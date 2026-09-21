/// Scanner/nettoyeur d'artistes, partagé par tous les points d'entrée qui
/// écrivent un nom d'artiste en base (extraction ID3, correction manuelle) —
/// évite qu'un même artiste tagué avec des espaces superflus d'un fichier à
/// l'autre (ex. "Daft Punk " et "Daft  Punk") ne finisse par créer deux
/// entrées distinctes dans `track_artists`.
class ArtistNameNormalizer {
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Trim + réduction des espaces multiples internes à un seul espace.
  static String normalize(String name) => name.trim().replaceAll(_whitespace, ' ');

  /// Découpe une chaîne d'artistes combinée (feat./ft./virgule/&/x) selon
  /// [splitPattern] puis normalise chaque partie — voir
  /// [MetadataExtractor._artistSplitPattern] pour le détail des frontières de
  /// mot qui empêchent de tronquer un nom comme "Daft Punk".
  static List<String> splitAndNormalize(String raw, RegExp splitPattern) {
    return raw.split(splitPattern).map(normalize).where((name) => name.isNotEmpty).toList();
  }
}
