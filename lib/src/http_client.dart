// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Injectable HTTP client abstraction. Provider implementations talk to this
// interface instead of `package:http` directly so that tests can substitute a
// deterministic transport.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'exceptions.dart';

/// Read-only HTTP response exposed to provider implementations.
class LyricsHttpResponse {
  const LyricsHttpResponse({
    required this.statusCode,
    required this.body,
    required this.bodyBytes,
    required this.headers,
  });

  final int statusCode;
  final String body;
  final Uint8List bodyBytes;
  final Map<String, String> headers;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

/// A single HTTP request, independent of transport details.
///
/// Providers may populate any subset of [headers]/[body]/[queryParameters].
/// Setting [http2] to `true` hints that the underlying transport should use
/// HTTP/2 when available; [PackageHttpClient] currently treats this as a
/// forward-compatible flag and falls back to HTTP/1.1. The QQ Music provider
/// relies on the header order left untouched by the implementation.
class LyricsHttpRequest {
  LyricsHttpRequest({
    required this.method,
    required this.uri,
    this.body,
    this.encoding,
    this.headers = const <String, String>{},
    this.queryParameters = const <String, String>{},
    this.http2 = false,
  });

  final String method;
  final Uri uri;
  final Object? body;
  final Encoding? encoding;
  final Map<String, String> headers;
  final Map<String, String> queryParameters;
  final bool http2;

  /// Returns the effective URI after [queryParameters] are applied.
  Uri get effectiveUri => queryParameters.isEmpty
      ? uri
      : uri.replace(queryParameters: queryParameters);
}

/// Minimal HTTP surface required by provider implementations.
///
/// Providers never reach for [package:http] directly — instead they call into
/// this interface and benefit from the cookie jar, retry policy, and
/// instrumentation that the [LyricsHttpClient] implementation provides.
abstract interface class LyricsHttpClient {
  Future<LyricsHttpResponse> get(Uri url, {Map<String, String>? headers});

  Future<LyricsHttpResponse> post(
    Uri url, {
    Object? body,
    Map<String, String>? headers,
    Encoding? encoding,
  });

  /// Lowest-level entry point. Useful when a provider needs to specify the
  /// HTTP method, body, headers, and a query-string in one place (e.g. when
  /// re-signing a request that already has a canonical URL).
  Future<LyricsHttpResponse> send(LyricsHttpRequest request);

  /// Shared cookie jar. Providers that need session cookies (e.g. NetEase
  /// Cloud Music) populate this.
  Map<String, String> get cookies;
  set cookies(Map<String, String> value);

  /// Release any underlying resources.
  void close();
}

/// Default implementation backed by `package:http`.
///
/// Create one instance per `LyricFinder` and share it across providers.
///
/// 内建按主机的限流退避：任一请求收到 HTTP 429 后，该主机在退避窗口内的
/// 后续请求立即以 [LyricsRateLimitedException] 快速失败（携带剩余窗口），
/// 不再发起新连接。调用方（[LyricFinder] 的逐 provider 兜底循环）据此
/// 跳过被限流的源，避免在限流期间继续撞击加重封禁。
class PackageHttpClient implements LyricsHttpClient {
  PackageHttpClient({http.Client? inner, Duration? timeout})
    : _client = inner ?? http.Client(),
      _timeout = timeout ?? const Duration(seconds: 30);

  final http.Client _client;
  final Duration _timeout;

  /// 服务器未提供 `Retry-After` 时的默认退避窗口。
  static const Duration _defaultRateLimitBackoff = Duration(seconds: 30);

  /// 退避窗口上限，防止异常巨大的 `Retry-After` 长期锁死一个源。
  static const Duration _maxRateLimitBackoff = Duration(minutes: 10);

  /// host → 退避截止时间。
  final Map<String, DateTime> _rateLimitedUntil = {};

