// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// 3DES (DES-EDE-EDE) ECB single-block decryption for QQ Music cloud QRC.
//
// LDDC's hand-rolled `LDDC\core\decryptor\tripledes.py` is functionally
// identical to pointycastle's `DESedeEngine`, which we reuse here. The
// processing loop walks the buffer 8 bytes at a time (ECB).
//
// Source: `LDDC\core\decryptor\__init__.py:qrc_decrypt(QrcType.CLOUD)` and
// `LDDC\core\decryptor\tripledes.py:tripledes_crypt`.

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/desede_engine.dart';

const int _desBlockSize = 8;

/// Default QQ cloud QRC key (24 bytes, DES-EDE-EDE).
final List<int> qrcCloudKey = utf8.encode(r'!@#)(*$%123ZXC!@!@#)(NHL');

/// Decrypts a buffer encrypted under 3DES-EDE-EDE-ECB using [key].
///
/// [key] must be exactly 16 or 24 bytes (pointycastle's DESede limitation;
/// 16 bytes collapses to 2-key 3DES).
Uint8List tripledesEcbDecrypt(List<int> input, List<int> key) {
  if (key.length != 24 && key.length != 16) {
    throw ArgumentError('3DES key must be 16 or 24 bytes (got ${key.length})');
  }
  if (input.length % _desBlockSize != 0) {
    throw ArgumentError(
      '3DES-ECB payload length must be a multiple of 8 bytes (got ${input.length})',
    );
  }

  final cipher = DESedeEngine()
    ..init(false, KeyParameter(Uint8List.fromList(key)));
  final buffer = Uint8List(input.length);
  for (var offset = 0; offset < input.length; offset += _desBlockSize) {
    cipher.processBlock(
      Uint8List.fromList(input.sublist(offset, offset + _desBlockSize)),
      0,
      buffer,
      offset,
    );
  }
  return buffer;
}
