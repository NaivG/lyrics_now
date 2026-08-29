// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Base exceptions for the lyrics_now library.
//
// Mirrors the hierarchy used by the upstream Python LDDC project so that
// callers get a stable, predictable set of recoverable failure modes.

/// Root of the exception hierarchy thrown by this library.
class LyricsException implements Exception {
  const LyricsException(this.message, {this.cause});

  /// Human-readable description of what went wrong.
  final String message;

  /// Optional underlying cause (typically another [Exception] or [Error]).
  final Object? cause;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType: $message');
    if (cause != null) {
      buffer.write('\nCaused by: $cause');
    }
    return buffer.toString();
  }
}

/// Failure occurred while talking to an upstream provider over HTTP.
class LyricsNetworkException extends LyricsException {
  LyricsNetworkException(super.message, {super.cause, this.uri});

  final Uri? uri;

  @override
  String toString() {
    final base = super.toString();
    if (uri == null) return base;
    return '$base (uri=$uri)';
  }
}

/// Provider returned an HTTP error response (non-2xx).
class LyricsHttpStatusException extends LyricsNetworkException {
  LyricsHttpStatusException({
    required this.statusCode,
    required String body,
    Uri? uri,
  }) : _body = body,
       super(
         'HTTP $statusCode: ${body.isEmpty ? '<empty body>' : body}',
         uri: uri,
       );

  final int statusCode;
  final String _body;

  /// Raw response payload, useful for diagnostics.
  String get body => _body;
}

/// Network call failed before receiving a response.
class LyricsRequestFailedException extends LyricsNetworkException {
  LyricsRequestFailedException(super.message, {super.cause, super.uri});
}

/// Provider timed out while waiting for a response.
class LyricsTimeoutException extends LyricsNetworkException {
  LyricsTimeoutException({Uri? uri, this.timeout, Object? cause})
    : super('Request timed out', uri: uri, cause: cause);

  final Duration? timeout;
}

/// Provider could not be reached or returned unusable data.
class LyricsParseException extends LyricsException {
  LyricsParseException(super.message, {this.input, super.cause});

  /// Snippet of the offending input (truncated by the caller).
  final String? input;
}

/// Provider returned no lyrics for the requested song.
class LyricsNotFoundException extends LyricsException {
  const LyricsNotFoundException(super.message);
}

/// Provider rejected the request because of authentication or signature failure.
class LyricsAuthException extends LyricsException {
  const LyricsAuthException(super.message);
}

/// Provider rejected the request because it was rate-limited (HTTP 429).
class LyricsRateLimitedException extends LyricsNetworkException {
  LyricsRateLimitedException({Uri? uri, this.retryAfter, String body = ''})
    : super('Rate limited: ${body.isEmpty ? '<empty body>' : body}', uri: uri);

  /// Hint from the server via `Retry-After` if present.
  final Duration? retryAfter;
}

/// Signing request failed (e.g. malformed signature inputs).
class LyricsSignError extends LyricsException {
  LyricsSignError(super.message, {super.cause});
}

/// Decrypting lyrics content failed.
class LyricsDecryptError extends LyricsException {
  LyricsDecryptError(super.message, {this.format, super.cause});

  /// Format of the encrypted blob (e.g. `qrc`, `krc`, `yrc`).
  final String? format;
}
