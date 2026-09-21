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

class SpotifyCredentialsStorage {
  static const String _keyClientId = 'spotify.client_id';
  static const String _keyClientSecret = 'spotify.client_secret';

  Future<void> save(SpotifyCredentials credentials) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyClientId, credentials.clientId);
    await prefs.setString(_keyClientSecret, credentials.clientSecret);
  }

  Future<SpotifyCredentials?> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? id = prefs.getString(_keyClientId);
    final String? secret = prefs.getString(_keyClientSecret);
    if (id == null || secret == null || id.isEmpty || secret.isEmpty) return null;
    return SpotifyCredentials(clientId: id, clientSecret: secret);
  }
}
