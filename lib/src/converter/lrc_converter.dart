// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import '../models/lyrics.dart';
import '../models/lyrics_models.dart';
import '../models/lyrics_format.dart';

String lrcConverter(
  FSLyrics lyrics,
  LyricsFormat format, {
  List<String> langsOrder = const ['orig', 'ts', 'roma'],
  int msDigits = 2,
  bool addEndTimestamp = false,
}) {
  final buffer = StringBuffer();
  _writeTags(buffer, lyrics.tags);

  final lines = _getLyricsLines(lyrics, langsOrder);
  if (lines.isEmpty) return buffer.toString();

  final msDiv = msDigits == 3 ? 1 : 10;
  final msPad = msDigits;

  switch (format) {
    case LyricsFormat.lineByLineLrc:
      _writeLineByLine(buffer, lines, msDiv, msPad);
    case LyricsFormat.enhancedLrc:
      _writeEnhanced(buffer, lines, msDiv, msPad, addEndTimestamp);
    case LyricsFormat.verbatimLrc:
      _writeVerbatim(buffer, lines, msDiv, msPad, addEndTimestamp);
    default:
      _writeLineByLine(buffer, lines, msDiv, msPad);
  }

  return buffer.toString();
}

void _writeTags(StringBuffer buffer, Map<String, String> tags) {
  for (final entry in tags.entries) {
    buffer.writeln('[${entry.key}:${entry.value}]');
  }
}

List<_LineBlock> _getLyricsLines(FSLyrics lyrics, List<String> langsOrder) {
  final result = <_LineBlock>[];
  final orig = lyrics[TrackNames.orig];
  if (orig == null || orig.isEmpty) return result;

  for (var i = 0; i < orig.length; i++) {
    final origLine = orig[i];
    final texts = <String>[];
    for (final lang in langsOrder) {
      if (lang == TrackNames.orig) {
        texts.add(origLine.text);
        continue;
      }
      final track = lyrics[lang];
      if (track == null || i >= track.length) {
        texts.add('');
        continue;
      }
      texts.add(track[i].text);
    }
    if (texts.every((t) => t.isEmpty)) continue;
    result.add(
      _LineBlock(
        start: origLine.start,
        end: origLine.end,
        origWords: origLine.words,
        texts: texts,
      ),
    );
  }
  return result;
}

void _writeLineByLine(
  StringBuffer buffer,
  List<_LineBlock> lines,
  int msDiv,
  int msPad,
) {
  for (final block in lines) {
    buffer.write(_lrcTimestamp(block.start, msDiv, msPad));
    final text = block.texts.where((t) => t.isNotEmpty).join(' / ');
    buffer.writeln(text);
  }
}

void _writeEnhanced(
  StringBuffer buffer,
  List<_LineBlock> lines,
  int msDiv,
  int msPad,
  bool addEnd,
) {
  for (final block in lines) {
    buffer.write(_lrcTimestamp(block.start, msDiv, msPad));
    for (var w = 0; w < block.origWords.length; w++) {
      final word = block.origWords[w];
      buffer.write(word.text);
      if (w < block.origWords.length - 1) {
        buffer.write(_inlineTimestamp(word.end, msDiv, msPad));
      }
    }
    if (addEnd && block.end > block.start) {
      buffer.writeln(_inlineTimestamp(block.end, msDiv, msPad));
    } else {
      buffer.writeln();
    }
  }
}

void _writeVerbatim(
  StringBuffer buffer,
  List<_LineBlock> lines,
  int msDiv,
  int msPad,
  bool addEnd,
) {
  for (final block in lines) {
    for (final word in block.origWords) {
      buffer.write(_lrcTimestamp(word.start, msDiv, msPad));
      buffer.write(word.text);
      if (addEnd) {
        buffer.writeln(_inlineTimestamp(word.end, msDiv, msPad));
      } else {
        buffer.writeln();
      }
    }
  }
}

String _formatTimestamp(int ms, int msDiv, int msPad) {
  final totalSec = ms ~/ 1000;
  final min = totalSec ~/ 60;
  final sec = totalSec % 60;
  final frac = (ms % 1000) ~/ msDiv;
  return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}.${frac.toString().padLeft(msPad, '0')}';
}

String _lrcTimestamp(int ms, int msDiv, int msPad) =>
    '[${_formatTimestamp(ms, msDiv, msPad)}]';

String _inlineTimestamp(int ms, int msDiv, int msPad) =>
    '<${_formatTimestamp(ms, msDiv, msPad)}>';

class _LineBlock {
  const _LineBlock({
    required this.start,
    required this.end,
    required this.origWords,
    required this.texts,
  });
  final int start;
  final int end;
  final List<FSLyricsWord> origWords;
  final List<String> texts;
}
