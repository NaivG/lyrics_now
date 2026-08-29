// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// NetEase Cloud Music YRC (verbatim word-timed) parser.
//
// Lines begin with `[start,duration]`; words look like `(start,duration,0)
// text`. When the line body carries no per-word pairs, a single LyricsWord
// spanning the line is recorded.
//
// Source: `LDDC\core\parser\yrc.py`.

import '../models/lyrics_models.dart';

final RegExp _lineSplitPattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
final RegExp _wordSplitPattern = RegExp(
  r"(?:\[\d+,\d+\])?\((?<start>\d+),(?<duration>\d+),\d+\)(?<content>(?:.(?!\d+,\d+,\d+\)))*)",
);

LyricsData yrc2Data(String yrc) {
  final result = LyricsData(<LyricsLine>[]);
  for (final raw in yrc.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || !line.startsWith('[')) continue;

    final lineMatch = _lineSplitPattern.firstMatch(line);
    if (lineMatch == null) continue;

    final lineStart = int.parse(lineMatch.group(1)!);
    final lineEnd = lineStart + int.parse(lineMatch.group(2)!);
    final body = lineMatch.group(3)!;

    final words = <LyricsWord>[];
    for (final wordMatch in _wordSplitPattern.allMatches(body)) {
      final start = int.parse(wordMatch.namedGroup('start')!);
      final end = start + int.parse(wordMatch.namedGroup('duration')!);
      words.add(
        LyricsWord(
          start: start,
          end: end,
          text: wordMatch.namedGroup('content') ?? '',
        ),
      );
    }
    if (words.isEmpty) {
      words.add(LyricsWord(start: lineStart, end: lineEnd, text: body));
    }
    result.add(LyricsLine(start: lineStart, end: lineEnd, words: words));
  }
  return result;
}
