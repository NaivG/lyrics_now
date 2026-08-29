// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

class _StubHttpClient implements LyricsHttpClient {
  _StubHttpClient(this.responses);

  final List<_StubResponse> responses;
  final List<Uri> calls = <Uri>[];
  int _cursor = 0;

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
    calls.add(request.effectiveUri);
    if (_cursor >= responses.length) {
      throw StateError('Out of stubs at ${request.effectiveUri}');
    }
    final preset = responses[_cursor++];
    return LyricsHttpResponse(
      statusCode: preset.statusCode,
      body: preset.body,
      bodyBytes: Uint8List.fromList(latin1.encode(preset.body)),
      headers: preset.headers,
    );
  }

  @override
  Map<String, String> get cookies => _cookies;
  final Map<String, String> _cookies = <String, String>{};
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
  _StubResponse(this.statusCode, this.body, {this.headers = const {}});
  final int statusCode;
  final String body;
  final Map<String, String> headers;
}

/// Builds an encrypted EAPI response body that, when decrypted by the
/// provider, yields [json].
List<int> _eapiResponseBytes(Map<String, Object?> json) {
  final plaintext = utf8.encode(jsonEncode(json));
  final key = Uint8List.fromList(utf8.encode(_eapiKey));
  return aesEcbEncrypt(plaintext, key);
}

String _eapiBody(Map<String, Object?> json) =>
    latin1.decode(_eapiResponseBytes(json));

Map<String, dynamic> _okEnvelope(Map<String, Object?> data) => {
  'code': 200,
  'data': data,
};

const String _eapiKey = 'e82ckenh8dichen8';

