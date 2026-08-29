// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// QQ Music provider (https://y.qq.com).
//
// `QmProvider` mirrors the upstream Python LDDC's `LDDC\core\api\lyrics\qm.py`.
//
// The single transport endpoint is `POST https://u.y.qq.com/cgi-bin/musicu.fcg`
// (no EAPI, no `sign` parameter — the Android-keyboard envelope is just a
// `{comm, request}` JSON). QRC cloud lyrics are returned as hex-encoded blobs;
// decryption uses the same 3DES-EDE-EDE key (`!@#)(*$%123ZXC!@!@#)(NHL`) and
// the deflate inflate path implemented in `lib/src/crypto/qrc.dart`.
//
// State managed internally:
//   - A 24-byte 3DES key constant (24 bytes) used during cloud-QRC decrypt.
//   - A static `comm` block mirror with a per-process randomized `rom` suffix.
//   - A TTL-cached (30 min) `comm.{uid,sid,userip}` populated by `GetSession`.
//   - A fabricated `search_id` for `DoSearchForQQ*` requests.

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../crypto/qrc.dart';
import '../exceptions.dart';
import '../http_client.dart';
import '../models/api_result_list.dart';
import '../models/artist.dart';
import '../models/language.dart';
import '../models/lyric_info.dart';
import '../models/lyrics.dart';
import '../models/lyrics_models.dart';
import '../models/lyrics_type.dart';
import '../models/search_info.dart';
import '../models/search_type.dart';
import '../models/song_info.dart';
import '../models/song_list_info.dart';
import '../models/source.dart';
import '../parser/qrc.dart';
import '../provider/lyrics_provider.dart';
import '../provider/query.dart';

class QmProvider extends CloudLyricsProvider {
  QmProvider(super.http) : super(source: Source.qm);

  static const String _endpoint = 'https://u.y.qq.com/cgi-bin/musicu.fcg';

  /// Search method for songs and song lists.
  static const String _searchLiteMethod = 'DoSearchForQQMusicLite';

  /// Search method for albums (returns the Desktop-shaped payload).
  static const String _searchDesktopMethod = 'DoSearchForQQMusicDesktop';

  /// `module` is constant for all searches.
  static const String _searchModule = 'music.search.SearchCgiService';

  /// Album track listing.
  static const String _albumListMethod = 'GetAlbumSongList';
  static const String _albumListModule = 'music.musichallAlbum.AlbumSongList';

  /// Playlist (diss) track listing.
  static const String _playlistListMethod = 'CgiGetDiss';
  static const String _playlistListModule = 'srf_diss_info.DissInfoServer';

  /// Lyric fetch.
  static const String _lyricMethod = 'GetPlayLyricInfo';
  static const String _lyricModule = 'music.musichallSong.PlayLyricInfo';

  /// Session bootstrap.
  static const String _sessionMethod = 'GetSession';
  static const String _sessionModule = 'music.getSession.session';

  static const Duration _commTtl = Duration(minutes: 30);

  /// Random `rom` build variant — different on each construction but stable
  /// for the process lifetime (matches LDDC's `random.choice(["5","4","2"])`).
  late final String _romTag =
      _romVariants[_random.nextInt(_romVariants.length)];

  /// Lazily bootstrapped (uid, sid, userip).
  Map<String, String>? _session;
  DateTime? _sessionLoadedAt;

  @override
  String get name => 'QQ Music';

  @override
  Set<SearchType> get supportedSearchTypes => {
    SearchType.song,
    SearchType.album,
    SearchType.songList,
  };

  Map<String, Object?> _baseComm() => <String, Object?>{
    'ct': 11,
    'cv': '1003006',
    'v': '1003006',
    'os_ver': '15',
    'phonetype': '24122RKC7C',
    'rom':
        'Redmi/miro/miro:15/AE3A.240806.005/OS2.0.10$_romTag.0.VOMCNXM:user/release-keys',
    'tmeAppID': 'qqmusiclight',
    'nettype': 'NETWORK_WIFI',
    'udid': '0',
  };

