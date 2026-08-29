// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';

import 'cache.dart';
import 'http_client.dart';
import 'matcher/song_matcher.dart';
import 'models/api_result_list.dart';
import 'models/info_base.dart';
import 'models/lyric_info.dart';
import 'models/lyrics.dart';
import 'models/song_info.dart';
import 'models/song_list_info.dart';
import 'persistent_cache/store.dart';
import 'provider/lyrics_provider.dart';
import 'provider/query.dart';

class LyricFinder {
  LyricFinder({
    LyricsHttpClient? http,
    List<LyricsProvider>? providers,
    Duration? searchCacheTtl,
    CacheStore? persistentCache,
    Duration? persistentCacheTtl,
    SongMatcher? matcher,
  }) : http = http ?? PackageHttpClient(),
       _ownsHttp = http == null,
       _providers = List<LyricsProvider>.unmodifiable(providers ?? const []),
       _searchCache = searchCacheTtl == null
           ? null
           : TtlSearchCache<APIResultList<InfoBase>>(searchCacheTtl),
       _persistentCache = persistentCache,
       _persistentCacheTtl = persistentCacheTtl ?? const Duration(hours: 4),
       _matcher = matcher;

  final LyricsHttpClient http;

  /// True when this finder created [http] itself (vs. having it injected by
  /// the caller). Injected clients are owned by the caller and must not be
  /// closed by [close].
  final bool _ownsHttp;
  final List<LyricsProvider> _providers;
  final TtlSearchCache<APIResultList<InfoBase>>? _searchCache;
  final CacheStore? _persistentCache;
  final Duration _persistentCacheTtl;
  final SongMatcher? _matcher;

  List<LyricsProvider> get providers => _providers;

  LyricFinder withProvider(LyricsProvider provider) {
    return LyricFinder(
      http: http,
      providers: <LyricsProvider>[..._providers, provider],
      searchCacheTtl: _searchCache?.ttl,
      persistentCache: _persistentCache,
      persistentCacheTtl: _persistentCacheTtl,
      matcher: _matcher,
    );
  }

  Future<APIResultList<SongInfo>> searchSongs(SearchQuery query) {
    return _runSearch<SongInfo>(query);
  }

  Future<APIResultList<SongListInfo>> searchSongLists(SearchQuery query) async {
    final tasks = <Future<APIResultList<SongListInfo>>>[];
    for (final provider in _providers) {
      final Future<APIResultList<SongListInfo>?> Function(SearchQuery)
      searchList = provider.searchSongList;
      if (!provider.supports(query.searchType)) continue;
      tasks.add(
        _safe(
          () async =>
              (await searchList(query)) ??
              APIResultList<SongListInfo>(items: const []),
          APIResultList<SongListInfo>(items: const []),
        ),
      );
    }
    final settled = await Future.wait(tasks);
    APIResultList<SongListInfo>? combined;
    for (final list in settled) {
      combined = combined == null ? list : combined.merged(list);
    }
    return combined ?? APIResultList<SongListInfo>(items: const []);
  }

  Future<APIResultList<T>> _runSearch<T extends InfoBase>(
    SearchQuery query,
  ) async {
    final cache = _searchCache;
    if (cache != null) {
      final cachedList = cache.lookup(query);
      if (cachedList != null) {
        return APIResultList<T>(
          items: cachedList.itemsList.cast<T>(),
          info: cachedList.info,
          sourceRanges: cachedList.sourceRanges,
          cached: cachedList.cached,
        );
      }
    }

    if (_persistentCache != null && T == SongInfo) {
      final cached = await _readPersistedSearch(query);
      if (cached != null) {
        if (cache != null) cache.store(query, _upcast(cached));
        return cached as APIResultList<T>;
      }
    }

    final tasks = <Future<APIResultList<InfoBase>>>[];
    for (final provider in _providers) {
      if (!provider.supports(query.searchType)) continue;
      tasks.add(
        _safe<APIResultList<InfoBase>>(
          () => _upcastSearch(provider.search(query)),
          APIResultList<InfoBase>(items: const []),
        ),
      );
    }
    final settled = await Future.wait(tasks);
    APIResultList<T>? combined;
    for (final list in settled) {
      final narrowed = APIResultList<T>(
        items: list.itemsList.cast<T>(),
        info: list.info,
        sourceRanges: list.sourceRanges,
        cached: list.cached,
      );
      combined = combined == null ? narrowed : combined.merged(narrowed);
    }
    final result = combined ?? APIResultList<T>(items: const []);

    if (cache != null) cache.store(query, _upcast<T>(result));
    if (_persistentCache != null && T == SongInfo) {
      await _writePersistedSearch(query, result as APIResultList<SongInfo>);
    }
    return result;
  }

