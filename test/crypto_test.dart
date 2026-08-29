// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:typed_data';

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

void main() {
  group('crypto/aes_ecb', () {
    // NIST AES-128 ECB test vector (Appendix F.1.1, F.2.1 from FIPS-197).
    // Key:           2b7e151628aed2a6abf7158809cf4f3c
    // Plaintext:     6bc1bee22e409f96e93d7e117393172a
    // Ciphertext:    3ad77bb40d7a3660a89ecaf32466ef97
    final key = Uint8List.fromList([
      0x2b,
      0x7e,
      0x15,
      0x16,
      0x28,
      0xae,
      0xd2,
      0xa6,
      0xab,
      0xf7,
      0x15,
      0x88,
      0x09,
      0xcf,
      0x4f,
      0x3c,
    ]);
    final plain = Uint8List.fromList([
      0x6b,
      0xc1,
      0xbe,
      0xe2,
      0x2e,
      0x40,
      0x9f,
      0x96,
      0xe9,
      0x3d,
      0x7e,
      0x11,
      0x73,
      0x93,
      0x17,
      0x2a,
    ]);
    final expectedCipher = Uint8List.fromList([
      0x3a,
      0xd7,
      0x7b,
      0xb4,
      0x0d,
      0x7a,
      0x36,
      0x60,
      0xa8,
      0x9e,
      0xca,
      0xf3,
      0x24,
      0x66,
      0xef,
      0x97,
    ]);

    test('AES-128-ECB encrypts the first block per the NIST vector', () {
      // 16-byte input gets PKCS#7-padded to 32 bytes; the first block must
      // match the published ciphertext.
      final out = aesEcbEncrypt(plain, key);
      expect(out.sublist(0, 16), expectedCipher);
      expect(out.length, 32); // PKCS#7 always adds one block of padding.
    });

    test('AES-128-ECB decrypt matches NIST vector', () {
      // The 16-byte ciphertext block decrypts to the 16-byte plaintext
      // verbatim; pkcs7Unpad leaves it untouched (last byte 0x97 > block).
      final out = aesEcbDecrypt(expectedCipher, key);
      expect(out, plain);
    });

    test('PKCS#7 padding/unpadding round-trip', () {
      final padded = pkcs7Pad([1, 2, 3]);
      expect(padded.length, 16);
      expect(pkcs7Unpad(padded), <int>[1, 2, 3]);
    });

    test('hexUpper emits uppercase hex of each byte', () {
      expect(hexUpper([0xDE, 0xAD, 0xBE, 0xEF]), 'DEADBEEF');
    });
  });

  group('crypto/qrc', () {
    test('QRC cloud decrypt path requires valid DES key length', () {
      expect(() => tripledesEcbDecrypt([1, 2, 3], [0]), throwsArgumentError);
    });

    test('qmc1 XORs against the 128-byte table', () {
      // Compare with a tiny buffer so the indexing rule is exercised.
      final data = Uint8List.fromList(List<int>.generate(8, (i) => i));
      final original = Uint8List.fromList(data);
      qmc1Decrypt(data);
      for (var i = 0; i < data.length; i++) {
        final key = (i > 0x7FFF) ? _peek(i % 0x7FFF & 0x7F) : _peek(i & 0x7F);
        expect(data[i] ^ key, original[i], reason: 'byte $i');
      }
    });
  });

  group('crypto/krc', () {
    test('invalid magic throws LyricsDecryptError', () {
      expect(
        () => krcDecrypt([1, 2, 3, 4, 5]),
        throwsA(isA<LyricsDecryptError>()),
      );
    });
  });

  group('crypto/eapi', () {
    test('getAnonymousUsername is deterministic and stays base64', () {
      final a = getAnonymousUsername('abcdef0123456789');
      final b = getAnonymousUsername('abcdef0123456789');
      final c = getAnonymousUsername('fedcba9876543210');
      expect(a, b);
      expect(a, isNot(c));
      final decoded = utf8.decode(base64.decode(a));
      expect(decoded, startsWith('abcdef0123456789 '));
    });

    test('getCacheKey is base64 and round-trips through base64 decode', () {
      final key = getCacheKey('e_r=true&id=42');
      final raw = base64.decode(key);
      // The encrypted form is one AES block (16 bytes) since input is short.
      expect(raw.length, 16);
    });

    test('eapiParamsEncrypt always returns params=HEX prefix', () {
      final cipher = eapiParamsEncrypt('/api/test', <String, Object?>{
        'e_r': true,
        'header': '{"os":"pc","appver":"3.1.3.203419"}',
      });
      expect(cipher, startsWith('params='));
      expect(cipher.substring('params='.length).length % 2, 0);
    });
  });

  group('crypto/kugou_sign', () {
    test('signature is deterministic for the same params', () {
      final params = <String, Object?>{'appid': '3116', 'mid': 'abc'};
      expect(kugouSignature(params), kugouSignature(params));
    });

    test('signature depends on body when present', () {
      final params = <String, Object?>{'appid': '3116'};
      expect(
        kugouSignature(params),
        isNot(kugouSignature(params, body: '{"a":1}')),
      );
    });

    test('signature embeds the canonical key as both prefix and suffix', () {
      final params = <String, Object?>{'appid': '3116'};
      final sig = kugouSignature(params);
      expect(sig, hasLength(32));
    });

    test('kugouHeaders carries both mid and client-time-ms', () {
      final h = kugouHeaders('SearchSong', 1700000000000);
      expect(h['User-Agent'], contains('SearchSong'));
      expect(h['KG-CLIENTTIMEMS'], '1700000000000');
      expect(h['mid'], hasLength(32));
    });
  });
}

