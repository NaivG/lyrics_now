// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// NetEase EAPI request signing + response decryption, anonymous-username
// derivation, cache-key helpers.
//
// Source: `LDDC\core\decryptor\eapi.py` and `LDDC\core\api\lyrics\ne.py`.
//
// Layout (mirrors the Python module):
//   - aesEcbEncrypt/Decrypt         (re-exported via aes_ecb.dart)
//   - pkcs7 helpers                 (re-exported via aes_ecb.dart)
//   - hexUpper (binascii.hexlify, upper-case)
//   - eapiParamsEncrypt(path, params)  → "params=HEX"
//   - eapiResponseDecrypt(buffer)
//   - getCacheKey(data)
//   - getAnonimousUsername(deviceId)

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import 'aes_ecb.dart';
import '../exceptions.dart';

/// EAPI request and response key.
final Uint8List _eapiAesKey = Uint8List.fromList(_eapiKeyBytes);

const List<int> _eapiKeyBytes = [
  0x65,
  0x38,
  0x32,
  0x63,
  0x6B,
  0x65,
  0x6E,
  0x68,
  0x38,
  0x64,
  0x69,
  0x63,
  0x68,
  0x65,
  0x6E,
  0x38,
];

/// Cache-key derivation key.
final Uint8List _cacheKeyAes = Uint8List.fromList(_cacheKeyBytes);

const List<int> _cacheKeyBytes = [
  0x29,
  0x28,
  0x31,
  0x33,
  0x64,
  0x61,
  0x71,
  0x50,
  0x40,
  0x73,
  0x73,
  0x77,
  0x30,
  0x72,
  0x64,
  0x7E,
];

/// Device-id XOR key (string used as a repeating key on the raw character
/// code points — note this is NOT the same as byte-wise XOR).
const String _deviceIdXorKey = r'3go8&$8*3*3h0k(2)2';

/// Composes the canonical NetEase EAPI request envelope.
///
/// [path] is the *`/api/...`*-form path (i.e. `/eapi/...` rewritten).
/// [params] must already include the `header` (and optional `e_r`) entries.
String eapiParamsEncrypt(String path, Map<String, Object?> params) {
  final pathBytes = utf8.encode(path);
  final paramBytes = utf8.encode(jsonEncode(params));
  final signBuilder = BytesBuilder()
    ..add(utf8.encode('nobody'))
    ..add(pathBytes)
    ..add(utf8.encode('use'))
    ..add(paramBytes)
    ..add(utf8.encode('md5forencrypt'));
  final sign = crypto.md5.convert(signBuilder.toBytes()).toString();
  final srcBuilder = BytesBuilder()
    ..add(pathBytes)
    ..add(utf8.encode('-36cd479b6b5-'))
    ..add(paramBytes)
    ..add(utf8.encode('-36cd479b6b5-'))
    ..add(utf8.encode(sign));
  final ciphertext = aesEcbEncrypt(srcBuilder.toBytes(), _eapiAesKey);
  return 'params=${hexUpper(ciphertext)}';
}

/// Decrypts an EAPI response body (the body returned by the server is the
/// raw AES-128-ECB encrypted bytes, NOT hex-encoded).
String eapiResponseDecrypt(List<int> body) {
  try {
    final plain = aesEcbDecrypt(body, _eapiAesKey);
    return utf8.decode(plain, allowMalformed: false);
  } on Object catch (e) {
    throw LyricsDecryptError(
      'EAPI response decrypt failed',
      format: 'eapi',
      cause: e,
    );
  }
}

/// Returns the base64-encoded AES-encrypted cache key. Sent as the URL query
/// parameter `cache_key` AND embedded in the `params` body for cacheable
/// endpoints (album detail, playlist detail).
String getCacheKey(String data) {
  final bytes = utf8.encode(data);
  final cipher = aesEcbEncrypt(bytes, _cacheKeyAes);
  return base64.encode(cipher);
}

/// Derives the anonymous-login username from a NetEase device id.
///
/// Each character code point of [deviceId] is XORed against
/// `_deviceIdXorKey[i % keyLength]` (note: code points, NOT bytes — matches
/// Python's `chr(ord(c) ^ ord(...))`). The result is then base64-encoded
/// after concatenating with a base64-encoded MD5 of the XORed characters.
String getAnonymousUsername(String deviceId) {
  final codeUnits = deviceId.codeUnits;
  final buffer = StringBuffer();
  for (var i = 0; i < codeUnits.length; i++) {
    buffer.writeCharCode(
      codeUnits[i] ^ _deviceIdXorKey.codeUnitAt(i % _deviceIdXorKey.length),
    );
  }
  final xored = buffer.toString();
  final md5Bytes = crypto.md5.convert(utf8.encode(xored)).bytes;
  final inner = base64.encode(md5Bytes);
  return base64.encode(utf8.encode('$deviceId $inner'));
}
