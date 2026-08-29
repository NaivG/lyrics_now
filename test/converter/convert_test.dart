import 'package:lyrics_now/src/converter/convert.dart';
import 'package:lyrics_now/src/models/lyrics.dart';
import 'package:lyrics_now/src/models/lyrics_models.dart';
import 'package:lyrics_now/src/models/lyrics_format.dart';
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
      words: [FSLyricsWord(start: 1000, end: 3000, text: 'Hello')],
    ),
  ]);
  return lyrics;
}

void main() {
  group('convert dispatch', () {
    test('lineByLineLrc format', () {
      final out = convert(_makeLyrics(), LyricsFormat.lineByLineLrc);
      expect(out, contains('[00:01.00]Hello'));
    });

    test('enhancedLrc format', () {
      final out = convert(_makeLyrics(), LyricsFormat.enhancedLrc);
      expect(out, contains('[00:01.00]Hello'));
    });

    test('verbatimLrc format', () {
      final out = convert(_makeLyrics(), LyricsFormat.verbatimLrc);
      expect(out, contains('[00:01.00]Hello'));
    });

    test('srt format', () {
      final out = convert(_makeLyrics(), LyricsFormat.srt);
      expect(out, contains('00:00:01,000'));
    });

    test('json format', () {
      final out = convert(_makeLyrics(), LyricsFormat.json);
      expect(out, contains('"version"'));
    });

    test('unsupported format throws', () {
      expect(
        () => convert(_makeLyrics(), LyricsFormat.qrc),
        throwsUnsupportedError,
      );
    });
  });
}
