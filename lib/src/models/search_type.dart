// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Kinds of searches a provider can answer.

/// What kind of search a provider is being asked to perform.
enum SearchType {
  /// Single track search.
  song,

  /// Album search.
  album,

  /// Curated playlist search.
  songList,

  /// Artist search (reserved for future use).
  artist,

  /// Lyrics search — searches lyrics text directly (LRCLIB / QQ).
  lyrics,
}
