import 'package:shared_preferences/shared_preferences.dart';

class PersistedPlayerState {
  const PersistedPlayerState({required this.queueTrackIds, required this.currentIndex});

  final List<String> queueTrackIds;
  final int currentIndex;
}

/// Persiste la queue + l'index courant pour reprendre au début du dernier
/// morceau actif au lancement (Étape 5 — "State Retention"). Écrit à chaque
/// changement de piste/pause plutôt qu'à un hook de fermeture précis : le
/// process peut être tué par l'OS à tout moment sur mobile.
class PlayerStateStorage {
  static const String _keyQueueIds = 'player.queue_track_ids';
  static const String _keyCurrentIndex = 'player.current_index';

  Future<void> save({required List<String> queueTrackIds, required int currentIndex}) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyQueueIds, queueTrackIds);
    await prefs.setInt(_keyCurrentIndex, currentIndex);
  }

  Future<PersistedPlayerState?> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String>? ids = prefs.getStringList(_keyQueueIds);
    final int? index = prefs.getInt(_keyCurrentIndex);
    if (ids == null || ids.isEmpty || index == null) return null;
    return PersistedPlayerState(queueTrackIds: ids, currentIndex: index);
  }
}
