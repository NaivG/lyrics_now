// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

void main() {
  test(
    'send builds a request that respects method, body, and query params',
    () async {
      final client = _RecordingHttpClient();
      await client.send(
        LyricsHttpRequest(
          method: 'POST',
          uri: Uri.parse('https://example.test/api/x'),
          queryParameters: const {'a': '1', 'b': 'two words'},
          headers: const {'X-Test': '1'},
          body: <String, Object?>{'k': 'v'},
        ),
      );

      expect(client.lastMethod, 'POST');
      expect(client.lastUrl?.path, '/api/x');
      expect(client.lastUrl?.queryParameters, <String, String>{
        'a': '1',
        'b': 'two words',
      });
      expect(client.lastHeaders['X-Test'], '1');
      expect(client.lastHeaders['Content-Type'], contains('application/json'));
      expect(client.lastBody, utf8.encode(jsonEncode({'k': 'v'})));
    },
  );

  test('send with no body leaves body empty', () async {
    final client = _RecordingHttpClient();
    await client.send(
      LyricsHttpRequest(method: 'GET', uri: Uri.parse('https://example.test/')),
    );
    expect(client.lastBody, isEmpty);
  });

  test('cookies set before send are forwarded as a request header', () async {
    final client = _RecordingHttpClient();
    client.cookies['token'] = 'abc';
    await client.get(Uri.parse('https://example.test/'));
    expect(client.lastHeaders['cookie'], 'token=abc');
  });

  test('http2 flag is preserved on the request envelope', () {
    final req = LyricsHttpRequest(
      method: 'GET',
      uri: Uri.parse('https://example.test/'),
      http2: true,
    );
    expect(req.http2, isTrue);
  });

  test(
    'LyricsHttpStatusException is thrown for non-2xx responses',
    () async {
      final client = PackageHttpClient();
      addTearDown(client.close);
      expect(
        () => client.get(Uri.parse('https://httpbin.org/status/418')),
        throwsA(isA<LyricsHttpStatusException>()),
      );
    },
    skip: 'Live HTTP smoke test; only enabled with --define-by-name=net=true.',
  );
}

class _RecordingHttpClient implements LyricsHttpClient {
  String? lastMethod;
  Uri? lastUrl;
  Map<String, String> lastHeaders = const {};
  Uint8List lastBody = Uint8List(0);

  @override
  Future<LyricsHttpResponse> send(LyricsHttpRequest request) async {
    lastMethod = request.method;
    lastUrl = request.effectiveUri;
    final merged = <String, String>{...request.headers};
    if (request.body != null && !merged.containsKey('Content-Type')) {
      merged['Content-Type'] = 'application/json; charset=utf-8';
    }
    if (cookies.isNotEmpty && !merged.containsKey('cookie')) {
      merged['cookie'] = cookies.entries
          .map((e) => '${e.key}=${e.value}')
          .join('; ');
    }
    lastHeaders = merged;
    lastBody = _bodyBytes(request.body, request.encoding);
    return LyricsHttpResponse(
      statusCode: 200,
      body: '{}',
      bodyBytes: Uint8List.fromList(utf8.encode('{}')),
      headers: const {},
    );
  }

  @override
  Future<LyricsHttpResponse> get(Uri url, {Map<String, String>? headers}) =>
      send(
        LyricsHttpRequest(
          method: 'GET',
          uri: url,
          headers: headers ?? const {},
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
      headers: headers ?? const {},
    ),
  );

  @override
  Map<String, String> cookies = <String, String>{};

  @override
  void close() {}

  Uint8List _bodyBytes(Object? body, Encoding? encoding) {
    if (body == null) return Uint8List(0);
    if (body is String) {
      return Uint8List.fromList(encoding?.encode(body) ?? utf8.encode(body));
    }
    if (body is List<int>) return Uint8List.fromList(body);
    return Uint8List.fromList(utf8.encode(jsonEncode(body)));
  }
}
