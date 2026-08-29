// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Tracks a lyrics track over time and decides which timestamps are reliable.

/// Granularity of the timestamp metadata available for a lyrics track.
enum LyricsType {
  /// Plain text only.
  plainText,

  /// Verbatim (word-by-word) timestamps.
  verbatim,

  /// Line-by-line timestamps.
  lineByLine,
}