  Future<APIResultList<SongInfo>?> _readPersistedSearch(
    SearchQuery query,
  ) async {
    final store = _persistentCache!;
    final key = _searchCacheKey(query);
    final raw = await store.read(key);
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw) as Map<String, Object?>;
      final items = (decoded['items'] as List)
          .cast<Map<String, Object?>>()
          .map(SongInfo.fromJson)
          .toList(growable: false);
      return APIResultList<SongInfo>(items: items, cached: true);
    } on Object {
      return null;
    }
  }

  Future<void> _writePersistedSearch(
    SearchQuery query,
    APIResultList<SongInfo> result,
  ) async {
    final store = _persistentCache!;
    final key = _searchCacheKey(query);
    final data = json.encode({
      'items': result.itemsList.map((s) => s.toJson()).toList(growable: false),
    });
    await store.write(key, data, _persistentCacheTtl);
  }

  String _searchCacheKey(SearchQuery query) {
    return 'search:${query.searchType.name}:${query.keyword.toLowerCase()}';
  }

  APIResultList<InfoBase> _upcast<T extends InfoBase>(APIResultList<T> list) {
    return APIResultList<InfoBase>(
      items: list.itemsList,
      info: list.info,
      sourceRanges: list.sourceRanges,
      cached: list.cached,
    );
  }

  Future<APIResultList<InfoBase>> _upcastSearch(
    Future<APIResultList<SongInfo>> future,
  ) async {
    final list = await future;
    return APIResultList<InfoBase>(
      items: list.itemsList,
      info: list.info,
      sourceRanges: list.sourceRanges,
      cached: list.cached,
    );
  }

  Future<List<LyricInfo>> listLyrics(
    LyricsProvider provider,
    LyricsListQuery query,
  ) async {
    try {
      return await provider.getLyricsList(query);
    } on Object {
      return const <LyricInfo>[];
    }
  }

  Future<Lyrics?> getLyrics(LyricsProvider provider, LyricInfo info) async {
    try {
      return await provider.getLyrics(info);
    } on Object {
      return null;
    }
  }

  Future<Lyrics?> fetchLyrics({
    required SongInfo song,
    int durationMs = 0,
  }) async {
    for (final provider in _providers) {
      try {
        final isSourceMatch = provider.source == song.source;
        List<LyricInfo> candidates;
        try {
          candidates = await provider.getLyricsList(
            LyricsListQuery(
              song: LyricsListTarget(
                source: provider.source,
                id: isSourceMatch ? song.id : null,
                mid: isSourceMatch ? song.mid : null,
                hash: isSourceMatch ? song.hash : null,
                title: song.title,
                artist: song.artistString,
                album: song.album,
                durationMs: durationMs == 0 ? song.duration : durationMs,
              ),
            ),
          );
        } on Object {
          // Providers like QmProvider / NeProvider don't expose a
          // candidate-list step; they only have a direct getLyrics() keyed
          // on the song's native id/mid. Fall through to the synthetic
          // candidate below so we can still reach them.
          candidates = const <LyricInfo>[];
        }
        if (candidates.isEmpty && isSourceMatch) {
          candidates = <LyricInfo>[
            LyricInfo(source: provider.source, songInfo: song),
          ];
        }
        if (candidates.isEmpty) continue;

        final target = _matcher != null
            ? _pickBestCandidate(song, candidates, durationMs)
            : candidates.first;

        try {
          return await provider.getLyrics(target);
        } on Object {
          continue;
        }
      } on Object {
        continue;
      }
    }
    return null;
  }

  LyricInfo _pickBestCandidate(
    SongInfo song,
    List<LyricInfo> candidates,
    int durationMs,
  ) {
    final songCandidates = candidates
        .map(
          (c) => SongInfo(
            source: c.source,
            title: c.songInfo.title,
            artist: c.songInfo.artist,
            album: c.songInfo.album,
            duration: c.songInfo.duration,
          ),
        )
        .toList(growable: false);

    final scored = _matcher!.findMatches(song, songCandidates);
    if (scored.isEmpty) return candidates.first;

    final bestIdx = candidates.indexWhere(
      (c) => _songMatch(c.songInfo, scored.first.song),
    );
    return bestIdx >= 0 ? candidates[bestIdx] : candidates.first;
  }

  bool _songMatch(SongInfo a, SongInfo b) =>
      a.title == b.title &&
      a.artistString == b.artistString &&
      a.album == b.album;

  void close() {
    if (_ownsHttp) http.close();
  }

  static Future<T> _safe<T>(Future<T> Function() fn, T fallback) async {
    try {
      return await fn();
    } on Object {
      return fallback;
    }
  }
}
