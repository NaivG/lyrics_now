// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

class _StubResponse {
  _StubResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

class _StubHttpClient implements LyricsHttpClient {
  _StubHttpClient(this._responses);

  final Map<String, _StubResponse> _responses;
  final calls = <Uri>[];
  final Map<String, String> _cookies = <String, String>{};

  @override
  Future<LyricsHttpResponse> get(Uri url, {Map<String, String>? headers}) =>
      send(
        LyricsHttpRequest(
          method: 'GET',
          uri: url,
          headers: headers ?? const <String, String>{},
        ),
      );

  @override
  Future<LyricsHttpResponse> post(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
    Encoding? encoding,
  }) async {
    throw LyricsException('POST is not supported in the stub');
  }

  @override
  Future<LyricsHttpResponse> send(LyricsHttpRequest request) async {
    final url = request.effectiveUri;
    calls.add(url);
    final key = '${url.path}?${url.query}';
    final preset = _responses[key];
    if (preset == null) {
      throw LyricsException('No preset for $url');
    }
    if (preset.statusCode < 200 || preset.statusCode >= 300) {
      throw LyricsHttpStatusException(
        statusCode: preset.statusCode,
        body: preset.body,
        uri: url,
      );
    }
    return LyricsHttpResponse(
      statusCode: preset.statusCode,
      body: preset.body,
      bodyBytes: Uint8List.fromList(utf8.encode(preset.body)),
      headers: const {},
    );
  }

  @override
  Map<String, String> get cookies => _cookies;

  @override
  set cookies(Map<String, String> value) {
    _cookies
      ..clear()
      ..addAll(value);
  }

  @override
  void close() {}
}

String _uri(String path, Map<String, String> query) {
  final buffer = StringBuffer(path);
  if (query.isNotEmpty) {
    buffer.write('?');
    buffer.write(
      query.entries
          .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
          .join('&'),
    );
  }
  return buffer.toString();
}

void main() {
  test('LrclibProvider.search dispatches a /search?q=... request', () async {
    final stub = _StubHttpClient({
      _uri('/api/search', {'q': 'Jay Chou'}): _StubResponse(
        200,
        '[{"id":1,"trackName":"青花瓷","artistName":"Jay Chou",'
        '"albumName":"我很忙","duration":239.83,"instrumental":false}]',
      ),
    });
    final provider = LrclibProvider(stub);
    final list = await provider.search(
      const SearchQuery(keyword: 'Jay Chou', searchType: SearchType.song),
    );
    expect(list, isNotNull);
    expect(list.length, 1);
    final song = list.single;
    expect(song.source, Source.lrclib);
    expect(song.title, '青花瓷');
    expect(song.artist?.names, ['Jay Chou']);
    expect(song.album, '我很忙');
    expect(song.duration, 239830);
    expect(stub.calls.single.host, 'lrclib.net');
  });

  test('LrclibProvider.getLyrics parses synced lyrics', () async {
    const syncedLyrics = '[00:00.00]First\n[00:01.00]Second';
    final stub = _StubHttpClient({
      _uri('/api/get', {
        'track_name': '青花瓷',
        'artist_name': 'Jay Chou',
        'album_name': '我很忙',
        'duration': '239.83',
        'id': '1',
      }): _StubResponse(
        200,
        jsonEncode(<String, Object?>{
          'id': 1,
          'trackName': '青花瓷',
          'artistName': 'Jay Chou',
          'albumName': '我很忙',
          'duration': 239.83,
          'instrumental': false,
          'syncedLyrics': syncedLyrics,
          'plainLyrics': null,
        }),
      ),
    });
    final provider = LrclibProvider(stub);
    final lyrics = await provider.getLyrics(
      LyricInfo(
        source: Source.lrclib,
        id: '1',
        songInfo: SongInfo(
          source: Source.lrclib,
          title: '青花瓷',
          album: '我很忙',
          artist: Artist('Jay Chou'),
          duration: 239830,
        ),
      ),
    );
    final orig = lyrics['orig'] as LyricsData;
    expect(orig.length, 2);
    expect(lyrics.tags['ar'], 'Jay Chou');
  });

  test('LrclibProvider surfaces a 4xx response as an exception', () async {
    final stub = _StubHttpClient({
      _uri('/api/search', {'q': 'missing'}): _StubResponse(404, 'not found'),
    });
    final provider = LrclibProvider(stub);
    expect(
      () => provider.search(
        const SearchQuery(keyword: 'missing', searchType: SearchType.song),
      ),
      throwsA(isA<LyricsHttpStatusException>()),
    );
  });
}
