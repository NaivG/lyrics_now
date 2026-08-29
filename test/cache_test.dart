// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

void main() {
  group('cache/ne_cookie_store', () {
    test('InMemoryNeCookieStore round-trips a record', () async {
      final store = InMemoryNeCookieStore();
      const record = NeCookieRecord(
        userId: 99,
        cookies: {'NMTID': 'abc', 'MUSIC_A': 'def'},
        expireAt: 9999999999,
      );
      await store.write(record);
      final read = await store.read();
      expect(read, isNotNull);
      expect(read!.userId, 99);
      expect(read.cookies['NMTID'], 'abc');
      expect(read.cookies['MUSIC_A'], 'def');
      expect(read.isExpired, isFalse);
    });

    test('InMemoryNeCookieStore exposes expiry semantics', () async {
      final store = InMemoryNeCookieStore(ttl: const Duration(milliseconds: 1));
      await store.write(
        NeCookieRecord(
          userId: 1,
          cookies: const {'A': '1'},
          expireAt: 9999999999,
        ),
      );
      expect(await store.read(), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(await store.read(), isNull);
    });

    test('clear() drops the stored record', () async {
      final store = InMemoryNeCookieStore();
      await store.write(
        const NeCookieRecord(
          userId: 1,
          cookies: {'A': '1'},
          expireAt: 9999999999,
        ),
      );
      await store.clear();
      expect(await store.read(), isNull);
    });

    test('NeCookieRecord.isExpired respects expireAt', () {
      final expired = NeCookieRecord(
        userId: 1,
        cookies: const {},
        expireAt: 0, // 1970
      );
      final live = NeCookieRecord(
        userId: 1,
        cookies: const {},
        expireAt: 9999999999,
      );
      expect(expired.isExpired, isTrue);
      expect(live.isExpired, isFalse);
    });
  });
}
