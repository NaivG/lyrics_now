// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// AES-128-ECB with PKCS#7 padding — a thin wrapper around pointycastle's
// ECB block cipher, used by the NetEase EAPI client (NetEase's pyaes style),
// the cache-key helper, and the QQ cloud response decryptor.
//
// Source: LDDC's `LDDC\core\decryptor\eapi.py`.

import 'dart:typed_data';

import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/ecb.dart';

const _blockSize = 16;
const int _aesKeySize = 16; // AES-128

Uint8List pkcs7Pad(List<int> bytes, [int blockSize = _blockSize]) {
  final padLen = blockSize - (bytes.length % blockSize);
  final pad = List<int>.filled(padLen, padLen);
  return Uint8List.fromList([...bytes, ...pad]);
}

Uint8List pkcs7Unpad(List<int> bytes, [int blockSize = _blockSize]) {
  if (bytes.isEmpty) return Uint8List(0);
  final last = bytes.last;
  if (last <= 0 || last > blockSize || last > bytes.length) {
    return Uint8List.fromList(bytes);
  }
  for (var i = bytes.length - last; i < bytes.length; i++) {
    if (bytes[i] != last) {
      return Uint8List.fromList(bytes);
    }
  }
  return Uint8List.fromList(bytes.sublist(0, bytes.length - last));
}

Uint8List aesEcbEncrypt(List<int> input, Uint8List key) {
  assert(
    key.length == _aesKeySize,
    'AES-128 requires a 16-byte key (got ${key.length})',
  );
  final cipher = ECBBlockCipher(AESEngine())..init(true, KeyParameter(key));
  return _process(cipher, pkcs7Pad(input));
}

Uint8List aesEcbDecrypt(List<int> input, Uint8List key) {
  assert(
    key.length == _aesKeySize,
    'AES-128 requires a 16-byte key (got ${key.length})',
  );
  final cipher = ECBBlockCipher(AESEngine())..init(false, KeyParameter(key));
  return pkcs7Unpad(_process(cipher, input));
}

String hexUpper(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();

String hexLower(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _process(ECBBlockCipher cipher, List<int> input) {
  var offset = 0;
  if (input.isEmpty || input.length % _blockSize != 0) {
    throw ArgumentError(
      'AES ciphertext length must be a multiple of $_blockSize '
      '(got ${input.length})',
    );
  }
  final buffer = Uint8List(input.length);
  while (offset < input.length) {
    final chunk = input.sublist(offset, offset + _blockSize);
    cipher.processBlock(Uint8List.fromList(chunk), 0, buffer, offset);
    offset += _blockSize;
  }
  return buffer;
}
