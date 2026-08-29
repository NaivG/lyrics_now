// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Kugou music provider (https://www.kugou.com).
//
// `KGAPI` mirrors the upstream Python LDDC's `LDDC\core\api\lyrics\kg.py`.
// The provider touches four sub-APIs:
//
//   - `userservice.kugou.com/risk/v1/r_register_dev`        �?dfid bootstrap
//   - `complexsearch.kugou.com/v2/search/song`               �?song search
//   - `complexsearch.kugou.com/v1/search/{album,special}`    �?album / playlist
//   - `lyrics.kugou.com/v1/search` + `lyrics.kugou.com/download` �?lyrics
//   - `openapi.kugou.com/kmr/v1/album_songlist`              �?album tracks
//   - `pubsongscdn.kugou.com/v4/get_other_list_file`        �?playlist tracks
//
// Every request carries the canonical signature:
//   md5(`LnT6xpN3khm36zse0QzvmgTZ3waWdRSA`
//       + "k=v" sorted (dict-values JSON-stringified, others toString)
//       + body
//       + key).

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;

import '../crypto/krc.dart';
import '../crypto/kugou_sign.dart';
import '../exceptions.dart';
import '../http_client.dart';
import '../models/api_result_list.dart';
import '../models/artist.dart';
import '../models/language.dart';
import '../models/lyric_info.dart';
import '../models/lyrics.dart';
import '../models/search_info.dart';
import '../models/search_type.dart';
import '../models/song_info.dart';
import '../models/song_list_info.dart';
import '../models/source.dart';
import '../parser/krc.dart';
import '../parser/lrc.dart';
import '../provider/lyrics_provider.dart';
import '../provider/query.dart';

class KgProvider extends CloudLyricsProvider {
  KgProvider(super.http) : super(source: Source.kg);

  // Lazy-init state for the dfid (device fingerprint id).
  String? _dfid;
  DateTime? _dfidLoadedAt;

  static const Duration _dfidTtl = Duration(minutes: 30);
  static const String _placeholderDfid = '-';

  @override
  String get name => 'Kugou';

  @override
  Set<SearchType> get supportedSearchTypes => {
    SearchType.song,
    SearchType.album,
    SearchType.songList,
  };

