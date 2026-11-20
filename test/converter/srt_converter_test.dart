import 'package:lyrics_now/src/converter/srt_converter.dart';
import 'package:lyrics_now/src/models/lyric_info.dart';
import 'package:lyrics_now/src/models/lyrics.dart';
import 'package:lyrics_now/src/models/lyrics_models.dart';
import 'package:lyrics_now/src/models/song_info.dart';
import 'package:lyrics_now/src/models/source.dart';
import 'package:lyrics_now/src/parser/lrc.dart';
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

    test('does not let a plain-LRC line span an interlude', () {
      final info = LyricInfo(
        source: Source.lrclib,
        songInfo: SongInfo(source: Source.lrclib, title: 'x'),
        duration: 180000,
      );
      final lyrics = Lyrics(info);
      lyrics['orig'] = parseLrc('[00:05.00]intro\n[00:30.00]verse').data;

      final out = srtConverter(lyrics.toFullTimestamp());
      // The first cue ends at 5 s + the default 8 s bound, not at 30 s.
      expect(out, contains('00:00:05,000 --> 00:00:13,000'));
      expect(out, isNot(contains('00:00:05,000 --> 00:00:30,000')));
    });
  });
}
