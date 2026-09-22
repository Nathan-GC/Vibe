import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../storage/database/app_database.dart';
import '../storage/database/track_repository.dart';
import 'player_state_storage.dart';
import 'queue_controller.dart';

part 'player_controller.g.dart';

enum PlaybackStatus { idle, playing, paused }

/// 3 modes de lecture de la Queue (bouton dédié du Player) : `playlistOrder`
/// suit l'ordre affiché dans l'onglet Queue, `shuffle` le mélange (voir
/// QueueController.shuffle), `repeatOne` reboucle indéfiniment le morceau
/// courant à sa fin plutôt que d'avancer — un "suivant"/"précédent" manuel
/// reste toujours possible dans les 3 modes.
enum PlayerRepeatMode { playlistOrder, shuffle, repeatOne }

class PlayerSnapshot {
  const PlayerSnapshot({
    required this.status,
    this.currentTrack,
    this.currentPlaylistId,
    this.repeatMode = PlayerRepeatMode.playlistOrder,
  });

  final PlaybackStatus status;
  final Track? currentTrack;
  final String? currentPlaylistId;
  final PlayerRepeatMode repeatMode;

  PlayerSnapshot copyWith({
    PlaybackStatus? status,
    Track? currentTrack,
    String? currentPlaylistId,
    PlayerRepeatMode? repeatMode,
  }) {
    return PlayerSnapshot(
      status: status ?? this.status,
      currentTrack: currentTrack ?? this.currentTrack,
      currentPlaylistId: currentPlaylistId ?? this.currentPlaylistId,
      repeatMode: repeatMode ?? this.repeatMode,
    );
  }
}

/// Couche B de l'état global (lecteur natif) : joue la Queue en respectant le
/// découpage de silence (trim_start_ms/trim_end_ms, Étape 2), avance
/// automatiquement en fin de piste, et persiste la dernière piste active pour
/// reprendre à son début au prochain lancement (State Retention).
/// Isolée de la DB (lue en lecture seule) et du ticker d'animation tempo
/// (Couche C) — seule la position, exposée en Stream, est partagée.
@riverpod
class PlayerController extends _$PlayerController {
  final AudioPlayer _player = AudioPlayer();
  final PlayerStateStorage _storage = PlayerStateStorage();
  StreamSubscription<PlayerState>? _completionSub;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  int _currentIndex = -1;
  int _loadToken = 0;

  @override
  PlayerSnapshot build() {
    // Source unique de vérité pour `status` : `playerStateStream` reflète le
    // "playing" voulu de just_audio en direct (mis à jour de façon synchrone
    // dès l'appel à `_player.play()/pause()`, avant même la confirmation de
    // la plateforme native — voir just_audio.dart `AudioPlayer.play()`), donc
    // plus fiable que d'attendre la résolution du Future retourné par
    // `_player.play()`/`pause()` pour mettre à jour `state`. Bug réel observé
    // en conditions réelles (Tab 2) : après pause puis reprise, le son
    // repartait bien mais l'icône restait figée sur "Play" et les animations
    // de fond (TempoSyncController) ne redémarraient pas tant que
    // `state.status` n'avait pas été réconcilié par un second tap.
    _completionSub = _player.playerStateStream.listen((playerState) {
      if (playerState.processingState == ProcessingState.completed) {
        _onTrackCompleted();
        return;
      }
      if (state.currentTrack == null) return;
      final PlaybackStatus mapped = playerState.playing ? PlaybackStatus.playing : PlaybackStatus.paused;
      if (mapped != state.status) state = state.copyWith(status: mapped);
    });
    ref.onDispose(() {
      _completionSub?.cancel();
      _interruptionSub?.cancel();
      _becomingNoisySub?.cancel();
      _player.dispose();
    });

    Future.microtask(_restoreLastSession);
    unawaited(_configureAudioSession());
    return const PlayerSnapshot(status: PlaybackStatus.idle);
  }

