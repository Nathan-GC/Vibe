import '../../shared/text/title_cleaner.dart';

class SanitizedFilename {
  const SanitizedFilename({required this.title, required this.artist, required this.requiresUserReview});

  final String title;
  final String artist;
  final bool requiresUserReview;
}

/// Nettoie les noms de fichiers bruts : numéro de piste, qualité, tags parasites,
/// puis sépare Artiste / Titre. Ex. "01_Daft_Punk_-_One_More_Time_(Official_320kbps).mp3"
/// -> Artist: "Daft Punk", Title: "One More Time".
class FilenameSanitizer {
  // Ponctuation exigée juste après les chiffres (pas un simple espace) : sans
  // ça, "21 Savage - Song.mp3" perdait son "21" (pris pour un numéro de
  // piste) et devenait artist="Savage" — bug réel découvert avec de vrais
  // fichiers dont l'artiste commence par un chiffre (21 Savage, etc.).
  // Le "." n'autorise pas de chiffre juste après (lookahead) pour ne pas
  // confondre un numéro de piste avec un nombre décimal glissé dans le nom
  // (ex. "104.5SkyFM-..." une fréquence radio) ; "_"/"-" n'ont pas cette
  // restriction car appliqué en boucle (voir plus bas), ce qui permet de
  // dépiler un préfixe disque-piste répété (ex. "01-01- Title.mp3").
  static final RegExp _trackNumberPrefix = RegExp(r'^\s*\d{1,3}(?:\.(?!\d)|[_-])\s*');
  // Bruit technique laissé par certains convertisseurs : hash (MD5/SHA-like),
  // GUID, ou fragment de requête type "yt_v=<id>" — jamais du contenu de
  // titre. Un hash hexadécimal est distingué d'un vrai numéro ("Blink 182",
  // "Waltz No. 2", "Mambo No. 5" : uniquement des chiffres) en exigeant un
  // mélange chiffres+lettres a-f sur au moins 8 caractères — un mot anglais
  // de cette forme est quasi inexistant, contrairement à un simple nombre.
  // Ne mange que la ponctuation de liaison immédiate (espace/tiret/underscore),
  // jamais un mot entier avant le hash : une première version tentait
  // d'avaler aussi un éventuel nom réattribué juste avant ("-NomChaîne-hash"),
  // mais rien ne distingue ça d'un vrai "Artist - Title-hash" — testé, ça
  // supprimait le vrai titre ("One More Time-<guid>" perdait "One More Time").
  // Quelques fichiers réels gardent donc un segment "-NomChaîne" résiduel une
  // fois le hash seul retiré (ex. "...-Eurythmics-<hash>" -> "...-Eurythmics") :
  // limite acceptée plutôt que de risquer d'effacer un vrai titre.
  static final RegExp _idNoise = RegExp(
    r'[\s_-]*(?:'
    r'\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b|' // GUID
    r'\b(?=[0-9a-f]*[a-f])(?=[0-9a-f]*[0-9])[0-9a-f]{8,64}\b|' // hash hex mixte chiffres+lettres
    r'\b(?:yt[_-]?v|v|id)=[\w-]{6,}' // fragment de requête, ex. "yt_v=dQw4w9WgXcQ"
    r')[\s_-]*',
    caseSensitive: false,
  );
  // Coquille de parenthèse/crochet vidée par un nettoyage précédent (ex. un
  // id seul entre crochets, "[yt_v=...]") : sans ce filet, "[ ]" restait
  // affiché tel quel dans le titre final.
  static final RegExp _emptyBracketPair = RegExp(r'[\(\[\{]\s*[\)\]\}]');
  // Identifiant numérique en fin de nom, typique des fichiers issus de
  // convertisseurs/téléchargeurs en ligne : soit un long timestamp epoch
  // (ex. "_1747590913639", souvent sans séparateur net), soit un compteur
  // court mais toujours précédé d'un "_" explicite (ex. "_733", "_28") — le
  // "_" requis pour les IDs courts évite de tronquer un vrai titre numérique
  // séparé par un espace (ex. "Blink 182").
  static final RegExp _trailingNumericId = RegExp(r'[\s_]*\d{6,}$|_\d{1,5}$');
  static final RegExp _separator = RegExp(r'\s*[-–—]\s*');
  // Bruit terminal non parenthésé, laissé tel quel par TitleCleaner (qui ne
  // nettoie que le contenu entre parenthèses/crochets) — très fréquent dans
  // les noms compacts des convertisseurs YouTube (ex. "...-HQ", "... Lyrics",
  // "... Official Audio"). Appliqué en boucle : certains fichiers empilent
  // plusieurs suffixes ("-Lyrics" puis, une fois retiré, plus rien d'autre).
  static final RegExp _bareTrailingNoise = RegExp(
    r'[\s_-]+(?:official\s+)?(?:lyrics?|paroles?|audio|video|visuali[sz]er|hq)\s*$',
    caseSensitive: false,
  );
  // Insère un espace aux frontières de mots collés (style "TVGirl",
  // "IWannaBeYours") — fréquent dans les noms compacts sans espaces d'un
  // convertisseur en particulier. Purement additif (n'efface jamais rien),
  // donc sans risque sur les noms déjà correctement espacés.
  static final RegExp _camelCaseBoundary = RegExp(r'(?<=[a-zA-Z0-9])(?=[A-Z][a-z])');

