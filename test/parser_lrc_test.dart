// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

void main() {
  group('parseLrc', () {
    test('parses plain line-by-line LRC', () {
      const lrc = '[00:00.00]First line\n[00:01.50]Second line';
      final result = parseLrc(lrc);
      expect(result.data.length, 2);
      expect(result.data[0].start, 0);
      expect(result.data[0].words.single.text, 'First line');
      expect(result.data[1].start, 1500);
      expect(result.data[1].words.single.text, 'Second line');
    });

    test(
      'keeps plain-LRC ends unknown instead of stretching to the next line',
      () {
        // Ordinary LRC only carries line starts. The parser must not invent an
        // end from the next line's start: otherwise there is no way to tell a
        // held line from an instrumental interlude.
        const lrc = '[00:10.00]First line\n[00:40.00]Second line';
        final result = parseLrc(lrc);

        expect(result.data[0].start, 10000);
        expect(result.data[0].end, isNull);
        expect(result.data[0].words.single.start, 10000);
        expect(result.data[0].words.single.end, isNull);
        expect(result.data[1].start, 40000);
        expect(result.data[1].end, isNull);
      },
    );

    test('keeps multi-stamp ends unknown as well', () {
      const lrc = '[00:10.00][00:20.00]shared text';
      final result = parseLrc(lrc);
      expect(result.data[0].end, isNull);
      expect(result.data[0].words.single.end, isNull);
      expect(result.data[1].end, isNull);
      expect(result.data[1].words.single.end, isNull);
    });

    test('honours an explicit trailing end marker on enhanced LRC', () {
      const lrc = '[00:00.00]Hello<00:03.00>';
      final result = parseLrc(lrc);
      final line = result.data.single;
      expect(line.start, 0);
      expect(line.end, 3000);
      expect(line.words.single.end, 3000);
    });

    test('honours an explicit trailing end marker on verbatim LRC', () {
      const lrc = '[00:00.00]Hel[00:00.40]lo[00:00.80]world[00:01.20]';
      final result = parseLrc(lrc);
      final line = result.data.single;
      expect(line.words, hasLength(3));
      expect(line.words[0].end, 400);
      expect(line.words[1].end, 800);
      expect(line.words[2].end, 1200);
      expect(line.end, 1200);
    });

    test('verbatim LRC without a trailing marker still has no end', () {
      const lrc = '[00:00.00]Hel[00:00.40]lo[00:00.80]world';
      final result = parseLrc(lrc);
      final line = result.data.single;
      expect(line.words[1].end, 800);
      expect(line.words[2].end, isNull);
      expect(line.end, isNull);
    });

    test('parses verbatim (word-by-word) LRC', () {
      const lrc = '[00:00.00]Hel[00:00.40]lo[00:00.80]world';
      final result = parseLrc(lrc);
      final line = result.data.single;
      expect(line.words.length, 3);
      expect(line.words[0].text, 'Hel');
      expect(line.words[1].text, 'lo');
      expect(line.words[2].text, 'world');
      expect(line.words[0].end, line.words[1].start);
    });

    test('extracts metadata tags', () {
      const lrc = '[ti:Title]\n[ar:Artist]\n[al:Album]\n[00:00.00]x';
      final result = parseLrc(lrc);
      expect(result.tags, {'ti': 'Title', 'ar': 'Artist', 'al': 'Album'});
    });

    test('parses enhanced inline format', () {
      const lrc = '[00:00.00]<00:00.50>He<00:01.00>llo';
      final result = parseLrc(lrc);
      final line = result.data.single;
      expect(line.words.length, 2);
      expect(line.words[0].text, 'He');
      expect(line.words[0].end, 1000);
      expect(line.words[1].text, 'llo');
    });

    test('judgeLyricsType distinguishes verbatim from line-by-line', () {
      final plain = LyricsData([
        LyricsLine(
          start: 0,
          end: 1000,
          words: [const LyricsWord(text: 'single')],
        ),
      ]);
      expect(judgeLyricsType(plain), LyricsType.lineByLine);

      final verbatim = LyricsData([
        LyricsLine(
          start: 0,
          end: 1000,
          words: [
            const LyricsWord(start: 0, end: 100, text: 'A'),
            const LyricsWord(start: 100, end: 200, text: 'B'),
          ],
        ),
      ]);
      expect(judgeLyricsType(verbatim), LyricsType.verbatim);
    });

    test(
      'judgeLyricsType stays verbatim when the last word end is unknown',
      () {
        // The final word of a verbatim/enhanced line has no end unless the file
        // carries an explicit marker; that must not downgrade the track type.
        expect(
          judgeLyricsType(parseLrc('[00:00.00]He[00:00.50]llo').data),
          LyricsType.verbatim,
        );
        expect(
          judgeLyricsType(parseLrc('[00:00.00]He<00:00.50>llo').data),
          LyricsType.verbatim,
        );
      },
    );

    test('parses multi-stamp NetEase-style lines', () {
      const lrc = '[00:00.00][00:01.50]shared line';
      final result = parseLrc(lrc);
      // Each timestamp gets its own line (matches upstream LDDC's parser
      // behavior).
      expect(result.data.lines, hasLength(2));
      expect(result.data[0].start, 0);
      expect(result.data[0].words.single.text, 'shared line');
      expect(result.data[1].start, 1500);
      expect(result.data[1].words.single.text, 'shared line');
    });

    test('parsePlaintext yields a single-word-per-line track', () {
      final data = parsePlaintext('alpha\nbeta\ngamma\n');
      expect(data.length, 3);
      expect(data[0].words.single.text, 'alpha');
      expect(data[2].words.single.text, 'gamma');
    });
  });
}
