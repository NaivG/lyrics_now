// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

void main() {
  group('Source', () {
    test('preserves LDDC integer ids', () {
      expect(Source.multi.id, 0);
      expect(Source.qm.id, 1);
      expect(Source.kg.id, 2);
      expect(Source.ne.id, 3);
      expect(Source.lrclib.id, 4);
      expect(Source.local.id, 100);
    });

    test('round-trips through fromId', () {
      for (final source in Source.values) {
        expect(Source.fromId(source.id), source);
      }
    });

    test('reports supported search types', () {
      expect(Source.qm.supports(SearchType.song), isTrue);
      expect(Source.qm.supports(SearchType.album), isTrue);
      expect(Source.lrclib.supports(SearchType.song), isTrue);
      expect(Source.lrclib.supports(SearchType.album), isFalse);
      expect(Source.local.supports(SearchType.song), isFalse);
    });
  });

  group('Artist', () {
    test('builds from a single string', () {
      final artist = Artist('Jay Chou');
      expect(artist.names, ['Jay Chou']);
      expect(artist.length, 1);
      expect(artist.str(), 'Jay Chou');
    });

    test('builds from an iterable and dedupes preserving order', () {
      final artist = Artist(['Jay Chou', 'Vincent Fang', 'Jay Chou']);
      expect(artist.names, ['Jay Chou', 'Vincent Fang']);
      expect(artist.length, 2);
      expect(artist.str(separator: ', '), 'Jay Chou, Vincent Fang');
    });

    test('empty string is dropped', () {
      final artist = Artist(['', 'Chou', '']);
      expect(artist.names, ['Chou']);
    });

    test('canonical equality ignores ordering', () {
      final a = Artist(['A', 'B', 'C']);
      final b = Artist(['C', 'A', 'B']);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('empty artist renders as empty string', () {
      expect(Artist().str(), '');
      expect(Artist().str(separator: ';'), '');
      expect(Artist().isEmpty, isTrue);
    });
  });

  group('SongInfo', () {
    test('duration formatting and artist title', () {
      final song = SongInfo(
        source: Source.qm,
        title: '青花瓷',
        artist: Artist(['Jay Chou']),
        album: '我很忙',
        duration: 240000, // 4 minutes
      );

      expect(song.artistTitle(), 'Jay Chou - 青花瓷');
      expect(song.fullTitle, '青花瓷');
      expect(song.formatDuration, '04:00');
      expect(song.formatDuration, isNot(''));
    });

    test('full title composes subtitle', () {
      final song = SongInfo(
        source: Source.qm,
        title: '青花瓷',
        subtitle: 'Live',
        artist: Artist('Jay Chou'),
      );
      expect(song.fullTitle, '青花瓷 (Live)');
      expect(song.artistTitle(full: true), 'Jay Chou - 青花瓷 (Live)');
    });

    test('copyWith preserves untouched fields', () {
      final song = SongInfo(
        source: Source.qm,
        title: '青花瓷',
        artist: Artist('Jay Chou'),
        duration: 1000,
      );
      final mutated = song.copyWith(album: 'Album');
      expect(mutated.album, 'Album');
      expect(mutated.title, '青花瓷');
      expect(mutated.duration, 1000);
    });
  });

  group('LyricsData + Lyrics', () {
    test('round-trips lines through toFullTimestamp', () {
      final info = LyricInfo(
        source: Source.lrclib,
        songInfo: SongInfo(source: Source.lrclib, title: 'Demo'),
      );
      final lyrics = Lyrics(info);
      lyrics.tags.addAll({'ti': 'Demo', 'ar': 'Tester'});
      lyrics['orig'] = LyricsData([
        LyricsLine(
          start: 1000,
          end: 2000,
          words: const [
            LyricsWord(start: 1000, end: 1500, text: 'hello'),
            LyricsWord(start: 1500, end: 2000, text: 'world'),
          ],
        ),
      ]);
      lyrics.types['orig'] = LyricsType.verbatim;

      final fs = lyrics.toFullTimestamp();
      expect(fs.length, 1);
      final line = fs['orig']!.first;
      expect(line.start, 1000);
      expect(line.end, 2000);
      expect(line.words.length, 2);
      expect(line.words.first.start, 1000);
      expect(line.words.last.end, 2000);
    });

    test(
      'inferredDuration walks the last word of orig when duration is null',
      () {
        final info = LyricInfo(
          source: Source.lrclib,
          songInfo: SongInfo(source: Source.lrclib, title: 'Demo'),
        );
        final lyrics = Lyrics(info);
        lyrics['orig'] = LyricsData([
          LyricsLine(
            start: 0,
            end: 12345,
            words: const [
              LyricsWord(start: 0, end: 1234, text: 'a'),
              LyricsWord(start: 1234, end: 12345, text: 'b'),
            ],
          ),
        ]);
        expect(lyrics.inferredDuration, 12345);
      },
    );

    test('addOffset produces a shifted copy', () {
      final info = LyricInfo(
        source: Source.lrclib,
        songInfo: SongInfo(source: Source.lrclib, title: 'Demo'),
      );
      final lyrics = Lyrics(info);
      lyrics['orig'] = LyricsData([
        LyricsLine(
          start: 0,
          end: 100,
          words: const [LyricsWord(start: 0, end: 100, text: 'hi')],
        ),
      ]);
      final shifted = lyrics.addOffset(500);
      final line = shifted['orig']!.first;
      expect(line.start, 500);
      expect(line.end, 600);
      expect(line.words.first.start, 500);
    });

    test('isInstrumental recognizes the placeholder line', () {
      final info = LyricInfo(
        source: Source.lrclib,
        songInfo: SongInfo(source: Source.lrclib, title: 'Track'),
        duration: 60000,
      );
      final lyrics = Lyrics(info);
      lyrics['orig'] = LyricsData([
        LyricsLine(words: const [LyricsWord(text: '纯音乐，请欣赏')]),
      ]);
      expect(lyrics.isInstrumental, isTrue);
    });
  });

  group('APIResultList', () {
    test('preserves items and supports ListMixin operations', () {
      final songs = [
        SongInfo(source: Source.qm, id: '1'),
        SongInfo(source: Source.kg, id: '2'),
      ];
      final list = APIResultList<SongInfo>(items: songs);

      expect(list.length, 2);
      expect(list[0].id, '1');
      expect(list[1].id, '2');

      final extended = list.toList()..add(SongInfo(source: Source.ne, id: '3'));
      expect(extended.length, 3);
    });

    test('merges range metadata safely', () {
      final first = APIResultList<SongInfo>(
        items: [SongInfo(source: Source.qm, id: '1')],
        sourceRanges: {Source.qm: (start: 0, end: 0, total: 1)},
      );
      final second = APIResultList<SongInfo>(
        items: [SongInfo(source: Source.kg, id: '2')],
        sourceRanges: {Source.kg: (start: 0, end: 0, total: 1)},
      );
      final combined = first.merged(second);
      expect(combined.length, 2);
      expect(combined.sources, containsAll([Source.qm, Source.kg]));
    });
  });
}
