/// Comptage de fréquence de mots-clés (Étape 4) — pure, sans dépendance à la
/// base : alimente le moteur de recommandation local à partir des tags
/// `Tracks.tags` (enrichissement iTunes, Étape 2). N'a aucun rôle dans le
/// choix de la Vibe, qui reste exclusivement manuel.
class KeywordStats {
  const KeywordStats._();

  static List<String> top(Iterable<List<String>> tagLists, {int limit = 3}) {
    final Map<String, int> counts = {};
    for (final tags in tagLists) {
      for (final tag in tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }

    final List<MapEntry<String, int>> sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).map((e) => e.key).toList();
  }
}