  Future<Map<String, Object?>> _ensureComm() async {
    final cached = _session;
    if (cached != null &&
        _sessionLoadedAt != null &&
        DateTime.now().difference(_sessionLoadedAt!) < _commTtl) {
      return <String, Object?>{..._baseComm(), ...cached};
    }
    try {
      final data = await _request(
        _sessionMethod,
        _sessionModule,
        <String, Object?>{'caller': 0, 'uid': '0', 'vkey': 0},
        needsSession: false,
      );
      final sessionRaw = data['session'];
      final session = sessionRaw is Map
          ? sessionRaw.cast<String, dynamic>()
          : const <String, dynamic>{};
      final map = <String, String>{
        'uid': (session['uid'] ?? '0').toString(),
        'sid': (session['sid'] ?? '').toString(),
        'userip': (session['userip'] ?? '').toString(),
      };
      _session = map;
      _sessionLoadedAt = DateTime.now();
      return <String, Object?>{..._baseComm(), ...map};
    } on Object {
      // Cache the empty session so we only attempt GetSession once per TTL.
      _session = const <String, String>{};
      _sessionLoadedAt = DateTime.now();
      return _baseComm();
    }
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String module,
    Map<String, Object?> param, {
    bool needsSession = true,
  }) async {
    final comm = needsSession ? await _ensureComm() : _baseComm();
    final body = jsonEncode(<String, Object?>{
      'comm': comm,
      'request': <String, Object?>{
        'method': method,
        'module': module,
        'param': param,
      },
    });
    final response = await http.send(
      LyricsHttpRequest(
        method: 'POST',
        uri: Uri.parse(_endpoint),
        body: body,
        encoding: utf8,
        headers: <String, String>{
          'cookie': 'tmeLoginType=-1;',
          'content-type': 'application/json',
          'accept-encoding': 'gzip',
          'user-agent': 'okhttp/3.14.9',
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
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw LyricsException('QM unexpected payload: ${response.body}');
    }
    final topCode = (decoded['code'] as num?)?.toInt();
    final request = decoded['request'];
    if (request is Map) {
      final innerCode = (request['code'] as num?)?.toInt();
      if (topCode != 0 && topCode != null) {
        throw LyricsException('QM API error code=$topCode');
      }
      if (innerCode != 0 && innerCode != null) {
        throw LyricsException('QM API error code=$innerCode');
      }
      final data = request['data'];
      if (data is Map) {
        return data.cast<String, dynamic>();
      }
    }
    if (topCode != 0 && topCode != null) {
      throw LyricsException('QM API error code=$topCode');
    }
    return <String, dynamic>{};
  }

  @override
  Future<APIResultList<SongInfo>> search(SearchQuery query) async {
    final param = <String, Object?>{
      'search_id': _buildSearchId(),
      'remoteplace': 'search.android.keyboard',
      'query': query.keyword,
      'search_type': _searchTypeWire(query.searchType),
      'num_per_page': 20,
      'page_num': query.page,
      'highlight': 0,
      'nqc_flag': 0,
      'page_id': 1,
      'grp': 1,
    };
    final method = query.searchType == SearchType.album
        ? _searchDesktopMethod
        : _searchLiteMethod;
    final data = await _request(method, _searchModule, param);
    final body = (data['body'] as Map?)?.cast<String, dynamic>() ?? const {};
    final raw = body['item_song'];
    final list = raw is List ? raw : const <dynamic>[];
    final items = <SongInfo>[
      for (final entry in list.whereType<Map>())
        _parseSongEntry(entry.cast<String, dynamic>()),
    ];
    final total = _resolveTotal(
      body,
      items.length,
      startIndexForPage(query.page),
    );
    return APIResultList<SongInfo>(
      items: items,
      info: SearchInfo.single(
        source: source,
        keyword: query.keyword,
        searchType: query.searchType,
        page: query.page,
      ),
      sourceRanges: items.isEmpty
          ? const {}
          : {source: _range(items.length, total)},
    );
  }

  @override
  Future<APIResultList<SongListInfo>?> searchSongList(SearchQuery query) async {
    if (!supports(query.searchType)) return null;
    final param = <String, Object?>{
      'search_id': _buildSearchId(),
      'remoteplace': 'search.android.keyboard',
      'query': query.keyword,
      'search_type': _searchTypeWire(query.searchType),
      'num_per_page': 20,
      'page_num': query.page,
      'highlight': 0,
      'nqc_flag': 0,
      'page_id': 1,
      'grp': 1,
    };
    final data = await _request(
      query.searchType == SearchType.album
          ? _searchDesktopMethod
          : _searchLiteMethod,
      _searchModule,
      param,
    );
    final body = (data['body'] as Map?)?.cast<String, dynamic>() ?? const {};

    if (query.searchType == SearchType.album) {
      final albums =
          (body['album'] is Map
              ? ((body['album'] as Map)['list'] as List?)
              : null) ??
          const <dynamic>[];
      final items = <SongListInfo>[
        for (final entry in albums.whereType<Map>())
          _parseAlbumEntry(entry.cast<String, dynamic>()),
      ];
      final total = _resolveAlbumTotal(body, items.length);
      return APIResultList<SongListInfo>(
        items: items,
        info: SearchInfo.single(
          source: source,
          keyword: query.keyword,
          searchType: query.searchType,
          page: query.page,
        ),
        sourceRanges: items.isEmpty
            ? const {}
            : {source: _range(items.length, total)},
      );
    }

    final list = body['item_songlist'];
    final raw = list is List ? list : const <dynamic>[];
    final items = <SongListInfo>[
      for (final entry in raw.whereType<Map>())
        _parseSonglistEntry(entry.cast<String, dynamic>()),
    ];
    final total = _resolveTotal(
      body,
      items.length,
      startIndexForPage(query.page),
    );
    return APIResultList<SongListInfo>(
      items: items,
      info: SearchInfo.single(
        source: source,
        keyword: query.keyword,
        searchType: query.searchType,
        page: query.page,
      ),
      sourceRanges: items.isEmpty
          ? const {}
          : {source: _range(items.length, total)},
    );
  }

  @override
  Future<APIResultList<SongInfo>> getSongList(
    SongListInfo info, {
    int page = 1,
    int? pageSize,
  }) async {
    return info.type == SongListType.album
        ? _getAlbumSongList(info)
        : _getPlaylistSongList(info);
  }

  Future<APIResultList<SongInfo>> _getAlbumSongList(SongListInfo info) async {
    final param = <String, Object?>{
      'albumID': int.tryParse(info.id) ?? 0,
      'order': 2,
      'begin': 0,
      'num': -1,
    };
    final data = await _request(_albumListMethod, _albumListModule, param);
    final list = data['songList'];
    final raw = list is List ? list : const <dynamic>[];
    final items = <SongInfo>[
      for (final wrapper in raw.whereType<Map>())
        if (wrapper['songInfo'] is Map)
          _parseSongEntry((wrapper['songInfo'] as Map).cast<String, dynamic>()),
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
          : {source: _range(items.length, items.length)},
    );
  }

  Future<APIResultList<SongInfo>> _getPlaylistSongList(
    SongListInfo info,
  ) async {
    final param = <String, Object?>{
      'disstid': int.tryParse(info.id) ?? 0,
      'dirid': 0,
      'onlysonglist': 0,
      'song_begin': 0,
      'song_num': -1,
      'userinfo': 1,
      'pic_dpi': 800,
      'orderlist': 1,
    };
    final data = await _request(
      _playlistListMethod,
      _playlistListModule,
      param,
    );
    final list = data['songlist'];
    final raw = list is List ? list : const <dynamic>[];
    final items = <SongInfo>[
      for (final entry in raw.whereType<Map>())
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
          : {source: _range(items.length, items.length)},
    );
  }

  @override
  Future<List<LyricInfo>> getLyricsList(LyricsListQuery query) async {
    throw UnsupportedError('$name does not support getLyricsList');
  }

  @override
  Future<Lyrics> getLyrics(LyricInfo info) async {
    final song = info.songInfo;
    if (song.title == null ||
        song.album == null ||
        song.id == null ||
        song.duration == null) {
      throw const LyricsException(
        'QM lyrics require title/album/id/duration on the song',
      );
    }
    final intervalSec = song.duration! ~/ 1000;
    final artists = (song.artist?.names ?? const <String>[]);
    final singerName = artists.join('/');
    final param = <String, Object?>{
      'albumName': base64.encode(utf8.encode(song.album!)),
      'crypt': 1,
      'ct': 19,
      'cv': 2111,
      'interval': intervalSec,
      'lrc_t': 0,
      'qrc': 1,
      'qrc_t': 0,
      'roma': 1,
      'roma_t': 0,
      'singerName': base64.encode(utf8.encode(singerName)),
      'songID': int.tryParse(song.id!) ?? 0,
      'songName': base64.encode(utf8.encode(song.title!)),
      'trans': 1,
      'trans_t': 0,
      'type': 0,
    };
    final data = await _request(_lyricMethod, _lyricModule, param);
    final lyrics = Lyrics(info);
    final entries = <(String, String, String)>[
      // (track key, blob key, version key)
      ('orig', 'lyric', 'qrc_t'),
      ('ts', 'trans', 'trans_t'),
      ('roma', 'roma', 'roma_t'),
    ];
    for (final entry in entries) {
      final blob = (data[entry.$2] as String?) ?? '';
      if (blob.isEmpty) continue;
      final versionKey = entry.$3;
      var version = (data[versionKey]?.toString()) ?? '0';
      if (entry.$2 == 'lyric' && version == '0') {
        version = (data['lrc_t']?.toString()) ?? '0';
      }
      if (version == '0') continue;
      String plaintext;
      try {
        final bytes = _hexDecode(blob);
        plaintext = qrcDecrypt(bytes);
      } on Object catch (e) {
        throw LyricsDecryptError(
          'QM QRC decrypt failed for ${entry.$1}',
          format: 'qrc-cloud',
          cause: e,
        );
      }
      final parsed = qrcStrParse(plaintext);
      if (entry.$1 == 'orig') {
        lyrics.tags.addAll(parsed.tags);
      }
      lyrics[entry.$1] = parsed.data;
      lyrics.types[entry.$1] = judgeLyricsType(parsed.data);
    }
    return lyrics;
  }

  // -----------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------

  SourceRange _range(int count, int total) =>
      (start: 0, end: count - 1, total: total);

  int startIndexForPage(int page) => (page - 1) * 20;

  /// LDDC's heuristic: a full page reveals the real total via `meta.sum`;
  /// otherwise the total is inferred from the current page's reach.
  int _resolveTotal(Map<String, dynamic> body, int count, int startIndex) {
    final meta = body['meta'];
    if (meta is Map && count == 20) {
      final sum = (meta['sum'] as num?)?.toInt();
      if (sum != null) return sum;
    }
    return startIndex + count;
  }

  int _resolveAlbumTotal(Map<String, dynamic> body, int count) {
    final meta = body['meta'];
    if (meta is Map && count == 20) {
      final sum = (meta['sum'] as num?)?.toInt();
      if (sum != null) return sum;
    }
    return count;
  }

  SongInfo _parseSongEntry(Map<String, dynamic> entry) {
    final singersRaw = entry['singer'];
    final singers = singersRaw is List
        ? singersRaw
              .whereType<Map>()
              .map((m) => (m['name'] ?? '').toString())
              .where((s) => s.isNotEmpty)
              .toList()
        : const <String>[];
    final albumMap = entry['album'];
    final albumName = albumMap is Map
        ? (albumMap['name']?.toString() ?? '')
        : '';
    final interval = (entry['interval'] as num?)?.toInt() ?? 0;
    final langCode = (entry['language'] as num?)?.toInt();
    return SongInfo(
      source: source,
      id: entry['id']?.toString(),
      mid: entry['mid']?.toString(),
      title: entry['title']?.toString(),
      subtitle: entry['subtitle']?.toString(),
      artist: singers.isEmpty ? null : Artist(singers),
      album: albumName.isEmpty ? null : albumName,
      duration: interval * 1000,
      language: _qmLanguage(langCode),
    );
  }

  SongListInfo _parseAlbumEntry(Map<String, dynamic> entry) {
    final publicTime = entry['publicTime']?.toString() ?? '';
    return SongListInfo(
      source: source,
      type: SongListType.album,
      id: (entry['albumID']?.toString()) ?? '',
      title: entry['albumName']?.toString() ?? '',
      imgUrl: entry['albumPic']?.toString() ?? '',
      author: entry['singerName']?.toString() ?? '',
      publishTime: _cstDateStringToUnix(publicTime),
      songCount: (entry['song_count'] as num?)?.toInt(),
      mid: entry['albumMID']?.toString(),
    );
  }

  SongListInfo _parseSonglistEntry(Map<String, dynamic> entry) {
    final create = entry['createtime']?.toString() ?? '';
    return SongListInfo(
      source: source,
      type: SongListType.songList,
      id: (entry['dissid']?.toString()) ?? '',
      title: entry['dissname']?.toString() ?? '',
      imgUrl: entry['logo']?.toString() ?? '',
      author: entry['nickname']?.toString() ?? '',
      publishTime: _cstDateStringToUnix(create),
      songCount: (entry['songnum'] as num?)?.toInt(),
    );
  }

  Language? _qmLanguage(int? code) {
    switch (code) {
      case 9:
        return Language.instrumental;
      case 5:
        return Language.english;
      case 4:
        return Language.korean;
      case 3:
        return Language.japanese;
      case 1:
      case 0:
        return Language.chinese;
      default:
        return Language.other;
    }
  }

  /// Parses `yyyy-MM-dd` strings from QQ's CST timezone into unix seconds.
  int? _cstDateStringToUnix(String raw) {
    if (raw.isEmpty) return null;
    try {
      final dt = DateTime.parse(raw);
      // QQ dates are CST (+08:00). The naive parse returns local; we normalize
      // by treating the body as UTC midnight, then offset by +08:00 to UTC.
      final cstOffsetSeconds = 8 * 3600;
      final asUtc = DateTime.utc(dt.year, dt.month, dt.day);
      final unixSeconds =
          asUtc.millisecondsSinceEpoch ~/ 1000 - cstOffsetSeconds;
      return unixSeconds;
    } on Object {
      return null;
    }
  }

  int _searchTypeWire(SearchType type) {
    switch (type) {
      case SearchType.song:
        return 0;
      case SearchType.album:
        return 2;
      case SearchType.songList:
        return 3;
      case SearchType.artist:
      case SearchType.lyrics:
        return 0;
    }
  }

  String _buildSearchId() {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return (_random.nextInt(20) * 18014398509481984 +
            _random.nextInt(4194304) * 4294967296 +
            nowMs % 86400000)
        .toString();
  }

  List<int> _hexDecode(String hex) {
    if (hex.length % 2 != 0) {
      throw const FormatException('QM QRC hex length is odd');
    }
    final bytes = <int>[];
    for (var i = 0; i < hex.length; i += 2) {
      final hi = int.tryParse(hex[i], radix: 16);
      final lo = int.tryParse(hex[i + 1], radix: 16);
      if (hi == null || lo == null) {
        throw const FormatException('QM QRC hex invalid char');
      }
      bytes.add((hi << 4) | lo);
    }
    return bytes;
  }

  LyricsType judgeLyricsType(LyricsData data) {
    if (data.isEmpty) return LyricsType.plainText;
    for (final line in data) {
      if (line.words.length > 1) return LyricsType.verbatim;
      if (line.start != null) return LyricsType.lineByLine;
    }
    return LyricsType.plainText;
  }
}

const List<String> _romVariants = ['5', '4', '2'];
final Random _random = Random.secure();
