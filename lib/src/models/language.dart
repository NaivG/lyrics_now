// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Heuristic language tags used to colour and group lyrics.

/// Coarse language tags inferred from the lyrics content itself.
enum Language {
  /// No lyrics — purely instrumental track.
  instrumental,

  /// Language could not be determined.
  other,

  /// Chinese.
  chinese,

  /// English (Latin script).
  english,

  /// Japanese.
  japanese,

  /// Korean.
  korean,
}
