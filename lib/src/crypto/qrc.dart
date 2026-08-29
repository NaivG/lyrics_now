// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// QRC decryption: orchestrates QMC1 (local files) or 3DES (cloud) over the
// encrypted blob and then zlib-inflates the result. Returns a UTF-8 decoded
// string containing the QRC XML wrapper (`<Lyric_1 ...>…</Lyric_1>`).
//
// Source: `LDDC\core\decryptor\__init__.py:qrc_decrypt`.
//
// Uses `package:archive`'s pure-Dart `ZLibDecoder` (raw=false, expecting the
// 2-byte zlib header) to avoid pulling `dart:io` into the crypto layer.

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' as archive;

import 'des_ede.dart';
import 'qmc1.dart';
import '../exceptions.dart';

/// Magic header that identifies a local QRC file.
final Uint8List qrcMagicHeader = Uint8List.fromList(<int>[
  0x98,
  0x25,
  0xB0,
  0xAC,
  0xE3,
  0x02,
  0x83,
  0x68,
  0xE8,
  0xFC,
  0x6C,
]);

/// Distinguishes local-file QRC from QQ cloud QRC payloads.
enum QrcType { local, cloud }

String qrcDecrypt(
  List<int> blob, {
  QrcType type = QrcType.cloud,
  List<int>? key,
}) {
  switch (type) {
    case QrcType.local:
      return _qrcDecryptLocal(blob);
    case QrcType.cloud:
      return _qrcDecryptCloud(blob, key ?? qrcCloudKey);
  }
}

String _qrcDecryptLocal(List<int> blob) {
  if (blob.length < qrcMagicHeader.length) {
    throw LyricsDecryptError('QRC payload too short', format: 'qrc-local');
  }
  for (var i = 0; i < qrcMagicHeader.length; i++) {
    if (blob[i] != qrcMagicHeader[i]) {
      throw LyricsDecryptError(
        'QRC magic header mismatch',
        format: 'qrc-local',
      );
    }
  }
  final buffer = Uint8List.fromList(blob.sublist(11));
  qmc1Decrypt(buffer);
  try {
    return utf8.decode(archive.ZLibDecoder().decodeBytes(buffer));
  } on Object catch (e) {
    throw LyricsDecryptError(
      'QRC local zlib inflate failed',
      format: 'qrc-local',
      cause: e,
    );
  }
}

String _qrcDecryptCloud(List<int> blob, List<int> key) {
  final plain = tripledesEcbDecrypt(blob, key);
  try {
    return utf8.decode(archive.ZLibDecoder().decodeBytes(plain));
  } on Object catch (e) {
    throw LyricsDecryptError(
      'QRC cloud zlib inflate failed',
      format: 'qrc-cloud',
      cause: e,
    );
  }
}