  @override
  Future<APIResultList<SongInfo>> search(SearchQuery query) async {
    final headers = _kgHeaders('SearchSong');
    final mid = headers['mid']!;
    final params = <String, Object?>{
      'userid': '0',
      'appid': '3116',
      'token': '',
      'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'iscorrection': '1',
      'uuid': '-',
      'mid': mid,
      'dfid': await _ensureDfid(),
      'clientver': '11070',
      'platform': 'AndroidFilter',
      'sorttype': '0',
      'keyword': query.keyword,
      'pagesize': 20,
      'page': query.page,
    };
    final uri = Uri.parse('http://complexsearch.kugou.com/v2/search/song');
    final response = await http.send(
      LyricsHttpRequest(
        method: 'GET',
        uri: uri,
        queryParameters: _queryMap(params),
        headers: headers,
      ),
    );
    final payload = jsonDecode(response.body);
    _checkPayload(payload);
    final list = _readList(payload, ['data', 'lists']);
    final items = <SongInfo>[
      for (final entry in list.whereType<Map>())
        _parseSongEntry(entry.cast<String, dynamic>()),
    ];
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
          : {source: (start: 0, end: items.length - 1, total: items.length)},
    );
  }

  @override
  Future<APIResultList<SongListInfo>?> searchSongList(SearchQuery query) async {
    if (query.searchType != SearchType.songList &&
        query.searchType != SearchType.album) {
      return null;
    }
    final headers = _kgHeaders('SearchSongRecommand');
    final mid = headers['mid']!;
    final params = <String, Object?>{
      'userid': '0',
      'appid': '3116',
      'token': '',
      'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'iscorrection': '1',
      'uuid': '-',
      'mid': mid,
      'dfid': await _ensureDfid(),
      'clientver': '11070',
      'platform': 'AndroidFilter',
      'keyword': query.keyword,
      'pagesize': 20,
      'page': query.page,
    };
    final uri = Uri.parse('http://complexsearch.kugou.com/v1/search/special');
    final response = await http.send(
      LyricsHttpRequest(
        method: 'GET',
        uri: uri,
        queryParameters: _queryMap(params),
        headers: headers,
      ),
    );
    final payload = jsonDecode(response.body);
    _checkPayload(payload);
    final list = _readList(payload, ['data', 'lists']);
    final items = <SongListInfo>[
      for (final entry in list.whereType<Map>())
        _parseSonglistEntry(entry.cast<String, dynamic>()),
    ];
    return APIResultList<SongListInfo>(
      items: items,
      info: SearchInfo.many(
        sources: [source],
        keyword: query.keyword,
        searchType: query.searchType,
        page: query.page,
      ),
      sourceRanges: items.isEmpty
          ? const {}
          : {source: (start: 0, end: items.length - 1, total: items.length)},
    );
  }

  @override
  Future<APIResultList<SongInfo>> getSongList(
    SongListInfo info, {
    int page = 1,
    int? pageSize,
  }) async {
    return info.type == SongListType.album
        ? _getAlbumSongList(info, page: page, pageSize: pageSize)
        : _getPlaylistSongList(info, page: page, pageSize: pageSize);
  }

  Future<APIResultList<SongInfo>> _getAlbumSongList(
    SongListInfo info, {
    required int page,
    required int? pageSize,
  }) async {
    final body = jsonEncode(<String, Object?>{
      'pagesize': (pageSize ?? 100).toString(),
      'album_id': info.id,
      'page': page.toString(),
    });
    final dfid = await _ensureDfid();
    final headers = {
      ..._kgHeaders('album_song_list'),
      'KG-TID': '221',
      'Content-Type': 'application/json;charset=UTF-8',
    };
    final mid = headers['mid']!;
    final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final commonParams = <String, Object?>{
      'dfid': dfid,
      'appid': '3116',
      'mid': mid,
      'clientver': '11070',
      'clienttime': nowSec,
      'uuid': '-',
      'pagesize': (pageSize ?? 100).toString(),
      'album_id': info.id,
      'page': page.toString(),
    };
    final signature = kugouSignature(commonParams, body: body);
    final query = _queryMap(commonParams)..['signature'] = signature;
    final response = await http.send(
      LyricsHttpRequest(
        method: 'POST',
        uri: Uri.parse('http://openapi.kugou.com/kmr/v1/album_songlist'),
        queryParameters: query,
        body: body,
        headers: headers,
      ),
    );
    final payload = jsonDecode(response.body);
    _checkPayload(payload);
    final list = _readList(payload, ['data', 'info', 'songs']);
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
          : {source: (start: 0, end: items.length - 1, total: items.length)},
    );
  }

  Future<APIResultList<SongInfo>> _getPlaylistSongList(
    SongListInfo info, {
    required int page,
    required int? pageSize,
  }) async {
    final dfid = await _ensureDfid();
    final headers = _kgHeaders('SongList');
    final mid = headers['mid']!;
    final params = <String, Object?>{
      'userid': '0',
      'appid': '3116',
      'token': '',
      'clienttime': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'iscorrection': '1',
      'uuid': '-',
      'mid': mid,
      'dfid': dfid,
      'clientver': '11070',
      'platform': 'AndroidFilter',
      'specialid': info.id,
      'page': page,
      'pagesize': pageSize ?? 300,
    };
    final response = await http.send(
      LyricsHttpRequest(
        method: 'GET',
        uri: Uri.parse('https://pubsongscdn.kugou.com/v4/get_other_list_file'),
        queryParameters: _queryMap(params),
        headers: headers,
      ),
    );
    final payload = jsonDecode(response.body);
    _checkPayload(payload);
    final list = _readList(payload, ['data', 'list']);
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
          : {source: (start: 0, end: items.length - 1, total: items.length)},
    );
  }

  @override
  Future<List<LyricInfo>> getLyricsList(LyricsListQuery query) async {
    final target = query.song;
    if (target.id == null && target.hash == null) return const [];
    final params = <String, Object?>{
      'appid': '3116',
      'clientver': '11070',
      'album_audio_id': target.id ?? '',
      'duration': target.durationMs ?? 0,
      'hash': target.hash ?? '',
      'lrctxt': '1',
      'man': 'no',
      'keyword': _lyricsKeyword(target),
    };
    final uri = Uri.parse('https://lyrics.kugou.com/v1/search');
    final response = await http.send(
      LyricsHttpRequest(
        method: 'GET',
        uri: uri,
        queryParameters: _queryMap(params),
        headers: _kgHeaders('Lyric'),
      ),
    );
    final payload = jsonDecode(response.body);
    _checkPayload(payload);
    final list = _readList(payload, ['candidates']);
    return <LyricInfo>[
      for (final entry in list.whereType<Map>())
        _buildLyricInfo(
          entry.cast<String, dynamic>(),
          SongInfo(
            source: source,
            title: target.title,
            artist: target.artist == null ? null : Artist(target.artist!),
            album: target.album,
            id: target.id,
            hash: target.hash,
            duration: target.durationMs,
          ),
        ),
    ];
  }

  @override
  Future<Lyrics> getLyrics(LyricInfo info) async {
    if (info.id == null || info.accessKey == null) {
      throw const LyricsException('KG lyrics require id/accessKey');
    }
    final params = <String, Object?>{
      'accesskey': info.accessKey!,
      'charset': 'utf8',
      'client': 'mobi',
      'fmt': 'krc',
      'id': info.id!,
      'ver': '1',
    };
    final headers = _kgHeaders('Lyric');
    final mid = headers['mid']!;
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final query = <String, String>{
      ..._queryMap(params),
      'appid': '3116',
      'clientver': '11070',
      'clienttime': (nowMs ~/ 1000).toString(),
      'mid': mid,
      'dfid': await _ensureDfid(),
      'uuid': '-',
      'userid': '0',
      'token': '',
      'iscorrection': '1',
      'platform': 'AndroidFilter',
    };
    final uri = Uri.parse('http://lyrics.kugou.com/download');
    final response = await http.send(
      LyricsHttpRequest(
        method: 'GET',
        uri: uri,
        queryParameters: query,
        headers: headers,
      ),
    );

    final payload = jsonDecode(response.body);
    if (payload is! Map) {
      throw LyricsNotFoundException('KG download returned no payload');
    }
    _checkPayload(payload);
    final content = payload['content'] as String?;
    final contentType = payload['contenttype'] as int? ?? 1;
    if (content == null) {
      throw LyricsNotFoundException('KG download missing content');
    }

    final bytes = base64.decode(content);
    final lyrics = Lyrics(info);

    if (contentType == 2) {
      final text = utf8.decode(bytes, allowMalformed: true);
      if (text.trim().startsWith('[')) {
        try {
          final parsed = parseLrc(text);
          lyrics['orig'] = parsed.data;
          lyrics.types['orig'] = judgeLyricsType(parsed.data);
          lyrics.tags.addAll(parsed.tags);
        } on Object {
          final plain = parsePlaintext(text);
          lyrics['orig'] = plain;
          lyrics.types['orig'] = judgeLyricsType(plain);
        }
      } else {
        final plain = parsePlaintext(text);
        lyrics['orig'] = plain;
        lyrics.types['orig'] = judgeLyricsType(plain);
      }
      return lyrics;
    }

    final plaintext = krcDecrypt(bytes);
    final parsed = krc2MData(plaintext);
    parsed.data.forEach((key, value) {
      lyrics[key] = value;
      lyrics.types[key] = judgeLyricsType(value);
    });
    lyrics.tags.addAll(parsed.tags);
    return lyrics;
  }

  // -----------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------

  Map<String, String> _kgHeaders(String module) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    return kugouHeaders(module, nowMs);
  }

  Future<String> _ensureDfid() async {
    final cached = _dfid;
    final loadedAt = _dfidLoadedAt;
    if (cached != null &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _dfidTtl) {
      return cached;
    }
    try {
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final bodyMap = <String, Object?>{'uuid': ''};
      final body = base64.encode(utf8.encode(jsonEncode(bodyMap)));
      final params = <String, Object?>{
        'appid': '1014',
        'platid': '4',
        'mid': crypto.md5.convert(utf8.encode('$nowMs')).toString(),
      };
      final sortedValues =
          (params.values.map((v) => v.toString()).toList()..sort()).join();
      final signature = crypto.md5
          .convert(utf8.encode('1014${sortedValues}1014'))
          .toString();
      final response = await http.send(
        LyricsHttpRequest(
          method: 'POST',
          uri: Uri.parse(
            'https://userservice.kugou.com/risk/v1/r_register_dev',
          ),
          queryParameters: {
            for (final entry in params.entries)
              entry.key: entry.value.toString(),
            'signature': signature,
          },
          body: body,
          headers: const <String, String>{
            'User-Agent': 'Android14-1070-11070-201-0-wifi',
            'Content-Type': 'application/json',
          },
        ),
      );
      final payload = jsonDecode(response.body);
      if (payload is Map && payload['data'] is Map) {
        final dfid = (payload['data'] as Map)['dfid']?.toString();
        if (dfid != null && dfid.isNotEmpty) {
          _dfid = dfid;
          _dfidLoadedAt = DateTime.now();
          return dfid;
        }
      }
    } on Object {
      // Fall through to placeholder dfid.
    }
    _dfid = _placeholderDfid;
    _dfidLoadedAt = DateTime.now();
    return _placeholderDfid;
  }

  void _checkPayload(dynamic payload) {
    if (payload is! Map) return;
    final status = payload['status'];
    // Kugou uses status: 1 for success (lyrics API) and status: 0 for success/empty (search API)
    // Only reject codes >= 200 which indicate real errors (e.g. 201 = not found / rate limit)
    if (status is num && status >= 200) {
      final msg = payload['error']?.toString() ?? '';
      throw LyricsException('Kugou API error: status=$status${msg.isNotEmpty ? ' $msg' : ''}');
    }
    final errcode = payload['errcode'];
    if (errcode is num && errcode != 0) {
      final msg = payload['errmsg']?.toString() ?? '';
      throw LyricsException('Kugou API error: errcode=$errcode${msg.isNotEmpty ? ' $msg' : ''}');
    }
  }

  Map<String, String> _queryMap(Map<String, Object?> params) {
    final out = <String, String>{};
    params.forEach((k, v) {
      if (v == null) return;
      out[k] = v.toString();
    });
    out['signature'] = kugouSignature(params);
    return out;
  }

  List<dynamic> _readList(dynamic payload, List<String> path) {
    var cursor = payload;
    for (final key in path) {
      if (cursor is Map && cursor.containsKey(key)) {
        cursor = cursor[key];
      } else {
        return const <dynamic>[];
      }
    }
    return cursor is List ? cursor : const <dynamic>[];
  }

  SongInfo _parseSongEntry(Map<String, dynamic> entry) {
    final singersRaw = entry['Singers'];
    final singers = singersRaw is List
        ? singersRaw
              .whereType<Map>()
              .map((m) => m['name']?.toString() ?? '')
              .where((s) => s.isNotEmpty)
              .toList()
        : const <String>[];
    final transParam = entry['trans_param'];
    final languageLabel = transParam is Map
        ? (transParam['language']?.toString() ?? 'other')
        : 'other';
    final durationSec = entry['Duration'] is num
        ? (entry['Duration'] as num).toInt()
        : 0;
    return SongInfo(
      source: source,
      title: entry['SongName']?.toString(),
      subtitle: entry['Auxiliary']?.toString(),
      artist: singers.isEmpty ? null : Artist(singers),
      album: entry['AlbumName']?.toString(),
      duration: durationSec * 1000,
      id: entry['ID']?.toString(),
      hash: entry['FileHash']?.toString(),
      language: _kgLanguage(languageLabel),
    );
  }

  SongListInfo _parseSonglistEntry(Map<String, dynamic> entry) {
    final createdAt = entry['publish_time']?.toString() ?? '';
    final ts = _parsePublishTime(createdAt);
    return SongListInfo(
      source: source,
      type: SongListType.songList,
      id: entry['gid']?.toString() ?? entry['specialid']?.toString() ?? '',
      title: entry['specialname']?.toString() ?? '',
      imgUrl: entry['img']?.toString() ?? '',
      author: entry['nickname']?.toString() ?? '',
      publishTime: ts,
      songCount: entry['song_count'] is num
          ? (entry['song_count'] as num).toInt()
          : null,
    );
  }

  LyricInfo _buildLyricInfo(Map<String, dynamic> entry, SongInfo song) {
    return LyricInfo(
      source: source,
      songInfo: song,
      id: entry['id']?.toString(),
      accessKey: entry['accesskey']?.toString(),
      duration: entry['duration'] is num
          ? (entry['duration'] as num).toInt()
          : song.duration,
    );
  }

  String _lyricsKeyword(LyricsListTarget target) {
    final title = target.title ?? '';
    final artist = target.artist ?? '';
    if (artist.isEmpty) return title;
    if (title.isEmpty) return artist;
    return '$artist - $title';
  }

  Language? _kgLanguage(String label) {
    switch (label) {
      case '伴奏':
      case '纯音乐':
        return Language.instrumental;
      case '粤语':
      case '国语':
        return Language.chinese;
      case '英语':
        return Language.english;
      case '韩语':
        return Language.korean;
      case '日语':
        return Language.japanese;
      default:
        return Language.other;
    }
  }

  int? _parsePublishTime(String raw) {
    if (raw.isEmpty) return null;
    try {
      final normalized = raw.contains(' ')
          ? raw
          : '${raw.replaceFirst(' ', 'T')}T00:00:00';
      final parsed = DateTime.parse(normalized);
      return parsed.millisecondsSinceEpoch ~/ 1000;
    } on Object {
      return null;
    }
  }
}
