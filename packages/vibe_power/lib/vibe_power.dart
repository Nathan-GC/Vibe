import 'package:flutter/services.dart';

/// Pont natif minimal (Android) du mode Focus de Vibe Player.
///
/// Plugin local plutôt que `wakelock_plus`/`battery_plus` : ceux-ci
/// imposaient un téléchargement Maven (AGP 8.12.1) impossible sur le poste
/// de build, et le code natif ne peut pas vivre dans `android/` (gitignoré).
class VibePower {
  const VibePower._();

  static const MethodChannel _methods = MethodChannel('vibe_power/methods');
  static const EventChannel _powerSaveEvents = EventChannel('vibe_power/power_save');

  /// Pose ou retire `WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON` sur la
  /// fenêtre de l'activité (réappliqué automatiquement si l'activité est
  /// recréée).
  static Future<void> setKeepScreenOn(bool enabled) => _methods.invokeMethod<void>('setKeepScreenOn', enabled);

  /// `PowerManager.isPowerSaveMode()`.
  static Future<bool> isPowerSaveMode() async => await _methods.invokeMethod<bool>('isPowerSaveMode') ?? false;

  /// Émet le nouvel état à chaque bascule du mode économie d'énergie
  /// (`ACTION_POWER_SAVE_MODE_CHANGED`), tant qu'il y a un abonné.
  static Stream<bool> get powerSaveModeChanges =>
      _powerSaveEvents.receiveBroadcastStream().map((event) => event == true);
}
