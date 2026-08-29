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
