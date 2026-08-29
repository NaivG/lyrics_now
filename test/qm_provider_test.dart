// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:lyrics_now/lyrics_now.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/desede_engine.dart';
import 'package:pointycastle/block/modes/ecb.dart';
import 'package:test/test.dart';

class _StubHttpClient implements LyricsHttpClient {
  _StubHttpClient(this.responses);

  final List<_StubResponse> responses;
  final List<Uri> calls = <Uri>[];
  final List<Object?> bodies = <Object?>[];
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
    bodies.add(request.body);
    if (_cursor >= responses.length) {
      throw StateError('Out of stubs at ${request.effectiveUri}');
    }
    final preset = responses[_cursor++];
    if (preset.statusCode < 200 || preset.statusCode >= 300) {
      throw LyricsHttpStatusException(
        statusCode: preset.statusCode,
        body: preset.body,
        uri: request.effectiveUri,
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
  _StubResponse(this.statusCode, this.body);
  final int statusCode;
  final String body;
}

Map<String, dynamic> _okEnvelope(Map<String, dynamic> data) => {
  'code': 0,
  'request': {'code': 0, 'data': data},
};

void main() {
  test(
    'QmProvider.search dispatches song search via /cgi-bin/musicu.fcg',
    () async {
      final stub = _StubHttpClient([
        _StubResponse(200, jsonEncode(_okEnvelope({'session': {}}))),
        _StubResponse(
          200,
          jsonEncode(
            _okEnvelope({
              'body': {
                'item_song': [
                  {
                    'id': 1,
                    'mid': 'mid1',
                    'title': 'S',
                    'subtitle': '',
                    'singer': [
                      {'name': 'A'},
                    ],
                    'album': {'name': 'Al'},
                    'interval': 200,
                    'language': 0,
                  },
                ],
                'meta': {'sum': 1},
              },
            }),
          ),
        ),
      ]);
      final provider = QmProvider(stub);
      final results = await provider.search(
        const SearchQuery(keyword: 'S', searchType: SearchType.song),
      );
      expect(results, isNotEmpty);
      expect(results[0].title, 'S');
      expect(results[0].mid, 'mid1');
      expect(results[0].duration, 200 * 1000);
      expect(results[0].language, Language.chinese);
      expect(stub.calls.last.path, '/cgi-bin/musicu.fcg');
    },
  );

  test('QmProvider.searchSongList returns album hits', () async {
    final stub = _StubHttpClient([
      _StubResponse(200, jsonEncode(_okEnvelope({'session': {}}))),
      _StubResponse(
        200,
        jsonEncode(
          _okEnvelope({
            'body': {
              'album': {
                'list': [
                  {
                    'albumID': 7,
                    'albumMID': 'mid7',
                    'albumName': 'Album X',
                    'albumPic': 'https://example.test/x.jpg',
                    'song_count': 3,
                    'publicTime': '2024-01-01',
                    'singerName': 'Artist',
                  },
                ],
              },
              'meta': {'sum': 1},
            },
          }),
        ),
      ),
    ]);
    final provider = QmProvider(stub);
    final list = await provider.searchSongList(
      const SearchQuery(keyword: 'Album', searchType: SearchType.album),
    );
    expect(list, isNotNull);
    expect(list![0].type, SongListType.album);
    expect(list[0].id, '7');
    expect(list[0].title, 'Album X');
  });

  test('QmProvider.getSongList album variant parses tracks', () async {
    final stub = _StubHttpClient([
      _StubResponse(200, jsonEncode(_okEnvelope({'session': {}}))),
      _StubResponse(
        200,
        jsonEncode(
          _okEnvelope({
            'songList': [
              {
                'songInfo': {
                  'id': 42,
                  'mid': 'mid42',
                  'title': 'Track',
                  'singer': [
                    {'name': 'Artist'},
                  ],
                  'album': {'name': 'Al'},
                  'interval': 100,
                  'language': 5,
                },
              },
            ],
          }),
        ),
      ),
    ]);
    final provider = QmProvider(stub);
    final list = await provider.getSongList(
      const SongListInfo(
        source: Source.qm,
        type: SongListType.album,
        id: '1',
        title: 't',
        imgUrl: '',
        author: '',
      ),
    );
    expect(list, hasLength(1));
    expect(list[0].title, 'Track');
    expect(list[0].language, Language.english);
  });

  test('QmProvider.getSongList songList (CgiGetDiss) parses tracks', () async {
    final stub = _StubHttpClient([
      _StubResponse(200, jsonEncode(_okEnvelope({'session': {}}))),
      _StubResponse(
        200,
        jsonEncode(
          _okEnvelope({
            'songlist': [
              {
                'id': 7,
                'mid': 'mid7',
                'title': 'T2',
                'singer': [
                  {'name': 'Who'},
                ],
                'album': {'name': 'Al2'},
                'interval': 50,
                'language': 3,
              },
            ],
          }),
        ),
      ),
    ]);
    final provider = QmProvider(stub);
    final list = await provider.getSongList(
      const SongListInfo(
        source: Source.qm,
        type: SongListType.songList,
        id: '1',
        title: 't',
        imgUrl: '',
        author: '',
      ),
    );
    expect(list, hasLength(1));
    expect(list[0].title, 'T2');
  });

  test('QmProvider.getLyrics decrypts hex QRC cloud response', () async {
    final encrypted = _buildSyntheticCloudQrc();
    final stub = _StubHttpClient([
      _StubResponse(200, jsonEncode(_okEnvelope({'session': {}}))),
      _StubResponse(
        200,
        jsonEncode(
          _okEnvelope({
            'lyric': _hex(encrypted),
            'qrc_t': '1700000000000',
            'trans': '',
            'trans_t': '0',
            'roma': '',
            'roma_t': '0',
          }),
        ),
      ),
    ]);
    final provider = QmProvider(stub);
    final lyrics = await provider.getLyrics(
      LyricInfo(
        source: Source.qm,
        songInfo: SongInfo(
          source: Source.qm,
          id: '1',
          title: 'T',
          album: 'Al',
          duration: 1000,
        ),
      ),
    );
    expect(lyrics['orig'], isNotNull);
    expect(lyrics['orig']!.length, greaterThan(0));
  });

  test('QmProvider.getLyricsList is unsupported', () {
    final provider = QmProvider(_StubHttpClient([]));
    expect(
      () => provider.getLyricsList(
        LyricsListQuery(
          song: LyricsListTarget(source: Source.qm, id: '1'),
        ),
      ),
      throwsUnsupportedError,
    );
  });
}

List<int> _buildSyntheticCloudQrc() {
  // Build a synthetic cloud QRC: deflate-encode(QRC XML) → 3DES-ECB-encrypt.
  final xml =
      '<Lyric_1 LyricType="1" LyricContent="'
      '[ti:Title]\n'
      '[0,1000](0,500,0)Hel(500,500,0)lo\n'
      '"/>\n';
  final compressed = ZLibEncoder().encode(utf8.encode(xml)).cast<int>();
  // Pad to 8-byte multiples (deflate output may not be aligned).
  final padded = List<int>.from(compressed);
  while (padded.length % 8 != 0) {
    padded.add(0);
  }
  return _tripledesEcbEncrypt(padded, qrcCloudKey);
}

List<int> _tripledesEcbEncrypt(List<int> input, List<int> key) {
  final cipher = ECBBlockCipher(DESedeEngine())
    ..init(true, KeyParameter(Uint8List.fromList(key)));
  final out = Uint8List(input.length);
  for (var off = 0; off < input.length; off += 8) {
    cipher.processBlock(
      Uint8List.fromList(input.sublist(off, off + 8)),
      0,
      out,
      off,
    );
  }
  return out;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
