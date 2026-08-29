// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Kugou API request signing and helpers.
//
// The signature rule (from `LDDC\core\api\lyrics\kg.py` lines 148-155):
//   `md5(key + "k=v" sorted + body + key)`
// where `v` is JSON-stringified when it's a Map (else coerced to a string)
// and `body` is the raw POST body string (empty for GET).

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

/// Kugou signature key (constant published with the reverse-engineered app).
const String kugouSignatureKey = 'LnT6xpN3khm36zse0QzvmgTZ3waWdRSA';

/// Computes the Kugou `signature` for a request.
///
/// [params] contains both the canonical query params and the platform-common
/// defaults (appid, mid, dfid, etc.). [body] is the POST body string if any.
/// Returns the lowercase hex MD5 digest.
String kugouSignature(Map<String, Object?> params, {String body = ''}) {
  final sorted = params.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  final buffer = StringBuffer(kugouSignatureKey);
  for (final entry in sorted) {
    buffer.write(entry.key);
    buffer.write('=');
    final v = entry.value;
    if (v is Map || v is List) {
      buffer.write(jsonEncode(v));
    } else if (v == null) {
      buffer.write('');
    } else {
      buffer.write(v.toString());
    }
  }
  buffer.write(body);
  buffer.write(kugouSignatureKey);
  return crypto.md5.convert(utf8.encode(buffer.toString())).toString();
}

/// Returns the headers Kugou expects on every request. The `mid` and the
/// timestamps are millisecond-resolution integers encoded as `String`s.
Map<String, String> kugouHeaders(String module, int nowMs) {
  final mid = crypto.md5
      .convert(utf8.encode('${kugouSignatureKey}_$nowMs'))
      .toString();
  return <String, String>{
    'User-Agent': 'Android14-1070-11070-201-0-$module-wifi',
    'Connection': 'Keep-Alive',
    'Accept-Encoding': 'gzip,deflate',
    'KG-Rec': '1',
    'KG-RC': '1',
    'KG-CLIENTTIMEMS': nowMs.toString(),
    'mid': mid,
  };
}

Uint8List emptyBody() => Uint8List(0);
