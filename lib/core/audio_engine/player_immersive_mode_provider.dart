import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mode Canvas immersif du Master Player (voir MasterPlayerScreen._PlayerPage)
/// — sorti de l'état local du widget pour que la coque de navigation
/// (`_TabShell`, router.dart) puisse à la fois le lire (pour décider si le
/// bouton Retour doit d'abord réduire le mode immersif plutôt que quitter
/// l'app, Section 2.B) et l'écrire (pour l'y forcer depuis l'extérieur).
class PlayerImmersiveMode extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final NotifierProvider<PlayerImmersiveMode, bool> playerImmersiveModeProvider =
    NotifierProvider<PlayerImmersiveMode, bool>(PlayerImmersiveMode.new);
