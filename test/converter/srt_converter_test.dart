import 'package:lyrics_now/src/converter/srt_converter.dart';
import 'package:lyrics_now/src/models/lyrics.dart';
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
      words: [FSLyricsWord(start: 1000, end: 1500, text: 'Hello')],
    ),
  ]);
  return lyrics;
}

void main() {
  group('srtConverter', () {
    test('produces basic SRT', () {
      final out = srtConverter(_makeLyrics());
      expect(out, contains('1\n'));
      expect(out, contains('00:00:01,000 --> 00:00:03,000'));
      expect(out, contains('Hello'));
    });

    test('empty lyrics', () {
      final lyrics = FSLyrics.fromSong(
        SongInfo(source: Source.lrclib, title: 'x'),
      );
      expect(srtConverter(lyrics), isEmpty);
    });
  });
}
