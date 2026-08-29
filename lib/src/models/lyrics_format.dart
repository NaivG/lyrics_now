// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Wire / file formats for lyrics.

/// Output formats supported by the [LyricsConverter].
enum LyricsFormat {
  /// Verbatim LRC — every word has an independent timestamp.
  verbatimLrc('lrc'),

  /// Line-by-line LRC.
  lineByLineLrc('lrc'),

  /// Enhanced LRC with optional `[xx:xx.xx]text<xx:xx.xx>word` inline.
  enhancedLrc('lrc'),

  /// SubRip subtitle.
  srt('srt'),

  /// Advanced SubStation Alpha.
  ass('ass'),

  /// QQ Music's binary QRC.
  qrc('qrc'),

  /// Kugou Music's binary KRC.
  krc('krc'),

  /// NetEase Cloud Music's binary YRC.
  yrc('yrc'),

  /// Lossless JSON interchange (compatible with LDDC).
  json('json');

  const LyricsFormat(this.extension);

  /// File extension the format should be written with.
  final String extension;
}