  /// Audio Focus (Étape 5) : coupe la lecture sur appel entrant, notification
  /// d'une autre app qui prend le focus, ou casque débranché. La reprise
  /// automatique de la lecture à la fin d'une interruption transitoire (appel
  /// raccroché, notification prioritaire écoulée) EST le comportement
  /// officiel et voulu de Vibe Player — confirmé en QA (batterie Robustesse
  /// Système, Section 1) : redémarrer sans geste utilisateur est attendu ici,
  /// contrairement à une simple pause manuelle qui doit rester silencieuse.
  /// Cette reprise est gérée nativement par la négociation de focus audio
  /// d'ExoPlayer/just_audio côté Android dès que le focus est restitué ; ce
  /// listener ne gère explicitement que le début de l'interruption
  /// (`event.begin`), la fin n'a donc volontairement pas de branche dédiée.
  Future<void> _configureAudioSession() async {
    final AudioSession session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    _interruptionSub = session.interruptionEventStream.listen((event) {
      if (event.begin) pause();
    });

    _becomingNoisySub = session.becomingNoisyEventStream.listen((_) => pause());
  }

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  /// Déplacement manuel sur la barre de progression (Étape 3).
  Future<void> seek(Duration position) => _player.seek(position);

  /// Charge [tracks] dans la Queue et démarre la lecture à [startIndex]. Si le
  /// mode Aléatoire est actif, la nouvelle queue est immédiatement mélangée
  /// (le morceau de départ reste en tête) plutôt que jouée dans l'ordre
  /// affiché puis mélangée après coup.
  Future<void> playPlaylist(String playlistId, List<Track> tracks, {int startIndex = 0}) async {
    final List<String> ids = tracks.map((t) => t.id).toList();
    ref.read(queueControllerProvider.notifier).restore(ids);

    int effectiveStartIndex = startIndex;
    if (state.repeatMode == PlayerRepeatMode.shuffle && ids.isNotEmpty) {
      final String keepFirstId = ids[startIndex.clamp(0, ids.length - 1)];
      ref.read(queueControllerProvider.notifier).shuffle(keepFirst: keepFirstId);
      effectiveStartIndex = 0;
    }

    await playTrackAt(effectiveStartIndex, playlistId: playlistId);
  }

  /// Fait avancer cycliquement le mode de lecture : ordre de la playlist ->
  /// aléatoire -> répétition du titre -> ordre de la playlist. Bascule
  /// immédiatement l'ordre réel de la Queue à l'activation/désactivation du
  /// mode Aléatoire pour que la Queue affichée (Tab 2, page 2) corresponde
  /// toujours à l'ordre de lecture réel.
  Future<void> cycleRepeatMode() async {
    final PlayerRepeatMode next = switch (state.repeatMode) {
      PlayerRepeatMode.playlistOrder => PlayerRepeatMode.shuffle,
      PlayerRepeatMode.shuffle => PlayerRepeatMode.repeatOne,
      PlayerRepeatMode.repeatOne => PlayerRepeatMode.playlistOrder,
    };
    await _applyRepeatMode(next);
  }

  Future<void> _applyRepeatMode(PlayerRepeatMode mode) async {
    final bool enteringShuffle = mode == PlayerRepeatMode.shuffle && state.repeatMode != PlayerRepeatMode.shuffle;
    final bool leavingShuffle = mode != PlayerRepeatMode.shuffle && state.repeatMode == PlayerRepeatMode.shuffle;

    if (enteringShuffle) {
      ref.read(queueControllerProvider.notifier).shuffle(keepFirst: state.currentTrack?.id);
      _currentIndex = 0;
    } else if (leavingShuffle) {
      ref.read(queueControllerProvider.notifier).unshuffle();
      final String? currentId = state.currentTrack?.id;
      if (currentId != null) {
        final List<Track> tracks = await ref.read(queueTracksProvider.future);
        final int restoredIndex = tracks.indexWhere((t) => t.id == currentId);
        if (restoredIndex >= 0) _currentIndex = restoredIndex;
      }
    }

    state = state.copyWith(repeatMode: mode);
  }

