// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

class _StubHttpClient implements LyricsHttpClient {
  _StubHttpClient(this.responses);

  final Map<String, _StubResponse> responses;
  final List<Uri> calls = <Uri>[];
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
  }) => send(
    LyricsHttpRequest(
      method: 'POST',
      uri: url,
      body: body,
      encoding: encoding,
      headers: headers ?? const <String, String>{},
    ),
  );

  @override
  Future<LyricsHttpResponse> send(LyricsHttpRequest request) async {
    final url = request.effectiveUri;
    calls.add(url);
    final candidateKeys = <String>['${url.path}?${url.query}', url.path];
    _StubResponse? preset;
    for (final key in candidateKeys) {
      if (responses.containsKey(key)) {
        preset = responses[key];
        break;
      }
    }
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

class _StubResponse {
  _StubResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

String _uri(String path) => path;

void main() {
  test('KgProvider.search dispatches a /v2/search/song request', () async {
    final stub = _StubHttpClient({
      _uri('/v2/search/song'): _StubResponse(
        200,
        jsonEncode({
          'data': {
            'lists': [
              {
                'ID': 'khash',
                'FileHash': 'ABCDEF',
                'SongName': 'Sample Song',
                'Auxiliary': '',
                'Singers': [
                  {'name': 'Singer A'},
                  {'name': 'Singer B'},
                ],
                'AlbumName': 'Album',
                'Duration': 200,
                'trans_param': {'language': '国语'},
              },
            ],
          },
        }),
      ),
    });
    final provider = KgProvider(stub);
    final results = await provider.search(
      const SearchQuery(keyword: 'Sample', searchType: SearchType.song),
    );
    expect(results, isNotEmpty);
    expect(results[0].title, 'Sample Song');
    expect(results[0].hash, 'ABCDEF');
    expect(results[0].duration, 200 * 1000);
    expect(results[0].language, Language.chinese);
  });

  test('KgProvider.searchSongList returns playlists in query result', () async {
    final stub = _StubHttpClient({
      _uri('/v1/search/special'): _StubResponse(
        200,
        jsonEncode({
          'data': {
            'lists': [
              {
                'gid': 'gid123',
                'specialname': 'Top 10',
                'img': 'https://example.test/cover.jpg',
                'nickname': 'Curator',
                'song_count': 12,
                'publish_time': '2024-01-01',
              },
            ],
          },
        }),
      ),
    });
    final provider = KgProvider(stub);
    final results = await provider.searchSongList(
      const SearchQuery(keyword: 'Top', searchType: SearchType.songList),
    );
    expect(results, isNotNull);
    final list = results!;
    expect(list, isNotEmpty);
    expect(list[0].id, 'gid123');
    expect(list[0].title, 'Top 10');
    expect(list[0].songCount, 12);
  });

  test(
    'KgProvider.searchSongList returns null when searchType is not supported',
    () async {
      final stub = _StubHttpClient({});
      final provider = KgProvider(stub);
      final list = await provider.searchSongList(
        const SearchQuery(keyword: 'X', searchType: SearchType.song),
      );
      expect(list, isNull);
    },
  );
}
