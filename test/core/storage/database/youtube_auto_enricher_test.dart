import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:playlist_app/core/networking/metadata_api_client/online_track_result.dart';
import 'package:playlist_app/core/networking/youtube/youtube_enricher_service.dart';
import 'package:playlist_app/core/storage/database/app_database.dart';
import 'package:playlist_app/core/storage/database/track_repository.dart';
import 'package:playlist_app/core/storage/database/youtube_auto_enricher.dart';

class _FakeYoutubeEnricherService extends YoutubeEnricherService {
  _FakeYoutubeEnricherService(this.results);
  final List<OnlineTrackResult> results;
  int callCount = 0;

  @override
  Future<List<OnlineTrackResult>> search({required String artist, required String title}) async {
    callCount++;
    return results;
  }
}

class _ThrowingYoutubeEnricherService extends YoutubeEnricherService {
  @override
  Future<List<OnlineTrackResult>> search({required String artist, required String title}) async {
    throw Exception('network error');
  }
}

void main() {
  late AppDatabase db;
  late TrackRepository repository;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repository = TrackRepository(db);
  });

  tearDown(() => db.close());

  Future<void> insertTrack({required String id, required String title, required List<String> artists}) async {
    await db.into(db.tracks).insert(
          TracksCompanion.insert(id: id, title: title, album: '', artists: artists, durationSeconds: 180, filePath: '/music/$id.mp3'),
        );
  }

  test('fills the cover art from the top YouTube result and reports success', () async {
    await insertTrack(id: 't1', title: 'Bootleg Mix', artists: ['Some DJ']);
    final enricher = YoutubeAutoEnricher(
      youtubeEnricherService: _FakeYoutubeEnricherService(const [
        OnlineTrackResult(artist: 'Some Channel', title: 'Bootleg Mix', coverArtUrl: 'https://i.ytimg.com/vi/x/maxresdefault.jpg'),
      ]),
      trackRepository: repository,
    );

    final bool ok = await enricher.enrichTrack(trackId: 't1', title: 'Bootleg Mix', artists: ['Some DJ']);

    expect(ok, isTrue);
    final track = await repository.findById('t1');
    expect(track!.coverArtPath, 'https://i.ytimg.com/vi/x/maxresdefault.jpg');
    expect(track.enrichmentStatus, EnrichmentStatus.success);
    // Jamais de correction automatique de Titre/Artiste depuis YouTube (nom de
    // chaîne non fiable) — contrairement à TrackAutoEnricher.
    expect(track.title, 'Bootleg Mix');
    expect(track.artists, ['Some DJ']);
  });

  test('does not overwrite an existing cover art', () async {
    await insertTrack(id: 't1', title: 'Bootleg Mix', artists: ['Some DJ']);
    await (db.update(db.tracks)..where((t) => t.id.equals('t1'))).write(const TracksCompanion(coverArtPath: Value('local/existing.jpg')));
    final enricher = YoutubeAutoEnricher(
      youtubeEnricherService: _FakeYoutubeEnricherService(const [
        OnlineTrackResult(artist: 'Some Channel', title: 'Bootleg Mix', coverArtUrl: 'https://i.ytimg.com/vi/x/maxresdefault.jpg'),
      ]),
      trackRepository: repository,
    );

    final bool ok = await enricher.enrichTrack(trackId: 't1', title: 'Bootleg Mix', artists: ['Some DJ']);

    expect(ok, isFalse);
    final track = await repository.findById('t1');
    expect(track!.coverArtPath, 'local/existing.jpg');
  });

  test('marks failedPermanently after maxEnrichmentAttempts empty results, then skips the API', () async {
    await insertTrack(id: 't1', title: 'Nothing Findable', artists: ['Unknown']);
    final service = _FakeYoutubeEnricherService(const []);
    final enricher = YoutubeAutoEnricher(youtubeEnricherService: service, trackRepository: repository);

    for (int i = 0; i < TrackRepository.maxEnrichmentAttempts; i++) {
      expect(await enricher.enrichTrack(trackId: 't1', title: 'Nothing Findable', artists: ['Unknown']), isFalse);
    }
    final track = await repository.findById('t1');
    expect(track!.enrichmentStatus, EnrichmentStatus.failedPermanently);

    final int callsBefore = service.callCount;
    expect(await enricher.enrichTrack(trackId: 't1', title: 'Nothing Findable', artists: ['Unknown']), isFalse);
    expect(service.callCount, callsBefore);
  });

  test('a network failure does not consume an attempt', () async {
    await insertTrack(id: 't1', title: 'Bootleg Mix', artists: ['Some DJ']);
    final enricher = YoutubeAutoEnricher(youtubeEnricherService: _ThrowingYoutubeEnricherService(), trackRepository: repository);

    final bool ok = await enricher.enrichTrack(trackId: 't1', title: 'Bootleg Mix', artists: ['Some DJ']);

    expect(ok, isFalse);
    final track = await repository.findById('t1');
    expect(track!.enrichmentStatus, EnrichmentStatus.pending);
    expect(track.enrichmentAttempts, 0);
  });

  test('skips tracks already marked requiresReview without calling the API', () async {
    await db.into(db.tracks).insert(
          TracksCompanion.insert(
            id: 't1',
            title: 'Sounds',
            album: '',
            artists: const ['Unknown'],
            durationSeconds: 180,
            filePath: '/music/t1.mp3',
            enrichmentStatus: const Value(EnrichmentStatus.requiresReview),
          ),
        );
    final service = _FakeYoutubeEnricherService(const [OnlineTrackResult(artist: 'Should Not', title: 'Be Used')]);
    final enricher = YoutubeAutoEnricher(youtubeEnricherService: service, trackRepository: repository);

    final bool ok = await enricher.enrichTrack(trackId: 't1', title: 'Sounds', artists: ['Unknown']);

    expect(ok, isFalse);
    expect(service.callCount, 0);
  });
}
