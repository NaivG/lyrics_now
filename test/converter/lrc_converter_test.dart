import 'package:lyrics_now/src/converter/lrc_converter.dart';
import 'package:lyrics_now/src/models/lyrics.dart';
import 'package:lyrics_now/src/models/lyrics_format.dart';
import 'package:lyrics_now/src/models/lyrics_models.dart';
import 'package:lyrics_now/src/models/song_info.dart';
import 'package:lyrics_now/src/models/source.dart';
import 'package:test/test.dart';

FSLyrics _makeLyrics() {
  final lyrics = FSLyrics.fromSong(
    SongInfo(source: Source.lrclib, title: 'test'),
  );
  lyrics[TrackNames.orig] = FSLyricsData([
    FSLyricsLine(
      start: 1000,
      end: 3000,
      words: [
        FSLyricsWord(start: 1000, end: 1500, text: 'Hel'),
        FSLyricsWord(start: 1500, end: 2000, text: 'lo '),
        FSLyricsWord(start: 2000, end: 3000, text: 'world'),
      ],
    ),
    FSLyricsLine(
      start: 4000,
      end: 5000,
      words: [FSLyricsWord(start: 4000, end: 4500, text: 'Bye')],
    ),
  ]);
  return lyrics;
}

void main() {
  group('lrcConverter lineByLine', () {
    test('produces line-level LRC', () {
      final lyrics = _makeLyrics();
      final out = lrcConverter(lyrics, LyricsFormat.lineByLineLrc);
      expect(out, contains('[00:01.00]Hello world\n'));
      expect(out, contains('[00:04.00]Bye\n'));
    });
  });

  group('lrcConverter enhanced', () {
    test('produces enhanced LRC with inline timestamps', () {
      final lyrics = _makeLyrics();
      final out = lrcConverter(lyrics, LyricsFormat.enhancedLrc);
      expect(out, contains('[00:01.00]Hel<00:01.50>lo <00:02.00>world'));
      expect(out, contains('[00:04.00]Bye'));
    });
  });

  group('lrcConverter verbatim', () {
    test('produces one timestamp per word', () {
      final lyrics = _makeLyrics();
      final out = lrcConverter(lyrics, LyricsFormat.verbatimLrc);
      expect(out, contains('[00:01.00]Hel\n'));
      expect(out, contains('[00:01.50]lo \n'));
      expect(out, contains('[00:02.00]world\n'));
    });
  });

  group('lrcConverter empty', () {
    test('empty lyrics returns just tags', () {
      final lyrics = FSLyrics.fromSong(
        SongInfo(source: Source.lrclib, title: 'x'),
      );
      final out = lrcConverter(lyrics, LyricsFormat.lineByLineLrc);
      expect(out, isEmpty);
    });
  });
}
