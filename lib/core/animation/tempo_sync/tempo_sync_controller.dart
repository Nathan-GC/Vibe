import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Couche C de l'état global : ticker 60fps dérivé du BPM de la piste courante.
/// Volontairement isolée de Riverpod — s'abonne uniquement au `Stream<Duration>`
/// de position du PlayerController + au BPM déjà chargé en mémoire, pour ne
/// jamais déclencher de rebuild lié à la DB ou aux providers audio/thème.
class TempoSyncController extends ChangeNotifier {
  TempoSyncController({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  double _bpm = 120;
  double pulse = 0;
  // Secondes écoulées depuis le premier tick — sert de `u_time` monotone au
  // shader de particules (Vibe Engine), distinct de `pulse` (0..1 cyclique).
  double elapsedSeconds = 0;

  double get bpm => _bpm;

  void updateBpm(double bpm) => _bpm = bpm;

  void start() {
    if (!_ticker.isActive) _ticker.start();
  }

  void stop() {
    if (_ticker.isActive) _ticker.stop();
  }

  void _onTick(Duration elapsed) {
    final double beatsPerMs = _bpm / 60000;
    pulse = (elapsed.inMilliseconds * beatsPerMs) % 1.0;
    elapsedSeconds = elapsed.inMicroseconds / 1e6;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