  @override
  Map<String, String> cookies = <String, String>{};

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
    final merged = _mergeHeaders(request.headers);
    final uri = request.effectiveUri;
    _throwIfHostInBackoff(uri);
    try {
      final streamed = await _client
          .send(
            http.Request(request.method, uri)
              ..headers.addAll(merged)
              ..bodyBytes = _encodeBody(request),
          )
          .timeout(_timeout);
      final response = await http.Response.fromStream(streamed);
      _absorbCookies(response.headers['set-cookie']);
      return _wrap(response, uri);
    } on TimeoutException catch (e) {
      throw LyricsTimeoutException(uri: uri, timeout: _timeout, cause: e);
    } on LyricsException {
      // _wrap 抛出的类型化状态异常（429 限流 / 非 2xx）原样上抛，
      // 不能被下面的兜底包装成 LyricsRequestFailedException——
      // 调用方需要按类型区分限流与一般失败。
      rethrow;
    } on Object catch (e) {
      throw LyricsRequestFailedException(
        '${request.method} $uri failed: $e',
        cause: e,
        uri: uri,
      );
    }
  }

  Uint8List _encodeBody(LyricsHttpRequest request) {
    final body = request.body;
    if (body == null) return Uint8List(0);
    if (body is Uint8List) return body;
    if (body is List<int>) return Uint8List.fromList(body);
    if (body is String) {
      final encoded = request.encoding?.encode(body) ?? utf8.encode(body);
      return Uint8List.fromList(encoded);
    }
    final json = jsonEncode(body);
    final encoded = request.encoding?.encode(json) ?? utf8.encode(json);
    return Uint8List.fromList(encoded);
  }

  @override
  void close() => _client.close();

  Map<String, String> _mergeHeaders(Map<String, String> headers) {
    if (cookies.isEmpty && headers.isEmpty) {
      return const <String, String>{};
    }
    final merged = <String, String>{
      ...headers,
      if (cookies.isNotEmpty) 'cookie': _cookieHeader(),
    };
    return merged;
  }

  String _cookieHeader() =>
      cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');

  void _absorbCookies(String? setCookieHeader) {
    if (setCookieHeader == null) return;
    for (final piece in setCookieHeader.split(',')) {
      final pair = piece.split(';').first.trim();
      final equals = pair.indexOf('=');
      if (equals <= 0) continue;
      final name = pair.substring(0, equals).trim();
      final value = pair.substring(equals + 1).trim();
      if (name.isNotEmpty) {
        cookies[name] = value;
      }
    }
  }

  String _safeBody(http.Response response) {
    try {
      return response.body;
    } on FormatException {
      try {
        return utf8.decode(response.bodyBytes);
      } on FormatException {
        return latin1.decode(response.bodyBytes);
      }
    }
  }

  LyricsHttpResponse _wrap(http.Response response, Uri url) {
    final status = response.statusCode;
    final bodyText = _safeBody(response);
    if (status == 429) {
      final retryAfter =
          _parseRetryAfter(response.headers['retry-after']) ??
          _defaultRateLimitBackoff;
      final backoff = retryAfter > _maxRateLimitBackoff
          ? _maxRateLimitBackoff
          : retryAfter;
      _rateLimitedUntil[url.host] = DateTime.now().add(backoff);
      throw LyricsRateLimitedException(
        uri: url,
        retryAfter: backoff,
        body: bodyText,
      );
    }
    if (status < 200 || status >= 300) {
      throw LyricsHttpStatusException(
        statusCode: status,
        body: bodyText,
        uri: url,
      );
    }
    return LyricsHttpResponse(
      statusCode: status,
      body: bodyText,
      bodyBytes: response.bodyBytes,
      headers: response.headers,
    );
  }

  /// 主机仍在限流退避窗口内时快速失败，避免继续撞击。
  void _throwIfHostInBackoff(Uri uri) {
    final blockedUntil = _rateLimitedUntil[uri.host];
    if (blockedUntil == null) return;
    final remaining = blockedUntil.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _rateLimitedUntil.remove(uri.host);
      return;
    }
    throw LyricsRateLimitedException(
      uri: uri,
      retryAfter: remaining,
      body: '<host in rate-limit backoff>',
    );
  }

  /// 解析 `Retry-After` 头，仅支持 delta-seconds（各歌词源均用此格式）。
  /// 解析失败返回 null，由调用方使用默认退避。
  Duration? _parseRetryAfter(String? value) {
    if (value == null) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds == null || seconds < 0) return null;
    return Duration(seconds: seconds);
  }
}