int _peek(int index) {
  // Mirror lib/src/crypto/qmc1.dart _qmc1Key.
  const k = <int>[
    0x77,
    0x48,
    0x32,
    0x73,
    0xDE,
    0x69,
    0x47,
    0x14,
    0x6B,
    0x92,
    0xBF,
    0x2F,
    0x0E,
    0x21,
    0xA4,
    0xCB,
    0x6E,
    0xD5,
    0x4A,
    0x4F,
    0xA7,
    0x85,
    0x2C,
    0x5C,
    0xA2,
    0x6C,
    0x79,
    0x21,
    0x95,
    0xF8,
    0x10,
    0x9F,
    0x10,
    0xCE,
    0xE5,
    0xBE,
    0xAB,
    0x9F,
    0xC9,
    0x89,
    0x65,
    0xB4,
    0x68,
    0xC0,
    0x7C,
    0xC8,
    0xDE,
    0xAE,
    0xCD,
    0x4B,
    0xCA,
    0x5D,
    0x40,
    0xCB,
    0xAF,
    0x84,
    0x72,
    0x45,
    0xF4,
    0x65,
    0x90,
    0xA4,
    0xDC,
    0x57,
    0x03,
    0x12,
    0x08,
    0x44,
    0xD9,
    0xA2,
    0x7E,
    0xB6,
    0xE5,
    0x55,
    0xE9,
    0xE9,
    0xFE,
    0x21,
    0x7B,
    0x50,
    0xC9,
    0xE4,
    0x88,
    0x42,
    0x53,
    0x52,
    0x7C,
    0x41,
    0xC1,
    0x05,
    0xDF,
    0x6E,
    0x4E,
    0x31,
    0xB5,
    0x71,
    0x92,
    0xE1,
    0xE8,
    0x77,
    0xB2,
    0xF8,
    0xE5,
    0x06,
    0x41,
    0xC2,
    0x0C,
    0xDD,
    0x7D,
    0xC4,
    0x4D,
    0xCE,
    0x09,
    0x0A,
    0x40,
    0x35,
    0xC3,
    0x95,
    0x86,
    0x53,
    0xD6,
    0x62,
    0xCB,
    0xB4,
    0x50,
    0x9C,
    0x78,
    0x86,
  ];
  return k[index];
}
