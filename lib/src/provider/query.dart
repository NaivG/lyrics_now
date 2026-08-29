// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Value objects describing what is being requested from a provider.
//
// `Query` instances are cheap, comparable value objects that can be reused by
// caches, schedulers, or the high-level `LyricFinder` facade.

import '../models/search_type.dart';
import '../models/source.dart';

/// A request to a [LyricsProvider.search].
class SearchQuery {
  const SearchQuery({
    required this.keyword,
    required this.searchType,
    this.page = 1,
    this.pageSize,
    this.albumName,
    this.durationMs,
    this.artistName,
    this.trackName,
  });

  /// Free-text query. Providers may combine this with the more specific
  /// [trackName]/[artistName]/[albumName] fields when these are present.
  final String keyword;

  /// What kind of entity to search for.
  final SearchType searchType;

  /// 1-based page index. Defaults to `1`.
  final int page;

  /// Optional hard cap on the number of returned entries. Providers that
  /// never paginate ignore this.
  final int? pageSize;

  /// Restrict the search to a specific album, where the provider supports it.
  final String? albumName;

  /// Expected track duration in milliseconds. Useful for boosting LRCLIB
  /// accuracy.
  final int? durationMs;

  /// Restrict to a single artist (LRCLIB).
  final String? artistName;

  /// Restrict to a specific track name (LRCLIB).
  final String? trackName;

  /// Stable equality so providers can cache by query.
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SearchQuery) return false;
    return keyword == other.keyword &&
        searchType == other.searchType &&
        page == other.page &&
        pageSize == other.pageSize &&
        albumName == other.albumName &&
        durationMs == other.durationMs &&
        artistName == other.artistName &&
        trackName == other.trackName;
  }

  @override
  int get hashCode => Object.hash(
    keyword,
    searchType,
    page,
    pageSize,
    albumName,
    durationMs,
    artistName,
    trackName,
  );

  @override
  String toString() =>
      'SearchQuery("$keyword"[$searchType, page=$page${albumName == null ? '' : ', album=$albumName'}])';
}

/// A request to fetch candidate lyric records for a specific track.
class LyricsListQuery {
  const LyricsListQuery({
    required this.song,
    this.durationMs,
    this.artist,
    this.album,
  });

  /// Track to look up.
  final LyricsListTarget song;

  /// Expected track duration in milliseconds (optional but highly recommended).
  final int? durationMs;

  /// Override the artist for API calls.
  final String? artist;

  /// Override the album for API calls.
  final String? album;
}

/// Addressable target used to fetch lyric candidates.
///
/// Exactly one of [id]/[mid]/[hash]/plain-text fields must be supplied by the
/// caller, depending on what the provider expects.
class LyricsListTarget {
  const LyricsListTarget({
    required this.source,
    this.id,
    this.mid,
    this.hash,
    this.title,
    this.artist,
    this.album,
    this.durationMs,
  });

  /// Which provider this target is meant for.
  final Source source;

  /// Provider-specific identifier.
  final String? id;

  /// QQ `mid`.
  final String? mid;

  /// Kugou `hash`.
  final String? hash;

  /// Title for fuzzy providers (LRCLIB).
  final String? title;

  /// Artist for fuzzy providers.
  final String? artist;

  /// Album for fuzzy providers.
  final String? album;

  /// Track length in ms.
  final int? durationMs;

  @override
  String toString() =>
      'LyricsListTarget($source: id=$id, mid=$mid, hash=$hash, title=$title)';
}