  SanitizedFilename sanitizeFilename(String rawFilename) {
    final String withoutExtension = rawFilename.replaceAll(RegExp(r'\.[^.]+$'), '');

    String withoutTrackNumber = withoutExtension;
    String previous;
    do {
      previous = withoutTrackNumber;
      withoutTrackNumber = withoutTrackNumber.replaceFirst(_trackNumberPrefix, '');
    } while (withoutTrackNumber != previous);

    // Retiré avant le nettoyage des tags entre parenthèses et avant le
    // découpage artiste/titre : un GUID contient lui-même des tirets qui
    // fausseraient sinon la détection du séparateur artiste/titre.
    String withoutIdNoise = withoutTrackNumber.replaceAll(_idNoise, ' ');
    do {
      previous = withoutIdNoise;
      withoutIdNoise = withoutIdNoise.replaceFirst(_emptyBracketPair, ' ');
    } while (withoutIdNoise != previous);

    final String withoutNoise = withoutIdNoise.replaceAll(TitleCleaner.noiseTags, '');

    // Espacement des mots collés fait tôt, *avant* le dépiècement de l'ID et
    // du bruit terminal nu : sans ça, un suffixe comme "EnglishLyrics" ne
    // révèle jamais son "Lyrics" isolable (pas d'espace/underscore devant),
    // et le bruit ne peut plus être reconnu ensuite.
    final String spacedEarly = withoutNoise.replaceAllMapped(_camelCaseBoundary, (m) => ' ');

    String withoutTrailingId = spacedEarly;
    do {
      previous = withoutTrailingId;
      withoutTrailingId = withoutTrailingId.replaceFirst(_trailingNumericId, '');
    } while (withoutTrailingId != previous);

    String withoutBareNoise = withoutTrailingId;
    do {
      previous = withoutBareNoise;
      withoutBareNoise = withoutBareNoise.replaceFirst(_bareTrailingNoise, '');
    } while (withoutBareNoise != previous);

    final String normalized = withoutBareNoise.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

    final List<String> parts = _splitOnTopLevelSeparator(normalized);

    if (parts.length == 2) {
      // Un second segment qui ne fait que répéter (une partie de) l'artiste
      // n'est pas un vrai titre — signe d'une réattribution redondante
      // ajoutée par un convertisseur juste avant son id de téléchargement
      // (ex. "...Sweet Dreams (Are Made Of This)-Eurythmics-<hash>" une fois
      // le hash seul retiré : "Eurythmics" en second segment ne serait sinon
      // pris à tort pour le titre, avec l'artiste ET le vrai titre restés
      // collés côté "artiste"). Aucun faux positif plausible : un vrai titre
      // identique à un simple sous-mot du nom d'artiste n'existe pas en
      // pratique.
      if (_normalizeForComparison(parts[1]).isNotEmpty &&
          _normalizeForComparison(parts[0]).contains(_normalizeForComparison(parts[1]))) {
        // parts[0] seul (sans le tag redondant) plutôt que la chaîne
        // complète : le tag dupliqué n'apporte rien à afficher en révision.
        return SanitizedFilename(artist: 'Unknown', title: parts[0], requiresUserReview: true);
      }
      return SanitizedFilename(artist: parts[0], title: parts[1], requiresUserReview: false);
    }

    if (parts.length > 2) {
      // Séparateurs multiples (ex. plusieurs "-") : ambigu, best-effort + review manuelle.
      return SanitizedFilename(artist: parts.first, title: parts.sublist(1).join(' - '), requiresUserReview: true);
    }

    // Aucun séparateur trouvé : impossible de distinguer artiste/titre.
    return SanitizedFilename(artist: 'Unknown', title: normalized, requiresUserReview: true);
  }

  /// Découpe sur [_separator] en ignorant les tirets internes à une
  /// parenthèse/crochet/accolade — sans ça, un remix noté "(JENNIE Remix -
  /// Official Lyric Video)" ou un tag "(WSHHExclusive-OfficialMusicVideo)"
  /// fait croire à un séparateur artiste/titre supplémentaire là où il n'y en
  /// a pas, et casse un découpage par ailleurs sans ambiguïté.
  List<String> _splitOnTopLevelSeparator(String input) {
    final List<String> parts = [];
    final StringBuffer current = StringBuffer();
    int depth = 0;
    int i = 0;
    while (i < input.length) {
      final String char = input[i];
      if (char == '(' || char == '[' || char == '{') depth++;
      if (char == ')' || char == ']' || char == '}') depth = depth > 0 ? depth - 1 : 0;

      if (depth == 0) {
        final Match? match = _separator.matchAsPrefix(input, i);
        if (match != null && match.start == i) {
          parts.add(current.toString());
          current.clear();
          i = match.end;
          continue;
        }
      }
      current.write(char);
      i++;
    }
    parts.add(current.toString());
    return parts.map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  }

  static String _normalizeForComparison(String value) => value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
}
