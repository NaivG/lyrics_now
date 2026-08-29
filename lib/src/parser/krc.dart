// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Kugou KRC parser (post-decryption plaintext).
//
// KRC is a line-based format with `[k:v]` metadata tags, `[start,dur]line`
// for time-stamped lines, and `<start,dur,?>word` for word-timed content.
// A separate `[language]` tag carries a base64-encoded JSON describing the
// romaji (type=0) and translation (type=1) lanes, parallel to the orig line
// order.
//
// Source: `LDDC\core\parser\krc.py`.

import 'dart:convert';

import '../models/lyrics_models.dart';

final RegExp _tagSplitPattern = RegExp(r'^\[(\w+):([^\]]*)\]$');
final RegExp _lineSplitPattern = RegExp(r'^\[(\d+),(\d+)\](.*)$');
final RegExp _wordSplitPattern = RegExp(
  r'(?:\[\d+,\d+\])?<(?<start>\d+),(?<duration>\d+),\d+>(?<content>(?:.(?!\d+,\d+,\d+>))*)',
);

class _LaneBuffer {
  _LaneBuffer(this.key);
  final String key;
  final List<LyricsLine> lines = <LyricsLine>[];
}

/// Parses decrypted KRC text into `(tags, multiLaneData)`.
///
/// The returned record's `data` field is a `Map<String, LyricsData>` keyed by
/// language lane — at minimum `{'orig': ...}`, plus optional `'roma'` and
/// `'ts'` lanes derived from the `[language]` tag.
({Map<String, String> tags, Map<String, LyricsData> data}) krc2MData(
  String krc,
) {
  final tags = <String, String>{};
  final orig = _LaneBuffer('orig');
  final roma = _LaneBuffer('roma');
  final ts = _LaneBuffer('ts');

  for (final raw in krc.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || !line.startsWith('[')) continue;

    final tagMatch = _tagSplitPattern.firstMatch(line);
    if (tagMatch != null) {
      tags[tagMatch.group(1)!] = tagMatch.group(2)!;
      continue;
    }

    final lineMatch = _lineSplitPattern.firstMatch(line);
    if (lineMatch == null) continue;

    final lineStart = int.parse(lineMatch.group(1)!);
    final lineEnd = lineStart + int.parse(lineMatch.group(2)!);
    final body = lineMatch.group(3)!;

    final words = <LyricsWord>[];
    for (final wordMatch in _wordSplitPattern.allMatches(body)) {
      final start = lineStart + int.parse(wordMatch.namedGroup('start')!);
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
    orig.lines.add(LyricsLine(start: lineStart, end: lineEnd, words: words));
  }

  final languageTag = tags['language'];
  if (languageTag != null && languageTag.trim().isNotEmpty) {
    try {
      final decoded = base64.decode(languageTag.trim());
      final payload = jsonDecode(utf8.decode(decoded)) as Map<String, Object?>;
      final content = payload['content'] as List<dynamic>? ?? const [];
      for (final entry in content) {
        final map = entry as Map<String, dynamic>;
        final type = map['type'] as int? ?? -1;
        final lyricContent = (map['lyricContent'] as List<dynamic>? ?? const [])
            .cast<dynamic>();
        if (type == 0) {
          _appendWordAligned(roma, orig, lyricContent);
        } else if (type == 1) {
          _appendLineAligned(ts, orig, lyricContent);
        }
      }
    } on Object {
      // Silently drop malformed language tags — orig lane still parses.
    }
  }

  final result = <String, LyricsData>{'orig': LyricsData(orig.lines)};
  if (roma.lines.isNotEmpty) result['roma'] = LyricsData(roma.lines);
  if (ts.lines.isNotEmpty) result['ts'] = LyricsData(ts.lines);
  return (tags: tags, data: result);
}

void _appendWordAligned(
  _LaneBuffer target,
  _LaneBuffer orig,
  List<dynamic> lyricContent,
) {
  var offset = 0;
  for (var i = 0; i < orig.lines.length; i++) {
    final line = orig.lines[i];
    if (line.words.every((w) => w.text.isEmpty)) {
      offset += 1;
      continue;
    }
    if (i - offset >= lyricContent.length) break;
    final words = lyricContent[i - offset] as List<dynamic>;
    final aligned = <LyricsWord>[];
    for (var j = 0; j < line.words.length && j < words.length; j++) {
      aligned.add(
        LyricsWord(
          start: line.words[j].start,
          end: line.words[j].end,
          text: words[j].toString(),
        ),
      );
    }
    target.lines.add(
      LyricsLine(start: line.start, end: line.end, words: aligned),
    );
  }
}

void _appendLineAligned(
  _LaneBuffer target,
  _LaneBuffer orig,
  List<dynamic> lyricContent,
) {
  for (var i = 0; i < orig.lines.length; i++) {
    if (i >= lyricContent.length) break;
    final line = orig.lines[i];
    final text = (lyricContent[i] as List<dynamic>).join(' ').trim();
    target.lines.add(
      LyricsLine(
        start: line.start,
        end: line.end,
        words: <LyricsWord>[
          LyricsWord(start: line.start, end: line.end, text: text),
        ],
      ),
    );
  }
}
