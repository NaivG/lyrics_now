// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// LRCLIB provider: lyric catalogue of last resort.
//
// LRCLIB is a community-built open API (https://lrclib.net). It serves both
// plain-text lyrics and `syncedLyrics` strings formatted as standard LRC.
// Because it is server-rendered and unauthenticated, this provider is also
// the cheapest way to verify the platform abstraction.

import 'dart:convert';

import '../exceptions.dart';
import '../models/api_result_list.dart';
import '../models/artist.dart';
import '../models/language.dart';
import '../models/lyric_info.dart';
import '../models/lyrics.dart';
import '../models/lyrics_type.dart';
import '../models/search_info.dart';
import '../models/search_type.dart';
import '../models/song_info.dart';
import '../models/song_list_info.dart';
import '../models/source.dart';
import '../parser/lrc.dart';
import '../provider/lyrics_provider.dart';
import '../provider/query.dart';

/// User agent required by LRCLIB — public APIs reject missing / generic UA.
const String _userAgent = 'lyrics_now/0.1 (+https://github.com/lyrics_now)';

class LrclibProvider extends CloudLyricsProvider {
  LrclibProvider(super.http, {String baseUrl = 'https://lrclib.net/api'})
    : _baseUri = Uri.parse(baseUrl),
      super(source: Source.lrclib);

  final Uri _baseUri;

  @override
  String get name => 'LRCLIB';

  @override
  Set<SearchType> get supportedSearchTypes => {SearchType.song};

  @override
  Future<APIResultList<SongInfo>> search(SearchQuery query) async {
    if (!supports(query.searchType)) {
      throw UnsupportedError('LRCLIB does not support ${query.searchType}');
    }
    final response = await http.get(
      _baseUri.replace(
        path: '${_baseUri.path}/search',
        queryParameters: {'q': query.keyword},
      ),
      headers: const {'User-Agent': _userAgent, 'Accept': 'application/json'},
    );
    final List<dynamic> raw = jsonDecode(response.body) as List<dynamic>;
    final items = <SongInfo>[];
    for (final entry in raw) {
      if (entry is! Map) continue;
      items.add(_parseSongInfo(entry.cast<String, dynamic>()));
    }
    return APIResultList<SongInfo>(
      items: items,
      info: SearchInfo.single(
        source: source,
        keyword: query.keyword,
        searchType: query.searchType,
        page: query.page,
      ),
      sourceRanges: {
        if (items.isNotEmpty)
          source: (start: 0, end: items.length - 1, total: items.length),
      },
    );
  }

  @override
  Future<APIResultList<SongListInfo>?> searchSongList(
    SearchQuery query,
  ) async => null;

  @override
  Future<APIResultList<SongInfo>> getSongList(
    SongListInfo info, {
    int page = 1,
    int? pageSize,
  }) async {
    throw UnsupportedError('LRCLIB does not support song lists');
  }

  /// LRCLIB's "list" of candidate lyrics is a single record per search.
  @override
  Future<List<LyricInfo>> getLyricsList(LyricsListQuery query) async {
    if (query.song.id != null) {
      final response = await http.get(
        _baseUri.replace(path: '${_baseUri.path}/get/${query.song.id}'),
        headers: const {'User-Agent': _userAgent},
      );
      if (!response.isSuccess) return const [];
      final raw = jsonDecode(response.body);
      if (raw is Map<String, dynamic>) {
        return [_buildLyricInfo(raw)];
      }
      return const [];
    }

    final params = <String, String>{
      if (query.song.title != null) 'track_name': query.song.title!,
      if (query.song.artist != null) 'artist_name': query.song.artist!,
      if (query.song.album != null) 'album_name': query.song.album!,
      if (query.song.durationMs != null)
        'duration': (query.song.durationMs! / 1000).toString(),
    };
    if (params.isEmpty) {
      throw LyricsException('LRCLIB requires title/artist/album/duration');
    }
    final response = await http.get(
      _baseUri.replace(path: '${_baseUri.path}/get', queryParameters: params),
      headers: const {'User-Agent': _userAgent},
    );
    if (!response.isSuccess) return const [];
    final raw = jsonDecode(response.body);
    if (raw is Map<String, dynamic>) {
      if (raw.containsKey('error')) return const [];
      return [_buildLyricInfo(raw)];
    }
    return const [];
  }