  Future<void> playTrackAt(int startIndex, {String? playlistId}) async {
    final List<Track> tracks = await ref.read(queueTracksProvider.future);
    if (startIndex < 0 || startIndex >= tracks.length) return;

    // Jeton de génération : entre les deux `await` ci-dessous, un autre appel
    // (tap rapide sur "suivant", changement de playlist, complétion naturelle
    // qui se chevauche avec un swap manuel) peut démarrer et devenir le
    // véritable état courant. Sans ce garde, celui des deux qui finit en
    // second écraserait inconditionnellement `_currentIndex`/`state` même s'il
    // est désormais périmé — un bug réel observé en testant l'auto-avance
    // (Vibe Engine) : la Vibe affichée pouvait brièvement correspondre à une
    // ancienne playlist après un changement rapide.
    final int token = ++_loadToken;

    // Boucle (et non un simple appel unique) : un fichier référencé en base
    // peut avoir été supprimé/déplacé/corrompu hors de l'app (nettoyage
    // manuel du stockage, éjection de carte SD...). `setAudioSource` lève
    // alors une exception (`PlatformException`/`ExoPlaybackException`) —
    // bug réel reproduit : laissée non interceptée, elle remontait en
    // "Unhandled Exception" et figeait silencieusement le lecteur sur ce
    // morceau, sans jamais avancer. On tente donc chaque morceau suivant de
    // la Queue jusqu'au premier qui charge, plutôt que de s'arrêter net.
    for (int index = startIndex; index < tracks.length; index++) {
      final Track track = tracks[index];
      final int endMs = track.durationSeconds * 1000 - track.trimEndMs;

      try {
        await _player.setAudioSource(
          ClippingAudioSource(
            child: AudioSource.uri(Uri.file(track.filePath)),
            start: Duration(milliseconds: track.trimStartMs),
            end: track.trimEndMs > 0 ? Duration(milliseconds: endMs) : null,
          ),
        );
      } catch (_) {
        continue;
      }

      if (token != _loadToken) return;

      _currentIndex = index;
      // `copyWith` plutôt qu'un nouveau `PlayerSnapshot(...)` : préserve
      // `repeatMode` d'un changement de piste à l'autre (suivant/précédent,
      // auto-avance...) — sans quoi le mode Aléatoire/Répétition reviendrait
      // silencieusement à "ordre de la playlist" à chaque piste.
      //
      // `currentTrack` posé ICI, avant `_player.play()` plutôt qu'après sa
      // résolution : au tout premier appel natif suivant un cold start (warm-up
      // du plugin/service audio), la Future de `play()` peut mettre plusieurs
      // dizaines de secondes à se résoudre côté Dart alors que la lecture
      // native a déjà démarré. Tant que `currentTrack` restait null, le Lecteur
      // (titre, pochette, icône Play/Pause, fond Vibe) restait figé sur
      // "Aucune lecture" tout ce temps — le listener de `playerStateStream`
      // ci-dessus se tait lui aussi tant que `currentTrack == null` — jusqu'à
      // ce qu'un tap manuel force une resynchronisation. Bug réel observé lors
      // d'un retest QA (Vibe Neon "sans effet" au premier lancement d'une
      // playlist après ouverture de l'app).
      state = state.copyWith(status: PlaybackStatus.playing, currentTrack: track, currentPlaylistId: playlistId);
      unawaited(_player.play());

      unawaited(_storage.save(
        queueTrackIds: tracks.map((t) => t.id).toList(),
        currentIndex: index,
        currentPlaylistId: state.currentPlaylistId,
      ));
      unawaited(ref.read(trackRepositoryProvider).recordPlay(track.id));
      return;
    }

    // Plus aucun morceau lisible à partir de `startIndex` : rien à jouer.
    if (token == _loadToken) state = state.copyWith(status: PlaybackStatus.idle);
  }

  /// Séparés de [togglePlayPause] pour la notification média (Étape 5) :
  /// `audio_service` appelle `play`/`pause` distinctement selon le bouton
  /// pressé, jamais un simple bascule. `state.status` n'est volontairement
  /// plus assigné ici : le listener de `playerStateStream` dans [build] s'en
  /// charge en continu (voir son commentaire) — se fier à cette unique source
  /// plutôt que de dupliquer l'assignation ici évite tout risque de
  /// désynchronisation entre les deux.
  Future<void> play() async {
    if (state.currentTrack == null || _player.playing) return;
    await _player.play();
  }

  Future<void> pause() async {
    if (!_player.playing) return;
    await _player.pause();
  }

  Future<void> togglePlayPause() => _player.playing ? pause() : play();

  Future<void> next() async {
    final List<Track> tracks = await ref.read(queueTracksProvider.future);
    if (_currentIndex + 1 < tracks.length) await playTrackAt(_currentIndex + 1);
  }

  Future<void> previous() async {
    if (_currentIndex - 1 >= 0) await playTrackAt(_currentIndex - 1);
  }

