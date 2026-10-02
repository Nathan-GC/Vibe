import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Identifiants Spotify Developer (Client Credentials flow) fournis par
/// l'utilisateur — jamais embarqués dans l'app. Spotify n'expose aucun
/// endpoint public non authentifié listant les morceaux d'une playlist ;
/// sans ces identifiants, l'import Spotify se limite au titre/à la cover
/// (voir SpotifyPlaylistClient).
class SpotifyCredentials {
  const SpotifyCredentials({required this.clientId, required this.clientSecret});

  final String clientId;
  final String clientSecret;
}

/// Stockage chiffré (Keystore Android, `AndroidOptions()` par défaut de
/// flutter_secure_storage : RSA-OAEP + AES-GCM). Jusqu'à la v1.2, ces
/// identifiants étaient en clair dans SharedPreferences : ils sont déplacés
/// une fois vers le stockage chiffré puis effacés de l'ancien emplacement.
class SpotifyCredentialsStorage {
  static const String _keyClientId = 'spotify.client_id';
  static const String _keyClientSecret = 'spotify.client_secret';
  static const FlutterSecureStorage _secure = FlutterSecureStorage();

  Future<void> save(SpotifyCredentials credentials) async {
    await _secure.write(key: _keyClientId, value: credentials.clientId);
    await _secure.write(key: _keyClientSecret, value: credentials.clientSecret);
  }

  Future<SpotifyCredentials?> load() async {
    await _migrateFromPlainPreferences();
    final String? id = await _secure.read(key: _keyClientId);
    final String? secret = await _secure.read(key: _keyClientSecret);
    if (id == null || secret == null || id.isEmpty || secret.isEmpty) return null;
    return SpotifyCredentials(clientId: id, clientSecret: secret);
  }

  Future<void> _migrateFromPlainPreferences() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? id = prefs.getString(_keyClientId);
    final String? secret = prefs.getString(_keyClientSecret);
    if (id == null && secret == null) return;
    if (id != null && secret != null && await _secure.read(key: _keyClientId) == null) {
      await save(SpotifyCredentials(clientId: id, clientSecret: secret));
    }
    await prefs.remove(_keyClientId);
    await prefs.remove(_keyClientSecret);
  }
}