  @override
  Future<Lyrics> getLyrics(LyricInfo info) async {
    final params = <String, String>{
      if (info.songInfo.title != null) 'track_name': info.songInfo.title!,
      if (info.songInfo.artistString.isNotEmpty)
        'artist_name': info.songInfo.artistString,
      if (info.songInfo.album != null) 'album_name': info.songInfo.album!,
      if (info.songInfo.duration != null)
        'duration': (info.songInfo.duration! / 1000).toString(),
      if (info.id != null) 'id': info.id!,
    };
    final response = await http.get(
      _baseUri.replace(path: '${_baseUri.path}/get', queryParameters: params),
      headers: const {'User-Agent': _userAgent},
    );
    if (!response.isSuccess) {
      throw LyricsNotFoundException(
        'LRCLIB /get failed: ${response.statusCode}',
      );
    }
    final raw = jsonDecode(response.body) as Map<String, dynamic>;
    if (raw.containsKey('error')) {
      throw LyricsNotFoundException(raw['error']?.toString() ?? 'no lyrics');
    }

    final lyrics = Lyrics(info);
    final trackName = (raw['trackName'] as String?)?.trim();
    final artistName = (raw['artistName'] as String?)?.trim();
    final albumName = (raw['albumName'] as String?)?.trim();
    if (trackName?.isNotEmpty == true) lyrics.tags['ti'] = trackName!;
    if (artistName?.isNotEmpty == true) lyrics.tags['ar'] = artistName!;
    if (albumName?.isNotEmpty == true) lyrics.tags['al'] = albumName!;

    final synced = (raw['syncedLyrics'] as String?)?.trim();
    final plain = (raw['plainLyrics'] as String?)?.trim();
    final instrumental = raw['instrumental'] == true;

    if (synced != null && synced.isNotEmpty) {
      try {
        final parsed = parseLrc(synced);
        final data = parsed.data;
        lyrics['orig'] = data;
        lyrics.types['orig'] = judgeLyricsType(data);
        lyrics.tags.addAll(parsed.tags);
      } on LyricsException {
        // Fall through to plain-text path if LRC parsing somehow fails.
      }
    } else if (plain != null && plain.isNotEmpty) {
      final data = parsePlaintext(plain);
      lyrics['orig'] = data;
      lyrics.types['orig'] = LyricsType.plainText;
    } else if (instrumental) {
      final inst = Lyrics.instrumental(info.songInfo);
      for (final entry in inst.tracks.entries) {
        lyrics[entry.key] = entry.value;
      }
      lyrics.types.addAll(inst.types);
      for (final entry in inst.tags.entries) {
        lyrics.tags.putIfAbsent(entry.key, () => entry.value);
      }
    } else {
      throw LyricsNotFoundException(
        'LRCLIB returned no lyrics for ${info.songInfo.title}',
      );
    }

    return lyrics;
  }

  SongInfo _parseSongInfo(Map<String, dynamic> raw) {
    final rawDuration = raw['duration'];
    final ms = rawDuration is num ? (rawDuration * 1000).toInt() : null;
    return SongInfo(
      source: source,
      title: raw['trackName']?.toString(),
      artist: Artist(raw['artistName']?.toString() ?? ''),
      album: raw['albumName']?.toString(),
      duration: ms,
      id: raw['id']?.toString(),
      language: raw['instrumental'] == true
          ? Language.instrumental
          : Language.other,
    );
  }

  LyricInfo _buildLyricInfo(Map<String, dynamic> raw) {
    final song = _parseSongInfo(raw);
    final rawDuration = raw['duration'];
    final ms = rawDuration is num ? (rawDuration * 1000).toInt() : null;
    return LyricInfo(
      source: source,
      songInfo: song,
      id: raw['id']?.toString(),
      duration: ms,
    );
  }
}
