// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Timestamped LRC parser. Supports:
//
//   - LRC tag lines (`[ti:...]`, `[ar:...]`)
//   - Plain line-by-line LRC: `[mm:ss.xx]text`
//   - Verbatim LRC:        `[mm:ss.xx]word1[mm:ss.xx]word2`
//   - Enhanced LRC:        `[mm:ss.xx]<mm:ss.xx>word1<mm:ss.xx>word2<mm:ss.xx>`
//   - Multi-stamp lines (NetEase YRC): `[ss:ms][ss:ms]text`

import '../exceptions.dart';
import '../models/lyrics_models.dart';
import '../models/lyrics_type.dart';

/// Tag dictionary returned by the parser.
typedef LrcTags = Map<String, String>;

class LrcParseResult {
  LrcParseResult({required this.tags, required this.data});

  final LrcTags tags;
  final LyricsData data;
}

/// Time tag matcher: `[mm:ss.xx]` or `[mm:ss.xxx]`.
final RegExp _timeTagPattern = RegExp(
  r'\[(\d{1,3}):(\d{1,2})(?:\.(\d{1,3}))?\]',
);

/// `key:value` metadata tag.
final RegExp _metaTagPattern = RegExp(r'^\[(\w+):([^\]]*)\]$');

/// Enhanced inline word boundary: `<mm:ss.xx>` or `<mm:ss.xxx>`.
final RegExp _inlineBoundaryPattern = RegExp(
  r'<(\d{1,3}):(\d{1,2})(?:\.(\d{1,3}))?>',
);

/// Parse a single LRC document into `(tags, lines)`.
LrcParseResult parseLrc(String lrc) {
  if (lrc.trim().isEmpty) {
    throw LyricsParseException('Empty LRC content');
  }

  final tags = <String, String>{};
  final data = LyricsData();

  for (final rawLine in lrc.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;

    if (line[0] != '[') continue;

    final meta = _metaTagPattern.firstMatch(line);
    if (meta != null && !_timeTagPattern.hasMatch(line)) {
      tags[meta.group(1)!] = meta.group(2)!.trim();
      continue;
    }

    final matches = _timeTagPattern.allMatches(line).toList();
    if (matches.isEmpty) continue;

    final first = matches.first;
    final stripped = line.substring(first.end);

    if (_isEnhanced(stripped)) {
      data.add(_parseEnhanced(matches, line));
      continue;
    }
    if (_isMultiStamp(matches, line)) {
      _parseMultiStamp(matches, line, data);
      continue;
    }
    if (matches.length == 1) {
      data.add(_parseSingle(_msFromMatch(first), stripped));
      continue;
    }
    data.add(_parseVerbatim(matches, line));
  }

  data.sort();
  _fixupInlineStarts(data);
  _dropBlankLines(data);

  return LrcParseResult(tags: tags, data: data);
}

bool _isMultiStamp(List<RegExpMatch> matches, String originalLine) {
  if (matches.length < 2) return false;
  for (var i = 1; i < matches.length; i++) {
    if (matches[i].start != matches[i - 1].end) return false;
  }
  return matches.last.end < originalLine.length;
}

bool _isEnhanced(String strippedAfterFirstTag) {
  return strippedAfterFirstTag.contains('<');
}

int _msFromMatch(RegExpMatch m) {
  final mm = int.parse(m.group(1)!);
  final ss = int.parse(m.group(2)!);
  final msPart = m.group(3);
  final padded = (msPart ?? '0').padRight(3, '0');
  final frac = int.parse(padded);
  // 240 -> 240 ms; 12 -> 120 ms; 1 -> 100 ms (sub-decimal seconds).
  final ms = frac >= 100 ? frac : frac * 10;
  return ((mm * 60 + ss) * 1000) + ms;
}

LyricsLine _parseSingle(int startMs, String content) {
  return LyricsLine(
    start: startMs,
    end: null,
    words: <LyricsWord>[LyricsWord(start: startMs, end: null, text: content)],
  );
}

