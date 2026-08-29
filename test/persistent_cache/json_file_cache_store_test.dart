import 'dart:io';

import 'package:lyrics_now/src/persistent_cache/json_file_cache_store.dart';
import 'package:test/test.dart';

void main() {
  late Directory tmpDir;
  late JsonFileCacheStore store;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('cache_test_');
    store = JsonFileCacheStore(directory: tmpDir.path, shards: 4);
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('JsonFileCacheStore', () {
    test('write and read', () async {
      await store.write('k1', 'v1', const Duration(hours: 1));
      final result = await store.read('k1');
      expect(result, 'v1');
    });

    test('read miss', () async {
      final result = await store.read('nonexistent');
      expect(result, isNull);
    });

    test('expired entry returns null', () async {
      await store.write('k1', 'v1', Duration.zero);
      await Future.delayed(const Duration(milliseconds: 1));
      final result = await store.read('k1');
      expect(result, isNull);
    });

    test('delete', () async {
      await store.write('k1', 'v1', const Duration(hours: 1));
      await store.delete('k1');
      final result = await store.read('k1');
      expect(result, isNull);
    });

    test('clear', () async {
      await store.write('k1', 'v1', const Duration(hours: 1));
      await store.write('k2', 'v2', const Duration(hours: 1));
      await store.clear();
      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), isNull);
    });

    test('gc removes expired entries', () async {
      await store.write('k1', 'v1', Duration.zero);
      await store.write('k2', 'v2', const Duration(hours: 1));
      await Future.delayed(const Duration(milliseconds: 1));
      await store.gc();
      expect(await store.read('k1'), isNull);
      expect(await store.read('k2'), 'v2');
    });
  });
}
