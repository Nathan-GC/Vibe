import 'package:flutter_test/flutter_test.dart';
import 'package:playlist_app/core/networking/youtube/youtube_enricher_service.dart';

void main() {
  group('YoutubeEnricherService.cleanTitle', () {
    test('strips each documented noise tag', () {
      expect(YoutubeEnricherService.cleanTitle('Song Title (Official Video)'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title (Official Music Video)'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title [Clip Officiel]'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title (Lyrics)'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title (Lyrics Video)'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title [Official Audio]'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title (Audio)'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title [HD]'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title [4K]'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title (Prod. by Metro Boomin)'), 'Song Title');
      expect(YoutubeEnricherService.cleanTitle('Song Title [Slowed + Reverb]'), 'Song Title');
    });

    test('strips multiple stacked tags', () {
      expect(YoutubeEnricherService.cleanTitle('Song Title (Official Video) [HD]'), 'Song Title');
    });

    test('does not strip a parenthetical that merely contains a noise word among real content', () {
      expect(YoutubeEnricherService.cleanTitle('Song Title (Audio Description)'), 'Song Title (Audio Description)');
    });

    test('leaves a title with no noise tags untouched', () {
      expect(YoutubeEnricherService.cleanTitle('Daft Punk - One More Time'), 'Daft Punk - One More Time');
    });
  });
}
