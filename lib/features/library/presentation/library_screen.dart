import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/shared/widgets/enrichment_source_dialog.dart';
import '../../../core/shared/widgets/track_actions_sheet.dart';
import '../../../core/storage/database/app_database.dart';
import '../../../core/storage/database/duplicate_track_group.dart';
import '../../../core/storage/database/track_enricher.dart';
import '../../../core/storage/database/track_repository.dart';
import '../../../core/storage/scanner/scanned_track.dart';
import '../../../core/storage/storage_manager/imported_audio_file.dart';
import '../data/library_providers.dart';
import 'metadata_editor_modal.dart';

/// Bibliothèque locale : import manuel de MP3 depuis le stockage (copiés
/// automatiquement dans le dossier de l'app, voir StorageManagerService),
/// liste des morceaux déjà connus (Étape 3).
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _busy = false;
  String? _statusMessage;

  Future<void> _importFiles() async {
    final List<PlatformFile> picked =
        await FilePicker.pickFiles(type: FileType.audio);
    if (picked.isEmpty) return;

    setState(() {
      _busy = true;
      _statusMessage = 'Import 0 / ${picked.length}...';
    });

    try {
      final storageManager = ref.read(storageManagerServiceProvider);
      final scanService = ref.read(libraryScanServiceProvider);
      final repository = ref.read(trackRepositoryProvider);

      int imported = 0;
      int tooShort = 0;
      int failed = 0;
      String? lastError;
      // Renommés (repli FilenameSanitizer, pas de tag ID3 exploitable) parmi
      // ce lot — seuls ceux-là seront enrichis automatiquement juste après,
      // une fois TOUS les fichiers du lot renommés et persistés (phase 1
      // renommage, puis phase 2 enrichissement, jamais entrelacées).
      final List<ScannedTrack> renamedTracks = [];

      for (int i = 0; i < picked.length; i++) {
        final String? path = picked[i].path;
        if (path != null) {
          try {
            final ImportedAudioFile copied =
                await storageManager.importAudioFile(File(path));
            final ScannedTrack? track =
                await scanService.processImportedFile(copied);
            if (track != null) {
              await repository.upsertTrack(track);
              imported++;
              if (track.wasRenamedFromFilename) renamedTracks.add(track);
            } else {
              tooShort++;
            }
          } catch (error) {
            // Distingué de "trop court" : un import qui échoue (stockage,
            // permission, fichier corrompu...) doit rester visible plutôt que
            // de se fondre dans les morceaux légitimement ignorés — c'est
            // justement ce qui rendait un vrai problème indétectable depuis
            // l'app installée sur téléphone.
            failed++;
            lastError = error.toString();
          }
        } else {
          failed++;
        }

        if (mounted) {
          setState(
              () => _statusMessage = 'Import ${i + 1} / ${picked.length}...');
        }
      }

      // Import manuel : enrichissement automatique des morceaux renommés via
      // iTunes exclusivement, sans aucune question posée à l'utilisateur —
      // même principe que le premier scan (voir "Recadrage du Workflow
      // d'Enrichissement"). Seul le bouton étoile ✨ ("Enrichir tout")
      // propose un choix de source.
      int enriched = 0;
      if (renamedTracks.isNotEmpty && mounted) {
        final TrackEnricher enricher = ref.read(trackAutoEnricherProvider);
        for (int i = 0; i < renamedTracks.length; i++) {
          if (mounted) {
            setState(() => _statusMessage =
                'Enrichissement ${i + 1} / ${renamedTracks.length}...');
          }
          final ScannedTrack track = renamedTracks[i];
          final bool ok = await enricher.enrichTrack(
            trackId: track.id,
            title: track.title,
            artists: track.artists,
          );
          if (ok) enriched++;
        }
      }

      if (!mounted) return;
      final String summary = [
        '$imported importé(s)',
        if (renamedTracks.isNotEmpty)
          '$enriched/${renamedTracks.length} renommé(s) enrichi(s)',
        if (tooShort > 0) '$tooShort trop court(s) ou illisible(s)',
        if (failed > 0)
          '$failed échec(s)${lastError == null ? '' : ' : $lastError'}',
      ].join(', ');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(summary)));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Import impossible : $error')));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _statusMessage = null;
        });
      }
    }
  }

  void _openMetadataEditor(Track track) {
    showDialog<void>(
        context: context,
        builder: (context) => MetadataEditorModal(track: track));
  }

  /// Choix de la source pour un enrichissement global (Section 2.1) —
  /// affiché une fois par lancement d'"Enrichir tout" ou post-import, jamais
  /// pour un enrichissement individuel (voir MetadataEditorModal pour le
  /// choix de source par morceau). `null` si l'utilisateur annule.
  Future<EnrichmentSource?> _pickEnrichmentSource() =>
      showEnrichmentSourceDialog(context);

  TrackEnricher _enricherFor(EnrichmentSource source) => switch (source) {
        EnrichmentSource.itunes => ref.read(trackAutoEnricherProvider),
        EnrichmentSource.youtube => ref.read(youtubeAutoEnricherProvider),
      };

  /// Scanner de nettoyage des artistes (Feuille de route Vibe v5) : fusionne
  /// les variantes de casse d'un même nom ("DAFT PUNK"/"daft punk") sous une
  /// unique entité en Title Case.
  Future<void> _mergeArtists() async {
    final int mergedGroups =
        await ref.read(trackRepositoryProvider).mergeDuplicateCaseArtists();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mergedGroups == 0
              ? 'Aucun doublon de casse trouvé.'
              : '$mergedGroups artiste(s) fusionné(s).',
        ),
      ),
    );
  }

  /// Cherche la meilleure correspondance pour [track] via [enricher] (iTunes
  /// ou YouTube, voir [_pickEnrichmentSource]) et enrichit pochette HD /
  /// genre / époque en base. Non destructif (voir
  /// TrackRepository.enrichFromOnlineMetadata) : sûr à relancer.
  Future<bool> _enrichTrack(Track track, TrackEnricher enricher) {
    return enricher.enrichTrack(
        trackId: track.id, title: track.title, artists: track.artists);
  }

  /// Enrichissement individuel (bouton rapide sur un morceau) — toujours
  /// iTunes : pas de sélection de source pour ce cas précis (voir Section
  /// 2.1, réservée à "Enrichir tout"/post-import), le choix par morceau se
  /// fait plutôt dans MetadataEditorModal (Section 2.3).
  Future<void> _enrichSingle(Track track) async {
    final TrackEnricher enricher = ref.read(trackAutoEnricherProvider);
    bool found = false;
    for (int attempt = 1;
        attempt <= _maxEnrichmentPasses && !found;
        attempt++) {
      found = await _enrichTrack(track, enricher);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(found
              ? 'Pochette et genres mis à jour'
              : 'Aucune correspondance trouvée')),
    );
  }

  /// Enrichit tous les morceaux sans pochette ni mots-clés — l'espacement des
  /// requêtes iTunes est géré côté [MetadataApiClient] (throttle + reprise
  /// sur blocage de débit), pas ici.
  ///
  /// Boucle de nouvelles tentatives (Feuille de route pt.4) : une passe seule
  /// laissait parfois des morceaux non enrichis (timeout ponctuel, requête
  /// trop proche de la précédente...) sans que l'utilisateur ait de moyen de
  /// les retenter autrement qu'en rappelant "Enrichir tout" manuellement —
  /// jusqu'à 3 passes successives, chacune ne retraitant que ce qui manque
  /// encore, et on s'arrête dès qu'une passe n'enrichit plus rien de nouveau.
  static const int _maxEnrichmentPasses = 3;

  Future<void> _enrichLibrary() async {
    List<Track> all = await ref.read(libraryTracksProvider.future);
    List<Track> targets = all.where(trackNeedsEnrichment).toList();
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Rien à enrichir.')));
      }
      return;
    }

    final EnrichmentSource? source = await _pickEnrichmentSource();
    if (source == null || !mounted) return;
    final TrackEnricher enricher = _enricherFor(source);

    setState(() => _busy = true);

    int totalEnriched = 0;
    final int totalTargets = targets.length;

    for (int pass = 1;
        pass <= _maxEnrichmentPasses && targets.isNotEmpty;
        pass++) {
      int enrichedThisPass = 0;
      for (int i = 0; i < targets.length; i++) {
        if (mounted) {
          setState(() => _statusMessage =
              'Enrichissement (passe $pass/$_maxEnrichmentPasses) ${i + 1} / ${targets.length}...');
        }
        if (await _enrichTrack(targets[i], enricher)) {
          enrichedThisPass++;
          totalEnriched++;
        }
      }

      if (enrichedThisPass == 0) {
        break; // aucun progrès cette passe : inutile de retenter.
      }

      all = await ref.read(libraryTracksProvider.future);
      targets = all.where(trackNeedsEnrichment).toList();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('$totalEnriched / $totalTargets morceau(x) enrichi(s)')),
    );
    setState(() {
      _busy = false;
      _statusMessage = null;
    });

    await _proposeMergeArtists();
  }

  /// Proposée une fois l'enrichissement global terminé (voir "Recadrage du
  /// Workflow d'Enrichissement", 1.C) : l'enrichissement révèle souvent de
  /// nouveaux doublons de casse (ex. "DAFT PUNK" venu d'un tag ID3 vs "Daft
  /// Punk" déjà normalisé) — proposer la fusion tout de suite plutôt que de
  /// laisser l'utilisateur redécouvrir le bouton dédié.
  Future<void> _proposeMergeArtists() async {
    if (!mounted) return;
    final bool? proceed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fusionner les artistes en double ?'),
        content: const Text(
          'L\'enrichissement peut avoir révélé des variantes de casse du même artiste (ex. "DAFT PUNK" / "Daft Punk").',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Plus tard')),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Fusionner')),
        ],
      ),
    );
    if (proceed == true) await _mergeArtists();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Track>> allTracks = ref.watch(libraryTracksProvider);
    final AsyncValue<List<Track>> needsReviewTracks =
        ref.watch(needsReviewTracksProvider);
    final List<Track> needsEnrichmentTracks =
        ref.watch(tracksNeedingEnrichmentProvider);
    final List<DuplicateTrackGroup> duplicateGroups =
        ref.watch(duplicateTrackGroupsProvider).value ?? const [];
    final bool reviewFilterActive = ref.watch(libraryReviewFilterProvider);
    final bool enrichmentFilterActive =
        ref.watch(libraryEnrichmentFilterProvider);
    final LibrarySort sort = ref.watch(librarySortProvider);
    final int needsReviewCount = needsReviewTracks.maybeWhen(
        data: (data) => data.length, orElse: () => 0);
    final int needsEnrichmentCount = needsEnrichmentTracks.length;

    final AsyncValue<List<Track>> tracks = reviewFilterActive
        ? needsReviewTracks
        : enrichmentFilterActive
            ? AsyncValue.data(needsEnrichmentTracks)
            : allTracks;

    // Ergonomie navigation Android (2.B) : un filtre actif est un état de la
    // page, pas une vraie route/modale — le bouton Retour doit d'abord
    // l'effacer avant de vraiment quitter cette page.
    final bool filterActive = reviewFilterActive || enrichmentFilterActive;

    return PopScope(
      canPop: !filterActive,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (reviewFilterActive) {
          ref.read(libraryReviewFilterProvider.notifier).toggle();
        }
        if (enrichmentFilterActive) {
          ref.read(libraryEnrichmentFilterProvider.notifier).toggle();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bibliothèque'),
          actions: [
            PopupMenuButton<LibrarySort>(
              icon: const Icon(Icons.sort),
              tooltip: 'Trier',
              initialValue: sort,
              onSelected: (value) =>
                  ref.read(librarySortProvider.notifier).setSort(value),
              itemBuilder: (context) => LibrarySort.values
                  .map((value) =>
                      PopupMenuItem(value: value, child: Text(value.label)))
                  .toList(),
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome_outlined),
              tooltip: 'Enrichir les pochettes et genres manquants',
              onPressed: _busy ? null : _enrichLibrary,
            ),
            IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: 'Fusionner les artistes en double (casse)',
              onPressed: _busy ? null : _mergeArtists,
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Importer des MP3'),
                  onPressed: _busy ? null : _importFiles,
                ),
              ),
            ),
            if (_busy)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Column(
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 4),
                    Text(_statusMessage ?? '',
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            if (needsReviewCount > 0 ||
                needsEnrichmentCount > 0 ||
                duplicateGroups.isNotEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    children: [
                      if (needsReviewCount > 0)
                        FilterChip(
                          label: Text('À vérifier ($needsReviewCount)'),
                          avatar: const Icon(Icons.warning_amber_outlined,
                              size: 18, color: Colors.amber),
                          selected: reviewFilterActive,
                          onSelected: (_) => ref
                              .read(libraryReviewFilterProvider.notifier)
                              .toggle(),
                        ),
                      if (needsEnrichmentCount > 0)
                        FilterChip(
                          label: Text('À enrichir ($needsEnrichmentCount)'),
                          avatar:
                              const Icon(Icons.auto_awesome_outlined, size: 18),
                          selected: enrichmentFilterActive,
                          onSelected: (_) => ref
                              .read(libraryEnrichmentFilterProvider.notifier)
                              .toggle(),
                        ),
                      // Alerte doublons stricts (Titre + Artiste identiques) —
                      // navigue vers un écran dédié plutôt qu'un filtre en
                      // place : chaque groupe se corrige avec l'éditeur de
                      // métadonnées, pas avec un simple filtrage de la liste.
                      if (duplicateGroups.isNotEmpty)
                        ActionChip(
                          label: Text(
                              'Doublons détectés (${duplicateGroups.length})'),
                          avatar: const Icon(Icons.content_copy_outlined,
                              size: 18, color: Colors.redAccent),
                          onPressed: () =>
                              context.push('/space/library/duplicates'),
                        ),
                    ],
                  ),
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: tracks.when(
                data: (unsorted) {
                  if (unsorted.isEmpty) {
                    return const Center(
                        child: Text('Aucun morceau — importe des MP3.'));
                  }
                  final List<Track> data = sortLibraryTracks(unsorted, sort);
                  return ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final Track track = data[index];
                      final int minutes = track.durationSeconds ~/ 60;
                      final int seconds = track.durationSeconds % 60;
                      return ListTile(
                        leading: _CoverThumbnail(
                            path: track.coverArtPath,
                            needsReview: track.requiresUserReview),
                        title: Text(track.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              [
                                track.artists.join(', '),
                                if (track.album.isNotEmpty) track.album
                              ].join(' · '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (track.tags.isNotEmpty)
                              Text(
                                track.tags.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(fontStyle: FontStyle.italic),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                '$minutes:${seconds.toString().padLeft(2, '0')}'),
                            IconButton(
                              icon: const Icon(Icons.auto_awesome_outlined,
                                  size: 20),
                              tooltip: 'Enrichir (pochette HD + genres)',
                              onPressed: () => _enrichSingle(track),
                            ),
                          ],
                        ),
                        // À tout moment, pas seulement pour les morceaux "À
                        // vérifier" : un titre déjà enrichi doit pouvoir être
                        // ré-enrichi ou renommé sans repasser par le badge.
                        onTap: () => _openMetadataEditor(track),
                        onLongPress: () =>
                            TrackActionsSheet.show(context, track),
                      );
                    },
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(child: Text('Erreur : $error')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `coverArtPath` est double-usage (voir Tracks.coverArtPath) : chemin fichier
/// local extrait des tags ID3, ou URL HD renvoyée par l'enrichissement iTunes.
class _CoverThumbnail extends StatelessWidget {
  const _CoverThumbnail({required this.path, required this.needsReview});

  final String path;
  final bool needsReview;

  @override
  Widget build(BuildContext context) {
    if (needsReview) {
      return const CircleAvatar(
          child: Icon(Icons.warning_amber_outlined, color: Colors.amber));
    }
    if (path.isEmpty) {
      return const CircleAvatar(child: Icon(Icons.music_note_outlined));
    }

    final ImageProvider image = path.startsWith('http')
        ? NetworkImage(path)
        : FileImage(File(path)) as ImageProvider;
    return CircleAvatar(
        backgroundImage: image, onBackgroundImageError: (_, __) {});
  }
}
