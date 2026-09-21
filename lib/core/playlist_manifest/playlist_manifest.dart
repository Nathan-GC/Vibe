import 'manifest_track_ref.dart';

/// Manifeste JSON léger (métadonnées uniquement) d'une playlist — format
/// commun à l'export local, l'import Spotify, et le partage/fork (Étape 6).
class PlaylistManifest {
  const PlaylistManifest({
    required this.id,
    required this.title,
    required this.description,
    required this.version,
    required this.tags,
    required this.vibeStyle,
    required this.tracks,
    this.creatorHandle,
    this.originalCreator,
  });

  final String id;
  final String title;
  final String description;
  final int version;
  final List<String> tags;
  final String vibeStyle;
  final List<ManifestTrackRef> tracks;

  /// Auteur de CE manifeste au moment de l'export (utilisé pour l'attribution
  /// "Inspired by @X" lors d'un fork).
  final String? creatorHandle;

  /// Renseigné si ce manifeste est déjà lui-même issu d'un fork.
  final String? originalCreator;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'version': version,
        'tags': tags,
        'vibeStyle': vibeStyle,
        'creatorHandle': creatorHandle,
        'originalCreator': originalCreator,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

  factory PlaylistManifest.fromJson(Map<String, dynamic> json) {
    return PlaylistManifest(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String? ?? '',
      version: json['version'] as int? ?? 1,
      tags: (json['tags'] as List<dynamic>? ?? const []).cast<String>(),
      vibeStyle: json['vibeStyle'] as String? ?? 'minimal',
      creatorHandle: json['creatorHandle'] as String?,
      originalCreator: json['originalCreator'] as String?,
      tracks: (json['tracks'] as List<dynamic>? ?? const [])
          .map((t) => ManifestTrackRef.fromJson(t as Map<String, dynamic>))
          .toList(),
    );
  }
}
