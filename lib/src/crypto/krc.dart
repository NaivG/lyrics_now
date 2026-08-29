// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// KRC decryption: skip the 4-byte `krc18` magic, XOR with a 16-byte
// repeating key, then `zlib.decompress`. Returns the inflated text.
//
// Source: `LDDC\core\decryptor\__init__.py:krc_decrypt`.
//
// Uses `package:archive`'s pure-Dart `ZLibDecoder` (raw=false, expecting the
// 2-byte zlib header) to avoid pulling `dart:io` into the crypto layer.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;

import '../exceptions.dart';

/// KRC XOR key (16 bytes, see `LDDC\core\decryptor\__init__.py:KRC_KEY`).
final Uint8List krcKey = Uint8List.fromList(<int>[
  0x40,
  0x47,
  0x61,
  0x77,
  0x5E,
  0x32,
  0x74,
  0x47,
  0x51,
  0x36,
  0x31,
  0x2D,
  0xCE,
  0xD2,
  0x6E,
  0x69,
]);

final Uint8List _krcMagicHeader = Uint8List.fromList(utf8.encode('krc18'));

String krcDecrypt(List<int> blob) {
  if (blob.length < 4) {
    throw LyricsDecryptError('KRC payload too short', format: 'krc');
  }
  for (var i = 0; i < _krcMagicHeader.length; i++) {
    if (blob[i] != _krcMagicHeader[i]) {
      throw LyricsDecryptError(
        'KRC magic header mismatch (expected krc18)',
        format: 'krc',
      );
    }
  }
  final body = Uint8List.fromList(blob.sublist(4));
  for (var i = 0; i < body.length; i++) {
    body[i] ^= krcKey[i % krcKey.length];
  }
  try {
    return utf8.decode(archive.ZLibDecoder().decodeBytes(body));
  } on Object catch (e) {
    throw LyricsDecryptError(
      'KRC zlib inflate failed',
      format: 'krc',
      cause: e,
    );
  }
}