LyricsLine _parseEnhanced(List<RegExpMatch> stampMatches, String originalLine) {
  // Strip ALL leading stamps; pull out the inline `<...>` boundaries.
  var rest = originalLine;
  for (final m in stampMatches) {
    rest = rest.substring(m.end);
  }

  final boundaries = _inlineBoundaryPattern.allMatches(rest).toList();
  if (boundaries.isEmpty) {
    final start = _msFromMatch(stampMatches.first);
    return LyricsLine(
      start: start,
      end: null,
      words: <LyricsWord>[LyricsWord(start: start, end: null, text: rest)],
    );
  }

  final start = _msFromMatch(stampMatches.first);
  final words = <LyricsWord>[];

  // Leading text before the first `<...>` boundary (may be the whole content
  // if the inline boundary is the very first thing after the stamp).
  final initial = rest.substring(0, boundaries.first.start);
  if (initial.isNotEmpty) {
    words.add(
      LyricsWord(
        start: start,
        end: _msFromMatch(boundaries.first),
        text: initial,
      ),
    );
  }

  for (var i = 0; i < boundaries.length; i++) {
    final boundary = boundaries[i];
    final next = i + 1 < boundaries.length ? boundaries[i + 1] : null;

    final int wordStart;
    if (i == 0) {
      wordStart = start;
    } else {
      wordStart = _msFromMatch(boundaries[i - 1]);
    }

    final text = next == null
        ? rest.substring(boundary.end)
        : rest.substring(boundary.end, next.start);
    final wordEnd = next == null ? null : _msFromMatch(next);

    if (text.isNotEmpty) {
      words.add(LyricsWord(start: wordStart, end: wordEnd, text: text));
    }
  }

  return LyricsLine(start: start, end: null, words: words);
}

LyricsLine _parseVerbatim(List<RegExpMatch> matches, String originalLine) {
  // Each stamp in [stamp0][text0][stamp1][text1]... introduces a word. The
  // text after the LAST stamp is a trailing word (sometimes empty).
  final words = <LyricsWord>[];

  for (var i = 0; i < matches.length; i++) {
    final m = matches[i];
    final next = i + 1 < matches.length ? matches[i + 1] : null;
    final wordStart = _msFromMatch(m);
    final nextStart = next == null ? null : _msFromMatch(next);

    if (next != null) {
      // Text between this stamp and the next stamp.
      final text = originalLine.substring(m.end, next.start).trim();
      if (text.isNotEmpty) {
        words.add(LyricsWord(start: wordStart, end: nextStart, text: text));
      }
    } else {
      // After the last stamp: the rest of the line.
      final text = originalLine.substring(m.end).trim();
      if (text.isNotEmpty) {
        words.add(LyricsWord(start: wordStart, end: null, text: text));
      }
    }
  }

  return LyricsLine(
    start: _msFromMatch(matches.first),
    end: null,
    words: words,
  );
}

void _parseMultiStamp(
  List<RegExpMatch> matches,
  String originalLine,
  LyricsData output,
) {
  // NetEase multi-stamp lines: each `[mm:ss.xx]` becomes its own line with
  // the same text — matches LDDC's parser where every timestamp is its own
  // entry.
  final text = originalLine.substring(matches.last.end).trim();
  for (var i = 0; i < matches.length; i++) {
    final startMs = _msFromMatch(matches[i]);
    final endMs = i + 1 < matches.length ? _msFromMatch(matches[i + 1]) : null;
    output.add(
      LyricsLine(
        start: startMs,
        end: null,
        words: <LyricsWord>[LyricsWord(start: startMs, end: endMs, text: text)],
      ),
    );
  }
}

void _fixupInlineStarts(LyricsData data) {
  for (var i = 0; i < data.length; i++) {
    final line = data[i];
    if (line.words.isEmpty) continue;
    final next = i + 1 < data.length ? data[i + 1] : null;
    final fixedWords = <LyricsWord>[];
    for (var j = 0; j < line.words.length; j++) {
      final word = line.words[j];
      final int? newStart =
          word.start ?? (j == 0 ? line.start : line.words[j - 1].end);
      final int? newEnd;
      if (word.end != null) {
        newEnd = word.end;
      } else if (j + 1 < line.words.length) {
        newEnd = line.words[j + 1].start;
      } else {
        newEnd = next?.start;
      }
      fixedWords.add(LyricsWord(start: newStart, end: newEnd, text: word.text));
    }
    final newEnd = line.end ?? next?.start;
    data[i] = LyricsLine(start: line.start, end: newEnd, words: fixedWords);
  }
}

void _dropBlankLines(LyricsData data) {
  for (var i = data.lines.length - 1; i >= 0; i--) {
    if (data[i].words.isEmpty) {
      data.lines.removeAt(i);
    }
  }
}

/// Quick heuristic to detect whether a [LyricsData] is word-by-word, line-by-
/// line, or plain text.
LyricsType judgeLyricsType(LyricsData data) {
  if (data.isEmpty) return LyricsType.plainText;
  for (final line in data) {
    if (line.words.isEmpty) continue;
    if (line.words.length > 1) {
      final allTimed = line.words.every(
        (w) => w.start != null && w.end != null,
      );
      return allTimed ? LyricsType.verbatim : LyricsType.lineByLine;
    }
  }
  return LyricsType.lineByLine;
}

/// Parse plain (no timestamps) lyrics separated by line breaks.
LyricsData parsePlaintext(String raw) {
  final lines = LyricsData();
  for (final rawLine in raw.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    lines.add(
      LyricsLine(
        start: null,
        end: null,
        words: <LyricsWord>[LyricsWord(text: line)],
      ),
    );
  }
  return lines;
}