  Future<void> _onTrackCompleted() async {
    // Un swap de source (`playTrackAt`) en cours peut émettre un événement
    // `completed` fantôme pour l'ancienne source qu'il est en train de
    // remplacer — capturer le jeton avant l'`await` puis le revérifier permet
    // de distinguer cet artefact d'une vraie fin de piste et d'ignorer le
    // premier, plutôt que d'avancer `_currentIndex` sur la base d'un état déjà
    // périmé.
    final int tokenAtCompletion = _loadToken;
    final List<Track> tracks = await ref.read(queueTracksProvider.future);
    if (tokenAtCompletion != _loadToken) return;

    if (state.repeatMode == PlayerRepeatMode.repeatOne && _currentIndex >= 0 && _currentIndex < tracks.length) {
      await playTrackAt(_currentIndex);
    } else if (_currentIndex + 1 < tracks.length) {
      await playTrackAt(_currentIndex + 1);
    } else if (tracks.isNotEmpty) {
      // Section 3.1 : fin du dernier morceau de la playlist -> relance
      // automatique au premier plutôt que de s'arrêter (`playlistId` omis,
      // comme la branche "morceau suivant" ci-dessus : `playTrackAt` retombe
      // alors sur `currentPlaylistId` déjà en cours via `copyWith`).
      await playTrackAt(0);
    } else {
      state = state.copyWith(status: PlaybackStatus.idle);
    }
  }

  Future<void> _restoreLastSession() async {
    final PersistedPlayerState? persisted = await _storage.load();
    if (persisted == null) return;

    ref.read(queueControllerProvider.notifier).restore(persisted.queueTrackIds);
    final List<Track> tracks = await ref.read(queueTracksProvider.future);
    if (tracks.isEmpty) return;

    final int index = persisted.currentIndex.clamp(0, tracks.length - 1);
    final Track track = tracks[index];

    try {
      await _player.setAudioSource(
        ClippingAudioSource(
          child: AudioSource.uri(Uri.file(track.filePath)),
          start: Duration(milliseconds: track.trimStartMs),
        ),
      );
    } catch (_) {
      // Fichier de la dernière session introuvable (supprimé/déplacé hors de
      // l'app entre deux lancements) : rien à restaurer plutôt que de faire
      // planter le démarrage — l'utilisateur relance une lecture normalement,
      // `state` reste `idle` (valeur par défaut de [build]).
      return;
    }
    // Chargé en pause au début du morceau — pas de lecture automatique au lancement.
    // `ref.mounted` : ce provider peut avoir été disposé pendant les `await`
    // ci-dessus si l'app a déjà navigué ailleurs (ex. redirection vers
    // l'onboarding du premier lancement, Étape 8) — écrire `state` après coup
    // lèverait sinon une exception.
    if (!ref.mounted) return;
    _currentIndex = index;
    // `currentPlaylistId` restauré ici (Bug critique QA, cold restart) : sans
    // lui, MasterPlayerScreen/activeVibeProvider ne retrouvaient jamais la
    // playlist active après un force-stop/relance et retombaient
    // indéfiniment sur leur repli neutre (dégradé gris, accentColor black87)
    // au lieu de la Vibe réellement configurée.
    state = PlayerSnapshot(status: PlaybackStatus.paused, currentTrack: track, currentPlaylistId: persisted.currentPlaylistId);
  }
}

/// Durée réellement lisible d'une piste, silences coupés déduits (voir
/// `ClippingAudioSource` dans `playTrackAt`) — partagée par la barre de
/// progression du Player et le `MediaItem` de la notification système, pour
/// qu'aucun des deux n'affiche la durée brute du fichier.
extension TrackPlaybackDuration on Track {
  Duration get effectivePlaybackDuration {
    final int playableMs = (durationSeconds * 1000 - trimStartMs - trimEndMs).clamp(0, 1 << 31).toInt();
    return Duration(milliseconds: playableMs);
  }
}

/// Position courante pour la barre de progression (Étape 3) — `autoDispose`
/// car inutile hors de l'écran Player affiché.
final positionStreamProvider = StreamProvider.autoDispose<Duration>((ref) {
  return ref.watch(playerControllerProvider.notifier).positionStream;
});

final durationStreamProvider = StreamProvider.autoDispose<Duration?>((ref) {
  return ref.watch(playerControllerProvider.notifier).durationStream;
});
