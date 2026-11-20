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
///
/// Only timestamps the input actually provides are filled in. Ordinary
/// line-by-line LRC carries no line durations, so such lines keep
/// `end == null` rather than being stretched onto the next line's start:
/// consumers can then tell an unknown line length (and therefore a possible
/// instrumental interlude) apart from a known one. Explicit end markers
/// (trailing `<mm:ss.xx>` on enhanced lines, trailing `[mm:ss.xx]` on verbatim
/// lines) are still honoured.
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

    if (next != null) {
      // Text between this stamp and the next stamp.
      final text = originalLine.substring(m.end, next.start).trim();
      if (text.isNotEmpty) {
        words.add(
          LyricsWord(start: wordStart, end: _msFromMatch(next), text: text),
        );
      }
      continue;
    }

    // After the last stamp: the rest of the line.
    final text = originalLine.substring(m.end).trim();
    if (text.isNotEmpty) {
      words.add(LyricsWord(start: wordStart, end: null, text: text));
    } else if (words.isNotEmpty) {
      // A trailing stamp without text is an explicit end marker for the
      // previous word; honour it instead of stretching the line to the next
      // lyric line.
      final last = words.removeLast();
      words.add(LyricsWord(start: last.start, end: wordStart, text: last.text));
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
  // entry. The stamps only carry line starts; how long each repetition lasts
  // is unknown, so `end` stays `null` instead of borrowing the next stamp's
  // time (which would fabricate a duration and hide instrumental gaps).
  final text = originalLine.substring(matches.last.end).trim();
  for (final match in matches) {
    final startMs = _msFromMatch(match);
    output.add(
      LyricsLine(
        start: startMs,
        end: null,
        words: <LyricsWord>[LyricsWord(start: startMs, end: null, text: text)],
      ),
    );
  }
}

void _fixupInlineStarts(LyricsData data) {
  for (var i = 0; i < data.length; i++) {
    final line = data[i];
    if (line.words.isEmpty) continue;
    final fixedWords = <LyricsWord>[];
    for (var j = 0; j < line.words.length; j++) {
      final word = line.words[j];
      final int? newStart =
          word.start ?? (j == 0 ? line.start : line.words[j - 1].end);
      final int? newEnd;
      if (word.end != null) {
        newEnd = word.end;
      } else if (j + 1 < line.words.length) {
        // The next word's start is a real boundary inside this line.
        newEnd = line.words[j + 1].start;
      } else {
        // The last word has no known end. Do NOT borrow the next line's
        // start: an ordinary LRC line carries no duration information, and
        // fabricating one makes every instrumental interlude disappear.
        newEnd = null;
      }
      fixedWords.add(LyricsWord(start: newStart, end: newEnd, text: word.text));
    }
    // Only propagate an end that is actually known (e.g. a trailing inline
    // end marker on a verbatim/enhanced line); otherwise keep it unknown.
    data[i] = LyricsLine(
      start: line.start,
      end: line.end ?? fixedWords.last.end,
      words: fixedWords,
    );
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
///
/// Matches LDDC's `judge_lyrics_type`: a line carrying more than one word means
/// word-by-word timings are present even when the final word's end is unknown.
LyricsType judgeLyricsType(LyricsData data) {
  var type = LyricsType.plainText;
  for (final line in data) {
    if (line.words.length > 1) {
      type = LyricsType.verbatim;
      break;
    }
    if (line.start != null) type = LyricsType.lineByLine;
  }
  return type;
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
