import '../../../core/storage/database/app_database.dart';
import '../domain/artist_filter.dart';
import '../domain/artist_sort.dart';

abstract class ArtistRepository {
  /// Tous les morceaux crédités à [artistName] (y compris en featuring),
  /// filtrés et triés selon les contrôles de la vue Tab 1.
  Stream<List<Track>> watchArtistTracks(String artistName, {required ArtistFilter filter, required ArtistSort sort});

  /// Noms distincts de tous les artistes crédités sur au moins un morceau
  /// local, triés alphabétiquement — alimente le sélecteur "Ajouter par
  /// artiste" de l'éditeur de playlist (Feuille de route pt.9).
  Future<List<String>> fetchAllArtistNames();
}
