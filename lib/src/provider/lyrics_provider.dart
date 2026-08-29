// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Provider abstraction.
//
// Mirrors the upstream `BaseAPI` / `CloudAPI` / `LrclibAPI` / `LocalAPI` split
// from LDDC. Each provider sits behind this interface so the rest of the
// library (cache, scheduler, matchers, converters) can be agnostic of the
// underlying music platform.

import '../http_client.dart';
import '../models/api_result_list.dart';
import '../models/lyric_info.dart';
import '../models/lyrics.dart';
import '../models/search_type.dart';
import '../models/song_info.dart';
import '../models/song_list_info.dart';
import '../models/source.dart';
import 'query.dart';

/// Common contract for anything that can answer lyric queries.
///
/// Providers are typically cheap to construct and are expected to be reusable:
/// they share the [LyricsHttpClient] injected by the [LyricFinder] facade and
/// may cache inside it.
abstract interface class LyricsProvider {
  /// Short display name used in logs / diagnostics.
  String get name;

  /// Which provider this represents.
  Source get source;

  /// Search types supported by this provider.
  Set<SearchType> get supportedSearchTypes;

  /// Whether [search] can handle the requested type.
  bool supports(SearchType type) => supportedSearchTypes.contains(type);

  /// Search the provider's catalog for songs.
  ///
  /// Providers that don't index tracks at all may throw [UnsupportedError].
  Future<APIResultList<SongInfo>> search(SearchQuery query);

  /// Search the provider's catalog for albums and/or playlists.
  ///
  /// Returns `null` (the default) when the provider cannot search song lists;
  /// callers should then fall back to their own discovery UI.
  Future<APIResultList<SongListInfo>?> searchSongList(
    SearchQuery query,
  ) async => null;

  /// Fetch the contents of an album or songlist.
  Future<APIResultList<SongInfo>> getSongList(
    SongListInfo info, {
    int page = 1,
    int? pageSize,
  }) async {
    throw UnsupportedError('$name does not support getSongList');
  }

  /// Fetch candidate lyric records for the given track.
  Future<List<LyricInfo>> getLyricsList(LyricsListQuery query);

  /// Fetch and fully parse the lyric body for [info].
  Future<Lyrics> getLyrics(LyricInfo info);
}

/// Convenience base class for cloud-based providers that just need an HTTP
/// client + identity.
abstract class CloudLyricsProvider implements LyricsProvider {
  CloudLyricsProvider(this.http, {required this.source});

  @override
  final Source source;

  /// Shared HTTP client supplied by the [LyricFinder] facade.
  final LyricsHttpClient http;

  @override
  String get name => source.label;

  @override
  bool supports(SearchType type) => supportedSearchTypes.contains(type);
}
