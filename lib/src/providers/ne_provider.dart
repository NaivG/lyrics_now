// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// NetEase Cloud Music provider (https://music.163.com).
//
// `NeProvider` mirrors the upstream Python LDDC's
// `LDDC\core\api\lyrics\ne.py`. Every API call is wrapped through the NetEase
// EAPI envelope (AES-128-ECB request signing + response decryption) handled
// by `crypto/eapi.dart`.
//
// Anonymous auto-login (`/eapi/register/anonimous`) runs lazily on the first
// real call. The negotiated `MUSIC_A`, `NMTID`, `__csrf` and synthesised
// `clientSign`/`osver`/`mode` cookies are persisted via [NeCookieStore]
// (default in-memory TTL = 10 days, matching upstream).

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../cache.dart';
import '../crypto/eapi.dart';
import '../exceptions.dart';
import '../http_client.dart';
import '../models/api_result_list.dart';
import '../models/artist.dart';
import '../models/lyric_info.dart';
import '../models/lyrics.dart';
import '../models/lyrics_models.dart';
import '../models/lyrics_type.dart';
import '../models/search_info.dart';
import '../models/search_type.dart';
import '../models/song_info.dart';
import '../models/song_list_info.dart';
import '../models/source.dart';
import '../parser/lrc.dart';
import '../parser/yrc.dart';
import '../provider/lyrics_provider.dart';
import '../provider/query.dart';
import '../res/ne_device_ids.dart';

class NeProvider extends CloudLyricsProvider {
  NeProvider(super.http, {NeCookieStore? cookieStore})
    : _cookieStore = cookieStore ?? InMemoryNeCookieStore(),
      super(source: Source.ne);

  /// Persistent backing for the anonymous-login session.
  final NeCookieStore _cookieStore;

  /// Lazy init guard — `_inited` flips after the first successful login.
  bool _inited = false;
  bool _inFlight = false;

  /// Cached device fingerprint generated on first login.
  late _NeDeviceProfile _profile;

  @override
  String get name => 'NetEase';

  @override
  Set<SearchType> get supportedSearchTypes => {
    SearchType.song,
    SearchType.album,
    SearchType.songList,
  };

  /// Closest ancestor of "the user is currently anonymous".
  static const String _anonimousPath = '/eapi/register/anonimous';

  /// Song search (Lite resource list).
  static const String _songSearchPath = '/eapi/search/song/list/page';

  /// Album search.
  static const String _albumSearchPath = '/eapi/v1/search/album/get';

  /// Playlist search.
  static const String _playlistSearchPath = '/eapi/v1/search/playlist/get';

  /// Album track listing.
  static const String _albumListPath = '/eapi/album/v3/detail';

  /// Playlist track IDs.
  static const String _playlistListPath = '/eapi/v1/playlist/detail';

  /// Full song metadata (after `c` param).
  static const String _songDetailPath = '/eapi/v3/song/detail';

  /// Lyric fetch.
  static const String _lyricPath = '/eapi/song/lyric/v1';

  @override
  Future<APIResultList<SongInfo>> search(SearchQuery query) async {
    await _ensureLogin();
    if (query.searchType == SearchType.song) {
      return _searchSongs(query);
    }
    if (query.searchType == SearchType.album) {
      final list = await _searchAlbums(query);
      return APIResultList<SongInfo>(
        items: const [],
        info: list.info,
        sourceRanges: const {},
      );
    }
    if (query.searchType == SearchType.songList) {
      final list = await _searchPlaylists(query);
      return APIResultList<SongInfo>(
        items: const [],
        info: list.info,
        sourceRanges: const {},
      );
    }
    return APIResultList<SongInfo>(items: const []);
  }

  @override
  Future<APIResultList<SongListInfo>?> searchSongList(SearchQuery query) async {
    if (query.searchType == SearchType.album) return _searchAlbums(query);
    if (query.searchType == SearchType.songList) return _searchPlaylists(query);
    return null;
  }

