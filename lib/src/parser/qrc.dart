// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// QQ Music cloud QRC parser.
//
// The wire format is an XML-style block:
//   `<Lyric_1 LyricType="1" LyricContent="...">` containing newline-separated
// `[start,dur]line` blocks. Lines wrapping only a single timestamp marker
// are recorded as empty lines (an instrumental pivot). Verbatim lines have
// `(start,dur)` per word inside them.
//
// Source: `LDDC\core\parser\qrc.py`.

import '../exceptions.dart';
import '../models/lyrics_models.dart';
import 'lrc.dart';

final RegExp _qrcPattern = RegExp(
  r'<Lyric_1 LyricType="1" LyricContent="(?<content>.*?)"/>',
  dotAll: true,
);

final RegExp _tagSplitPattern = RegExp(r'^\[(\w+):([^\]]*)\]$');

final RegExp _lineSplitPattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');

final RegExp _wordSplitPattern = RegExp(
  r'(?:\[\d+,\d+\])?'
  r'(?<content>(?:(?!\(\d+,\d+\)).)*)'
  r'\((?<start>\d+),(?<duration>\d+)\)',
);

final RegExp _wordTimestampOnly = RegExp(r'^\(\d+,\d+\)$');

/// Parses the QRC XML and returns `(tags, lyricsData)`.
///
/// Throws [LyricsParseException] when the input lacks the Lyric_1 wrapper.
({Map<String, String> tags, LyricsData data}) qrc2Data(String input) {
  final match = _qrcPattern.firstMatch(input);
  if (match == null || match.namedGroup('content') == null) {
    throw LyricsParseException(
      'Unsupported lyrics format (no Lyric_1 envelope)',
    );
  }
  final tags = <String, String>{};
  final data = LyricsData(<LyricsLine>[]);

  final content = match.namedGroup('content')!;
  for (final raw in content.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;

    final lineMatch = _lineSplitPattern.firstMatch(line);
    if (lineMatch != null) {
      final lineStart = int.parse(lineMatch.group(1)!);
      final lineEnd = lineStart + int.parse(lineMatch.group(2)!);
      final lineContent = lineMatch.group(3)!;

      if (_wordTimestampOnly.hasMatch(lineContent)) {
        data.add(
          LyricsLine(start: lineStart, end: lineEnd, words: <LyricsWord>[]),
        );
        continue;
      }

      final words = <LyricsWord>[];
      for (final wordMatch in _wordSplitPattern.allMatches(lineContent)) {
        final text = wordMatch.namedGroup('content');
        if (text == '\r') continue;
        final start = int.parse(wordMatch.namedGroup('start')!);
        final end = start + int.parse(wordMatch.namedGroup('duration')!);
        words.add(LyricsWord(start: start, end: end, text: text!));
      }
      if (words.isEmpty) {
        words.add(
          LyricsWord(start: lineStart, end: lineEnd, text: lineContent),
        );
      }
      data.add(LyricsLine(start: lineStart, end: lineEnd, words: words));
      continue;
    }

    final tagMatch = _tagSplitPattern.firstMatch(line);
    if (tagMatch != null) {
      tags[tagMatch.group(1)!] = tagMatch.group(2)!;
    }
  }
  return (tags: tags, data: data);
}

/// Smart dispatch used by both the QQ cloud provider and the local-file
/// loader. Falls back to `parsePlaintext` when neither envelope is found.
({Map<String, String> tags, LyricsData data}) qrcStrParse(String lyric) {
  if (_qrcPattern.hasMatch(lyric)) {
    return qrc2Data(lyric);
  }
  if (lyric.contains('[') && lyric.contains(']')) {
    try {
      final result = parseLrc(lyric);
      return (tags: Map<String, String>.from(result.tags), data: result.data);
    } on Object {
      // Fall through to plaintext.
    }
  }
  final plaintext = parsePlaintext(lyric);
  return (tags: <String, String>{}, data: plaintext);
}
