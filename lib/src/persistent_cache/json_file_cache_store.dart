// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';
import 'dart:io';

import 'store.dart';

class JsonFileCacheStore implements CacheStore {
  JsonFileCacheStore({required String directory, this.shards = 16})
    : _dir = Directory(directory);

  final Directory _dir;
  final int shards;

  @override
  Future<String?> read(String key) async {
    await _ensureDir();
    final store = await _loadShard(_shardForKey(key));
    final raw = store[key];
    final entry = raw is Map<String, Object?> ? raw : null;
    if (entry == null) return null;
    if (_isExpired(entry)) {
      store.remove(key);
      await _saveShard(_shardForKey(key), store);
      return null;
    }
    return entry['v'] as String?;
  }

  @override
  Future<void> write(String key, String value, Duration ttl) async {
    await _ensureDir();
    final shard = _shardForKey(key);
    final store = await _loadShard(shard);
    store[key] = <String, Object?>{
      'v': value,
      'e': DateTime.now().millisecondsSinceEpoch + ttl.inMilliseconds,
    };
    await _saveShard(shard, store);
  }

  @override
  Future<void> delete(String key) async {
    await _ensureDir();
    final store = await _loadShard(_shardForKey(key));
    if (store.remove(key) != null) {
      await _saveShard(_shardForKey(key), store);
    }
  }

  @override
  Future<void> clear() async {
    if (!await _dir.exists()) return;
    for (var i = 0; i < shards; i++) {
      final file = File.fromUri(_dir.uri.resolve('cache_$i.json'));
      if (await file.exists()) await file.delete();
    }
  }

  @override
  Future<void> gc() async {
    if (!await _dir.exists()) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (var i = 0; i < shards; i++) {
      final store = await _loadShard(i);
      final before = store.length;
      store.removeWhere((_, v) {
        if (v is! Map<String, Object?>) return true;
        return _isExpiredEntry(v, now);
      });
      if (store.length < before) await _saveShard(i, store);
    }
  }

  int _shardForKey(String key) => key.hashCode.abs() % shards;

  Future<void> _ensureDir() async {
    if (!await _dir.exists()) await _dir.create(recursive: true);
  }

  Future<Map<String, Object?>> _loadShard(int shard) async {
    final file = _shardFile(shard);
    if (!await file.exists()) return <String, Object?>{};
    try {
      final content = await file.readAsString();
      return (json.decode(content) as Map<String, Object?>)
          .cast<String, Object?>();
    } on Object {
      return <String, Object?>{};
    }
  }

  Future<void> _saveShard(int shard, Map<String, Object?> data) async {
    final file = _shardFile(shard);
    await file.writeAsString(json.encode(data));
  }

  File _shardFile(int shard) =>
      File.fromUri(_dir.uri.resolve('cache_$shard.json'));

  static bool _isExpired(Map<String, Object?> entry) {
    final e = entry['e'];
    if (e == null) return true;
    return (e as num).toInt() < DateTime.now().millisecondsSinceEpoch;
  }

  static bool _isExpiredEntry(Map<String, Object?> entry, int nowMs) {
    final e = entry['e'];
    if (e == null) return true;
    return (e as num).toInt() < nowMs;
  }
}