  Future<APIResultList<SongInfo>> _searchSongs(SearchQuery query) async {
    final pageSize = 20;
    final params = <String, Object?>{
      'limit': pageSize.toString(),
      'offset': ((query.page - 1) * pageSize).toString(),
      'keyword': query.keyword,
      'scene': 'NORMAL',
      'needCorrect': 'true',
    };
    final data = await _request(_songSearchPath, params);
    final songData = (data['data'] is Map)
        ? (data['data'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final resources = (songData['resources'] is List)
        ? (songData['resources'] as List)
        : const <dynamic>[];
    final items = <SongInfo>[
      for (final entry in resources.whereType<Map>())
        if ((entry['baseInfo'] as Map?) != null)
          _parseSongEntry(
            ((entry['baseInfo'] as Map)
                        .cast<String, dynamic>()['simpleSongData']
                    as Map)
                .cast<String, dynamic>(),
          ),
    ];
    final total = resources.length == pageSize
        ? ((songData['totalCount'] as num?)?.toInt() ?? items.length)
        : ((query.page - 1) * pageSize) + items.length;
    return APIResultList<SongInfo>(
      items: items,
      info: SearchInfo.single(
        source: source,
        keyword: query.keyword,
        searchType: query.searchType,
        page: query.page,
      ),
      sourceRanges: items.isEmpty ? const {} : {source: _range(items, total)},
    );
  }

  Future<APIResultList<SongListInfo>> _searchAlbums(SearchQuery query) async {
    await _ensureLogin();
    final pageSize = 20;
    final params = <String, Object?>{
      'limit': pageSize.toString(),
      'offset': ((query.page - 1) * pageSize).toString(),
      's': query.keyword,
      'queryCorrect': 'true',
    };
    final data = await _request(_albumSearchPath, params);
    final result =
        (data['result'] as Map?)?.cast<String, dynamic>() ?? const {};
    final raw = (result['albums'] is List)
        ? (result['albums'] as List)
        : const <dynamic>[];
    final items = <SongListInfo>[
      for (final entry in raw.whereType<Map>())
        _parseAlbumEntry(entry.cast<String, dynamic>()),
    ];
    final total = raw.length == pageSize
        ? ((result['albumCount'] as num?)?.toInt() ?? items.length)
        : items.length;
    return APIResultList<SongListInfo>(
      items: items,
      info: SearchInfo.single(
        source: source,
        keyword: query.keyword,
        searchType: query.searchType,
        page: query.page,
      ),
      sourceRanges: items.isEmpty ? const {} : {source: _range(items, total)},
    );
  }

  Future<APIResultList<SongListInfo>> _searchPlaylists(
    SearchQuery query,
  ) async {
    await _ensureLogin();
    final pageSize = 20;
    final params = <String, Object?>{
      'limit': pageSize.toString(),
      'offset': ((query.page - 1) * pageSize).toString(),
      's': query.keyword,
      'queryCorrect': 'true',
    };
    final data = await _request(_playlistSearchPath, params);
    final result =
        (data['result'] as Map?)?.cast<String, dynamic>() ?? const {};
    final raw = (result['playlists'] is List)
        ? (result['playlists'] as List)
        : const <dynamic>[];
    final items = <SongListInfo>[
      for (final entry in raw.whereType<Map>())
        _parsePlaylistEntry(entry.cast<String, dynamic>()),
    ];
    final total = raw.length == pageSize
        ? ((result['playlistCount'] as num?)?.toInt() ?? items.length)
        : items.length;
    return APIResultList<SongListInfo>(
      items: items,
      info: SearchInfo.single(
        source: source,
        keyword: query.keyword,
        searchType: query.searchType,
        page: query.page,
      ),
      sourceRanges: items.isEmpty ? const {} : {source: _range(items, total)},
    );
  }

  @override
  Future<APIResultList<SongInfo>> getSongList(
    SongListInfo info, {
    int page = 1,
    int? pageSize,
  }) async {
    await _ensureLogin();
    final id = int.tryParse(info.id) ?? 0;
    if (info.type == SongListType.album) {
      return _getAlbumSongList(id, info);
    }
    if (info.type == SongListType.songList) {
      return _getPlaylistSongList(id, info);
    }
    throw UnsupportedError('$name does not support ${info.type}');
  }

  Future<APIResultList<SongInfo>> _getAlbumSongList(
    int albumId,
    SongListInfo info,
  ) async {
    final cacheKey = getCacheKey('e_r=true&id=$albumId');
    final params = <String, Object?>{'id': albumId, 'cache_key': cacheKey};
    final data = await _request(
      _albumListPath,
      params,
      queryCacheKey: cacheKey,
    );
    final list = (data['songs'] is List)
        ? (data['songs'] as List)
        : const <dynamic>[];
    final items = <SongInfo>[
      for (final entry in list.whereType<Map>())
        _parseSongEntry(entry.cast<String, dynamic>()),
    ];
    return APIResultList<SongInfo>(
      items: items,
      info: SearchInfo.many(
        sources: [source],
        keyword: '',
        searchType: SearchType.album,
        parent: info,
      ),
      sourceRanges: items.isEmpty
          ? const {}
          : {source: _range(items, items.length)},
    );
  }

  Future<APIResultList<SongInfo>> _getPlaylistSongList(
    int playlistId,
    SongListInfo info,
  ) async {
    final cacheKey = getCacheKey('e_r=true&id=$playlistId&n=0&s=0');
    final params = <String, Object?>{
      'id': playlistId,
      'n': '0',
      's': '0',
      'cache_key': cacheKey,
    };
    final data = await _request(
      _playlistListPath,
      params,
      queryCacheKey: cacheKey,
    );
    final playlist =
        (data['playlist'] as Map?)?.cast<String, dynamic>() ?? const {};
    final trackIds = (playlist['trackIds'] is List)
        ? (playlist['trackIds'] as List)
        : const <dynamic>[];
    final ids = <Map<String, Object?>>[
      for (final entry in trackIds.whereType<Map>())
        if ((entry['id'] as num?) != null)
          <String, Object?>{'id': (entry['id'] as num).toInt(), 'v': 0},
    ];
    if (ids.isEmpty) {
      return APIResultList<SongInfo>(
        items: const [],
        info: SearchInfo.many(
          sources: [source],
          keyword: '',
          searchType: SearchType.songList,
          parent: info,
        ),
        sourceRanges: const {},
      );
    }
    final detailParams = <String, Object?>{
      'c': jsonEncode(ids),
      'trialMode': '-1',
    };
    final detailData = await _request(_songDetailPath, detailParams);
    final list = (detailData['songs'] is List)
        ? (detailData['songs'] as List)
        : const <dynamic>[];
    final items = <SongInfo>[
      for (final entry in list.whereType<Map>())
        _parseSongEntry(entry.cast<String, dynamic>()),
    ];
    return APIResultList<SongInfo>(
      items: items,
      info: SearchInfo.many(
        sources: [source],
        keyword: '',
        searchType: SearchType.songList,
        parent: info,
      ),
      sourceRanges: items.isEmpty
          ? const {}
          : {source: _range(items, items.length)},
    );
  }

  @override
  Future<List<LyricInfo>> getLyricsList(LyricsListQuery query) async {
    throw UnsupportedError('$name does not support getLyricsList');
  }

  @override
  Future<Lyrics> getLyrics(LyricInfo info) async {
    await _ensureLogin();
    final id = int.tryParse(info.songInfo.id ?? '');
    if (id == null) {
      throw const LyricsException('NE lyrics require numeric song id');
    }
    final params = <String, Object?>{
      'id': id,
      'lv': '-1',
      'tv': '-1',
      'rv': '-1',
      'yv': '-1',
    };
    final data = await _request(_lyricPath, params);
    final lyrics = Lyrics(info);
    final song = info.songInfo;
    final tags = <String, String>{};
    if (song.artist != null && song.artist!.names.isNotEmpty) {
      tags['ar'] = song.artist!.names.join('/');
    }
    if (song.album != null && song.album!.isNotEmpty) {
      tags['al'] = song.album!;
    }
    if (song.title != null) tags['ti'] = song.title!;
    final byNick = _userNick(data['lyricUser']);
    if (byNick != null) tags['by'] = byNick;
    final transNick = _userNick(data['transUser']);
    if (transNick != null) {
      if (tags['by'] != null && tags['by'] != transNick) {
        tags['by'] = '${tags['by']} & $transNick';
      } else if (tags['by'] == null) {
        tags['by'] = transNick;
      }
    }
    lyrics.tags.addAll(tags);

    final yrcBlob = _lyricString(data['yrc']);
    final lrcBlob = _lyricString(data['lrc']);
    final tlyricBlob = _lyricString(data['tlyric']);
    final romalrcBlob = _lyricString(data['romalrc']);

    final entries = <(String, String)>[];
    if (yrcBlob.isNotEmpty) {
      entries.add(('orig', yrcBlob));
      entries.add(('orig_lrc', lrcBlob));
    } else {
      entries.add(('orig', lrcBlob));
    }
    entries.add(('ts', tlyricBlob));
    entries.add(('roma', romalrcBlob));

    for (final entry in entries) {
      final blob = entry.$2;
      if (blob.isEmpty) continue;
      LyricsData parsed;
      if (entry.$1 == 'orig' && blob == yrcBlob && yrcBlob.isNotEmpty) {
        parsed = yrc2Data(blob);
      } else if (blob.contains('[') && blob.contains(']')) {
        parsed = parseLrc(blob).data;
      } else {
        parsed = parsePlaintext(blob);
      }
      lyrics[entry.$1] = parsed;
      lyrics.types[entry.$1] = _judge(parsed);
    }
    return lyrics;
  }

  // -----------------------------------------------------------------
  // EAPI plumbing
  // -----------------------------------------------------------------

  Future<Map<String, dynamic>> _request(
    String path,
    Map<String, Object?> params, {
    String? queryCacheKey,
  }) async {
    await _ensureLogin();
    final cookies = _currentCookies();
    final headerJson = _headerJson();
    final signedParams = <String, Object?>{
      ...params,
      'e_r': true,
      'header': headerJson,
    };
    final body = eapiParamsEncrypt(
      path.replaceFirst('eapi', 'api'),
      signedParams,
    );
    final query = <String, String>{};
    if (queryCacheKey != null) {
      query['cache_key'] = queryCacheKey;
    }
    final response = await http.send(
      LyricsHttpRequest(
        method: 'POST',
        uri: Uri.parse(
          'https://interface.music.163.com$path',
        ).replace(queryParameters: query.isEmpty ? null : query),
        body: body,
        encoding: utf8,
        headers: <String, String>{
          'accept': '*/*',
          'content-type': 'application/x-www-form-urlencoded',
          'mconfig-info':
              '{"IuRPVVmc3WWul9fT":{"version":733184,"appver":"3.1.3.203419"}}',
          'origin': 'orpheus://orpheus',
          'user-agent': _userAgent,
          'sec-ch-ua': '"Chromium";v="91"',
          'sec-ch-ua-mobile': '?0',
          'sec-fetch-site': 'cross-site',
          'sec-fetch-mode': 'cors',
          'sec-fetch-dest': 'empty',
          'accept-encoding': 'gzip',
          'accept-language': 'en-US,en;q=0.9',
          'cookie': _cookieHeader(cookies),
        },
        http2: true,
      ),
    );
    if (!response.isSuccess) {
      throw LyricsHttpStatusException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    String decrypted;
    try {
      decrypted = eapiResponseDecrypt(response.bodyBytes);
    } on Object catch (e) {
      throw LyricsDecryptError(
        'NE EAPI response decrypt failed',
        format: 'eapi',
        cause: e,
      );
    }
    final decoded = jsonDecode(decrypted);
    if (decoded is! Map) {
      throw LyricsException('NE EAPI payload not a JSON object');
    }
    final code = (decoded['code'] as num?)?.toInt() ?? -1;
    if (code != 200 && code != 0) {
      throw LyricsException(
        'NE API error code=$code msg=${decoded['message'] ?? decoded['msg']}',
      );
    }
    return decoded.cast<String, dynamic>();
  }

  Future<void> _ensureLogin() async {
    if (_inited) return;
    if (_inFlight) {
      // Another call is already authenticating. Wait by re-checking _inited.
      // A short polling loop avoids a deadlock with single-threaded async.
      while (_inFlight && !_inited) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      if (_inited) return;
    }
    _inFlight = true;
    try {
      final existing = await _cookieStore.read();
      if (existing != null && !existing.isExpired) {
        _applyRecord(existing);
        _inited = true;
        return;
      }
      _profile = _NeDeviceProfile.generate();
      await _login();
      _inited = true;
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _login() async {
    final clientSign = _profile.clientSign;
    final cookies = <String, String>{
      'WEVNSM': '1.0.0',
      'os': 'pc',
      'deviceId': _profile.deviceId,
      'osver': _profile.osver,
      'clientSign': clientSign,
      'channel': 'netease',
      'mode': _profile.mode,
      'appver': '3.1.3.203419',
      'WNMCID': _profile.wnmcid,
    };
    final headerJson = _composeHeaderJson(cookies);
    final params = <String, Object?>{
      'username': getAnonymousUsername(_profile.deviceId),
      'e_r': true,
      'header': headerJson,
    };
    final body = eapiParamsEncrypt(
      _anonimousPath.replaceFirst('eapi', 'api'),
      params,
    );
    final response = await http.send(
      LyricsHttpRequest(
        method: 'POST',
        uri: Uri.parse('https://interface.music.163.com$_anonimousPath'),
        body: body,
        encoding: utf8,
        headers: <String, String>{
          'accept': '*/*',
          'content-type': 'application/x-www-form-urlencoded',
          'mconfig-info':
              '{"IuRPVVmc3WWul9fT":{"version":733184,"appver":"3.1.3.203419"}}',
          'origin': 'orpheus://orpheus',
          'user-agent': _userAgent,
          'sec-ch-ua': '"Chromium";v="91"',
          'sec-ch-ua-mobile': '?0',
          'sec-fetch-site': 'cross-site',
          'sec-fetch-mode': 'cors',
          'sec-fetch-dest': 'empty',
          'accept-encoding': 'gzip',
          'accept-language': 'en-US,en;q=0.9',
          'cookie': _cookieHeader(cookies),
        },
        http2: true,
      ),
    );
    if (!response.isSuccess) {
      throw LyricsHttpStatusException(
        statusCode: response.statusCode,
        body: response.body,
      );
    }
    String decrypted;
    try {
      decrypted = eapiResponseDecrypt(response.bodyBytes);
    } on Object catch (e) {
      throw LyricsDecryptError(
        'NE login response decrypt failed',
        format: 'eapi',
        cause: e,
      );
    }
    final decoded = jsonDecode(decrypted);
    if (decoded is! Map) {
      throw const LyricsException('NE login payload not a JSON object');
    }
    final code = (decoded['code'] as num?)?.toInt() ?? -1;
    if (code != 200 && code != 0) {
      throw LyricsException('NE login error code=$code');
    }
    final responseCookies = _absorbSetCookie(
      response.headers['set-cookie'] ?? '',
      base: cookies,
    );
    final userId =
        (decoded['data'] is Map
                ? ((decoded['data'] as Map)['userId'] as num?)
                : (decoded['userId'] as num?))
            ?.toInt() ??
        0;
    final expire = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 864000;
    await _cookieStore.write(
      NeCookieRecord(
        userId: userId,
        cookies: responseCookies,
        expireAt: expire,
      ),
    );
    _applyRecord(
      NeCookieRecord(
        userId: userId,
        cookies: responseCookies,
        expireAt: expire,
      ),
    );
  }

  Map<String, String>? _cachedCookies;

  void _applyRecord(NeCookieRecord record) {
    _cachedCookies = Map<String, String>.from(record.cookies);
  }

  Map<String, String> _currentCookies() =>
      Map<String, String>.from(_cachedCookies ?? const <String, String>{});

  String _headerJson() => _composeHeaderJson(_currentCookies());

  String _composeHeaderJson(Map<String, String> cookies) {
    return jsonEncode(<String, Object?>{
      'clientSign': cookies['clientSign'] ?? '',
      'os': cookies['os'] ?? 'pc',
      'appver': cookies['appver'] ?? '3.1.3.203419',
      'deviceId': cookies['deviceId'] ?? '',
      'requestId': 0,
      'osver': cookies['osver'] ?? '',
    }, toEncodable: _fallbackJson);
  }

  String _cookieHeader(Map<String, String> cookies) => cookies.entries
      .where((entry) => entry.value.isNotEmpty)
      .map((entry) => '${entry.key}=${entry.value}')
      .join('; ');

  Map<String, String> _absorbSetCookie(
    String raw, {
    required Map<String, String> base,
  }) {
    final result = Map<String, String>.from(base);
    if (raw.isEmpty) return result;
    for (final piece in _splitSetCookie(raw)) {
      final pair = piece.split(';').first.trim();
      final equals = pair.indexOf('=');
      if (equals <= 0) continue;
      final name = pair.substring(0, equals).trim();
      final value = pair.substring(equals + 1).trim();
      if (name.isNotEmpty && value.isNotEmpty) result[name] = value;
    }
    return result;
  }

  List<String> _splitSetCookie(String header) {
    final out = <String>[];
    final buf = StringBuffer();
    var depth = 0;
    for (final char in header.split('')) {
      if (char == ',') {
        if (depth == 0) {
          out.add(buf.toString());
          buf.clear();
        } else {
          buf.write(char);
        }
        continue;
      }
      if (char == ';') {
        depth++;
        buf.write(char);
        continue;
      }
      buf.write(char);
    }
    final last = buf.toString().trim();
    if (last.isNotEmpty) out.add(last);
    return out;
  }

  // -----------------------------------------------------------------
  // Field parsers
  // -----------------------------------------------------------------

  SongInfo _parseSongEntry(Map<String, dynamic> entry) {
    final ar = entry['ar'];
    final artistsRaw = ar is List ? ar : const <dynamic>[];
    final artists = artistsRaw
        .whereType<Map>()
        .map((m) => (m['name'] ?? '').toString())
        .where((s) => s.isNotEmpty)
        .toList();
    final al = entry['al'];
    final albumName = al is Map ? (al['name']?.toString() ?? '') : '';
    final aliases = entry['alia'];
    final subtitle = aliases is List && aliases.isNotEmpty
        ? aliases.first.toString()
        : '';
    final id = (entry['id'] as num?)?.toInt();
    final dt = (entry['dt'] as num?)?.toInt() ?? 0;
    return SongInfo(
      source: source,
      id: id?.toString(),
      title: entry['name']?.toString(),
      subtitle: subtitle,
      artist: artists.isEmpty ? null : Artist(artists),
      album: albumName.isEmpty ? null : albumName,
      duration: dt,
    );
  }

  SongListInfo _parseAlbumEntry(Map<String, dynamic> entry) {
    final id = (entry['id'] as num?)?.toInt();
    final publishMs = (entry['publishTime'] as num?)?.toInt();
    final size = (entry['size'] as num?)?.toInt();
    final artistList = entry['artists'];
    final author = artistList is List && artistList.isNotEmpty
        ? ((artistList.first as Map?)
                  ?.cast<String, dynamic>()['name']
                  ?.toString() ??
              '')
        : '';
    return SongListInfo(
      source: source,
      type: SongListType.album,
      id: id?.toString() ?? '',
      title: entry['name']?.toString() ?? '',
      imgUrl: entry['picUrl']?.toString() ?? '',
      author: author,
      publishTime: publishMs == null ? null : publishMs ~/ 1000,
      songCount: size,
    );
  }

  SongListInfo _parsePlaylistEntry(Map<String, dynamic> entry) {
    final id = (entry['id'] as num?)?.toInt();
    final trackCount = (entry['trackCount'] as num?)?.toInt();
    final creator = entry['creator'];
    final author = creator is Map
        ? (creator['nickname']?.toString() ?? '')
        : '';
    return SongListInfo(
      source: source,
      type: SongListType.songList,
      id: id?.toString() ?? '',
      title: entry['name']?.toString() ?? '',
      imgUrl: entry['coverImgUrl']?.toString() ?? '',
      author: author,
      songCount: trackCount,
    );
  }

  String _lyricString(dynamic entry) {
    if (entry is Map) {
      final lyric = entry['lyric'];
      if (lyric is String) return lyric;
    }
    return '';
  }

  String? _userNick(dynamic entry) {
    if (entry is Map) {
      final nick = entry['nickname'];
      if (nick is String && nick.isNotEmpty) return nick;
    }
    return null;
  }

  SourceRange _range<T>(List<T> items, int total) =>
      (start: 0, end: items.length - 1, total: total);

  LyricsType _judge(LyricsData data) {
    if (data.isEmpty) return LyricsType.plainText;
    for (final line in data) {
      if (line.words.length > 1) return LyricsType.verbatim;
      if (line.start != null) return LyricsType.lineByLine;
    }
    return LyricsType.plainText;
  }
}

// `SourceRange` is imported from `models/api_result_list.dart`.

const String _userAgent =
    'Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/3.1.3.203419';

const List<String> _modePool = <String>[
  'MS-iCraft B760M WIFI',
  'ASUS ROG STRIX Z790',
  'MSI MAG B550 TOMAHAWK',
  'ASRock X670E Taichi',
];

final Random _random = Random.secure();

Object? _fallbackJson(Object? nonEncodable) {
  return nonEncodable?.toString();
}

class _NeDeviceProfile {
  _NeDeviceProfile({
    required this.deviceId,
    required this.clientSign,
    required this.mode,
    required this.osver,
    required this.wnmcid,
  });

  factory _NeDeviceProfile.generate() {
    final mac = List<String>.generate(
      6,
      (_) =>
          _random.nextInt(256).toRadixString(16).padLeft(2, '0').toUpperCase(),
    ).join(':');
    final randomStr = StringBuffer();
    for (var i = 0; i < 8; i++) {
      final code = 65 + _random.nextInt(26);
      randomStr.writeCharCode(code);
    }
    final hashHex = StringBuffer();
    for (var i = 0; i < 64; i++) {
      final nibble = _random.nextInt(16);
      hashHex.write(nibble.toRadixString(16));
    }
    final clientSign = '$mac@@@${randomStr.toString()}@@@@@@$hashHex';
    final wnmcid = StringBuffer();
    for (var i = 0; i < 6; i++) {
      final c = 97 + _random.nextInt(26);
      wnmcid.writeCharCode(c);
    }
    final ts =
        DateTime.now().millisecondsSinceEpoch -
        Random.secure().nextInt(9000) -
        1000;
    wnmcid.write('.$ts.01.0');
    return _NeDeviceProfile(
      deviceId: neDeviceIds[_random.nextInt(neDeviceIds.length)],
      clientSign: clientSign,
      mode: _modePool[_random.nextInt(_modePool.length)],
      osver:
          'Microsoft-Windows-10--build-${200 + _random.nextInt(100)}00-64bit',
      wnmcid: wnmcid.toString(),
    );
  }

  final String deviceId;
  final String clientSign;
  final String mode;
  final String osver;
  final String wnmcid;
}
