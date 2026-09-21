import 'dart:io';

import 'package:flutter/material.dart';

/// Cover art : s'agrandit avec drop-shadow au Play, rétrécit de 5% au Pause.
/// `imagePath` est double-usage (voir Tracks.coverArtPath) : chemin fichier
/// local extrait des tags ID3, ou URL HD renvoyée par l'enrichissement iTunes.
class AlbumArtReactive extends StatelessWidget {
  const AlbumArtReactive({super.key, required this.imagePath, this.isPlaying = false});

  final String? imagePath;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final String? path = imagePath;
    final ImageProvider? image =
        (path == null || path.isEmpty) ? null : (path.startsWith('http') ? NetworkImage(path) : FileImage(File(path)));

    return AnimatedScale(
      scale: isPlaying ? 1.0 : 0.95,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: isPlaying
              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 12))]
              : [],
          borderRadius: BorderRadius.circular(16),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Hero(
            tag: 'album-art',
            child: Container(
              width: 280,
              height: 280,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: image == null
                  ? Icon(Icons.music_note, size: 96, color: Theme.of(context).colorScheme.onSurfaceVariant)
                  : Image(
                      image: image,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          Icon(Icons.music_note, size: 96, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
