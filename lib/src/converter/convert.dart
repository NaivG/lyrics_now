// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';

import '../models/lyrics.dart';
import '../models/lyrics_format.dart';
import 'lrc_converter.dart';
import 'srt_converter.dart';

String convert(
  FSLyrics lyrics,
  LyricsFormat format, {
  List<String> langsOrder = const ['orig', 'ts', 'roma'],
  int msDigits = 2,
  bool addEndTimestamp = false,
}) {
  switch (format) {
    case LyricsFormat.verbatimLrc:
    case LyricsFormat.lineByLineLrc:
    case LyricsFormat.enhancedLrc:
      return lrcConverter(
        lyrics,
        format,
        langsOrder: langsOrder,
        msDigits: msDigits,
        addEndTimestamp: addEndTimestamp,
      );
    case LyricsFormat.srt:
      return srtConverter(lyrics, langsOrder: langsOrder);
    case LyricsFormat.json:
      return const JsonEncoder.withIndent('  ').convert(lyrics.toJson());
    case LyricsFormat.qrc:
    case LyricsFormat.krc:
    case LyricsFormat.yrc:
    case LyricsFormat.ass:
      throw UnsupportedError('Conversion to $format is not implemented');
  }
}
