// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Identifies which upstream provider a piece of data came from.

import 'search_type.dart';

/// Which upstream produced the data.
///
/// `Source.values` is sorted by [id] so it can be used as a stable iteration
/// order. New sources should be added with their own unique integer in the
/// appropriate historical slot to remain compatible with serialized data.
enum Source {
  /// Aggregate / "all platforms" pseudo-source used by `LyricFinder`.
  multi(0, '聚合'),

  /// QQ Music.
  qm(1, 'QQ音乐'),

  /// Kugou Music.
  kg(2, '酷狗音乐'),

  /// NetEase Cloud Music.
  ne(3, '网易云音乐'),

  /// LRCLIB.
  lrclib(4, 'Lrclib'),

  /// Local files (audio tags or CUE sheets).
  local(100, '本地');

  const Source(this.id, this.label);

  /// Stable integer identifier — preserved across serialization.
  final int id;

  /// Short display label (Chinese by convention, see upstream LDDC).
  final String label;

  /// Search types supported by this [Source].
  Set<SearchType> get supportedSearchTypes {
    switch (this) {
      case Source.multi:
      case Source.qm:
      case Source.kg:
      case Source.ne:
        return const {SearchType.song, SearchType.album, SearchType.songList};
      case Source.lrclib:
        return const {SearchType.song};
      case Source.local:
        return const {};
    }
  }

  /// Whether the [Source] can answer a [SearchType] query.
  bool supports(SearchType type) => supportedSearchTypes.contains(type);

  /// Resolve a [Source] by its integer id, returning `null` if unknown.
  static Source? fromId(int id) {
    for (final source in Source.values) {
      if (source.id == id) return source;
    }
    return null;
  }
}