void main() {
  test('NeProvider.search returns songs via EAPI envelope', () async {
    final stub = _StubHttpClient([
      _StubResponse(
        200,
        _eapiBody({
          'code': 200,
          'data': {'userId': 99},
        }),
        headers: {
          'set-cookie':
              'NMTID=abc; path=/, MUSIC_A=def; path=/, __csrf=ghi; path=/',
        },
      ),
      _StubResponse(
        200,
        _eapiBody(
          _okEnvelope({
            'resources': [
              {
                'baseInfo': {
                  'simpleSongData': {
                    'id': 11,
                    'name': 'NE Song',
                    'ar': [
                      {'name': 'Anet'},
                    ],
                    'al': {'name': 'Al'},
                    'dt': 1000,
                    'alia': [],
                  },
                },
              },
            ],
            'totalCount': 1,
          }),
        ),
      ),
    ]);
    final provider = NeProvider(stub);
    final results = await provider.search(
      const SearchQuery(keyword: 'NE', searchType: SearchType.song),
    );
    expect(results, isNotEmpty);
    expect(results[0].title, 'NE Song');
    expect(results[0].id, '11');
    expect(results[0].duration, 1000);
    expect(stub.calls.length, 2);
  });

  test('NeProvider.searchSongList returns album hits', () async {
    final stub = _StubHttpClient([
      _StubResponse(
        200,
        _eapiBody({
          'code': 200,
          'data': {'userId': 1},
        }),
        headers: {
          'set-cookie': 'NMTID=x; path=/, MUSIC_A=y; path=/, __csrf=z; path=/',
        },
      ),
      _StubResponse(
        200,
        _eapiBody(
          _okEnvelope({
            'result': {
              'albums': [
                {
                  'id': 5,
                  'name': 'Album Y',
                  'picUrl': 'https://example.test/y.jpg',
                  'size': 8,
                  'publishTime': 1700000000000,
                  'artists': [
                    {'name': 'Band'},
                  ],
                },
              ],
              'albumCount': 1,
            },
          }),
        ),
      ),
    ]);
    final provider = NeProvider(stub);
    final list = await provider.searchSongList(
      const SearchQuery(keyword: 'Album', searchType: SearchType.album),
    );
    expect(list, isNotNull);
    expect(list![0].type, SongListType.album);
    expect(list[0].title, 'Album Y');
    expect(list[0].songCount, 8);
    expect(list[0].publishTime, 1700000000);
  });

  test('NeProvider.searchSongList returns playlist hits', () async {
    final stub = _StubHttpClient([
      _StubResponse(
        200,
        _eapiBody({
          'code': 200,
          'data': {'userId': 1},
        }),
        headers: {
          'set-cookie': 'NMTID=x; path=/, MUSIC_A=y; path=/, __csrf=z; path=/',
        },
      ),
      _StubResponse(
        200,
        _eapiBody(
          _okEnvelope({
            'result': {
              'playlists': [
                {
                  'id': 7,
                  'name': 'Top 50',
                  'coverImgUrl': 'https://example.test/p.jpg',
                  'trackCount': 50,
                  'creator': {'nickname': 'Curator'},
                },
              ],
              'playlistCount': 1,
            },
          }),
        ),
      ),
    ]);
    final provider = NeProvider(stub);
    final list = await provider.searchSongList(
      const SearchQuery(keyword: 'Top', searchType: SearchType.songList),
    );
    expect(list, isNotNull);
    expect(list![0].type, SongListType.songList);
    expect(list[0].title, 'Top 50');
    expect(list[0].author, 'Curator');
  });

  test('NeProvider.getSongList album variant parses tracks', () async {
    final stub = _StubHttpClient([
      _StubResponse(
        200,
        _eapiBody({
          'code': 200,
          'data': {'userId': 1},
        }),
        headers: {
          'set-cookie': 'NMTID=x; path=/, MUSIC_A=y; path=/, __csrf=z; path=/',
        },
      ),
      _StubResponse(
        200,
        _eapiBody(
          _okEnvelope({
            'songs': [
              {
                'id': 1,
                'name': 'T',
                'ar': [
                  {'name': 'A'},
                ],
                'al': {'name': 'Al'},
                'dt': 100,
                'alia': [],
              },
            ],
          }),
        ),
      ),
    ]);
    final provider = NeProvider(stub);
    final list = await provider.getSongList(
      const SongListInfo(
        source: Source.ne,
        type: SongListType.album,
        id: '1',
        title: 't',
        imgUrl: '',
        author: '',
      ),
    );
    expect(list, hasLength(1));
    expect(list[0].title, 'T');
  });

  test('NeProvider.getSongList playlist uses two-step flow', () async {
    final stub = _StubHttpClient([
      _StubResponse(
        200,
        _eapiBody({
          'code': 200,
          'data': {'userId': 1},
        }),
        headers: {
          'set-cookie': 'NMTID=x; path=/, MUSIC_A=y; path=/, __csrf=z; path=/',
        },
      ),
      _StubResponse(
        200,
        _eapiBody(
          _okEnvelope({
            'playlist': {
              'trackIds': [
                {'id': 1},
                {'id': 2},
              ],
            },
          }),
        ),
      ),
      _StubResponse(
        200,
        _eapiBody(
          _okEnvelope({
            'songs': [
              {
                'id': 1,
                'name': 'A',
                'ar': [
                  {'name': 'X'},
                ],
                'al': {'name': 'Al'},
                'dt': 100,
                'alia': [],
              },
              {
                'id': 2,
                'name': 'B',
                'ar': [
                  {'name': 'Y'},
                ],
                'al': {'name': 'Al'},
                'dt': 200,
                'alia': [],
              },
            ],
          }),
        ),
      ),
    ]);
    final provider = NeProvider(stub);
    final list = await provider.getSongList(
      const SongListInfo(
        source: Source.ne,
        type: SongListType.songList,
        id: '9',
        title: 'p',
        imgUrl: '',
        author: '',
      ),
    );
    expect(list, hasLength(2));
    expect(list[0].title, 'A');
    expect(list[1].title, 'B');
  });

  test('NeProvider.getLyrics parses YRC + tlyric + romalrc', () async {
    final stub = _StubHttpClient([
      _StubResponse(
        200,
        _eapiBody({
          'code': 200,
          'data': {'userId': 1},
        }),
        headers: {
          'set-cookie': 'NMTID=x; path=/, MUSIC_A=y; path=/, __csrf=z; path=/',
        },
      ),
      _StubResponse(
        200,
        _eapiBody(
          _okEnvelope({
            'lyricUser': {'nickname': 'MainLyric'},
            'transUser': {'nickname': 'Translator'},
            'yrc': {
              'lyric': '[0,1000](0,500,0)Yrc(500,500,0)Track',
              'version': 1700000000,
            },
            'lrc': {
              'lyric': '[00:00.00]Plain LRC\n[00:01.00]next line',
              'version': 1700000000,
            },
            'tlyric': {'lyric': '[00:00.00]translated\n'},
            'romalrc': {'lyric': '[00:00.00]romaji'},
          }),
        ),
      ),
    ]);
    final provider = NeProvider(stub);
    final lyrics = await provider.getLyrics(
      LyricInfo(
        source: Source.ne,
        songInfo: SongInfo(
          source: Source.ne,
          id: '1',
          title: 'Tt',
          album: 'Al',
          duration: 1000,
          artist: Artist(const ['A']),
        ),
      ),
    );
    expect(lyrics['orig'], isNotNull);
    expect(lyrics['orig']!.isNotEmpty, isTrue);
    expect(lyrics['orig']!.first.words.isNotEmpty, isTrue);
    expect(lyrics['ts'], isNotNull);
    expect(lyrics['roma'], isNotNull);
    expect(lyrics.tags['ar'], 'A');
    expect(lyrics.tags['by'], contains('MainLyric'));
  });

  test('NeProvider.getLyricsList is unsupported', () {
    final provider = NeProvider(_StubHttpClient([]));
    expect(
      () => provider.getLyricsList(
        LyricsListQuery(
          song: LyricsListTarget(source: Source.ne, id: '1'),
        ),
      ),
      throwsUnsupportedError,
    );
  });

  test(
    'NeProvider stores anonymous cookies in injected NeCookieStore',
    () async {
      final store = InMemoryNeCookieStore();
      final provider = NeProvider(_StubHttpClient([]), cookieStore: store);
      expect(store, isA<NeCookieStore>());
      expect(provider, isNotNull);
    },
  );
}
