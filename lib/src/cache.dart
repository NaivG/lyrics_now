// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Lightweight TTL-keyed caches used by `LyricFinder` and standalone callers.
//
// The cache is intentionally kept simple — the upstream LDDC uses `diskcache`
// which we don't want as a dependency. The point is to shield `getLyricsList`
// from re-issuing the same request inside a single user flow; cache values
// survive until their TTL expires.

import 'dart:collection';

/// A simple in-memory TTL cache keyed by [K] with values of type [V].
class TtlCache<K, V extends Object?> {
  TtlCache({required this.ttl, int capacity = 1024})
    : _capacity = capacity,
      _entries = HashMap<K, _Entry<V>>();

  /// Maximum time a value lives before it is considered stale.
  final Duration ttl;

  final int _capacity;
  final HashMap<K, _Entry<V>> _entries;
  bool _closed = false;

  V? lookup(K key) {
    if (_closed) return null;
    final entry = _entries[key];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.storedAt) > ttl) {
      _entries.remove(key);
      return null;
    }
    return entry.value;
  }

  void store(K key, V value) {
    if (_closed) return;
    if (_entries.length >= _capacity && !_entries.containsKey(key)) {
      // FIFO eviction.
      final oldest = _entries.entries.first;
      _entries.remove(oldest.key);
    }
    _entries[key] = _Entry(value, DateTime.now());
  }

  void invalidate(K key) {
    _entries.remove(key);
  }

  void clear() {
    _entries.clear();
  }

  void close() {
    _closed = true;
    _entries.clear();
  }
}

class _Entry<V> {
  _Entry(this.value, this.storedAt);
  final V value;
  final DateTime storedAt;
}

/// Convenience cache used by `LyricFinder` for deduped search queries.
class TtlSearchCache<V> extends TtlCache<Object, V> {
  // ignore: use_super_parameters
  TtlSearchCache(Duration ttl, {int capacity = 1024})
    : super(ttl: ttl, capacity: capacity);
}

/// Snapshot of a NetEase anonymous-login session.
///
/// Stored in [NeCookieStore] so the [NeProvider] can reuse cookies across
/// process restarts. `userId` is needed for some EAPI requests; `cookies`
/// carries the negotiated `MUSIC_A` / `NMTID` / `__csrf` etc.
class NeCookieRecord {
  const NeCookieRecord({
    required this.userId,
    required this.cookies,
    required this.expireAt,
  });

  /// Numeric NetEase user id returned by the `eapi/register/anonimous` flow.
  final int userId;

  /// Cookie map keyed by name (e.g. `MUSIC_A`, `NMTID`).
  final Map<String, String> cookies;

  /// Unix-second timestamp at which this record should no longer be reused.
  final int expireAt;

  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expireAt;
}

/// Persistence contract for NetEase anonymous-login state.
///
/// The provider calls [read] on first use to recover a valid session, and
/// calls [write] after a fresh login. Plug in [InMemoryNeCookieStore] for
/// transient state (default) or back it with `sqflite`, `hive`, or the local
/// file system for cross-restart persistence.
abstract interface class NeCookieStore {
  /// Returns the most recently stored record (regardless of expiry).
  Future<NeCookieRecord?> read();

  /// Persists [record]. Existing entries with the same key are replaced.
  Future<void> write(NeCookieRecord record);

  /// Discards all persisted records. Used on logout / refresh.
  Future<void> clear();
}

/// Default in-memory [NeCookieStore] backed by [TtlCache]. Survives until
/// the process exits — sufficient for CLI / scripting usage; for long-lived
/// services supply a disk-backed implementation.
class InMemoryNeCookieStore implements NeCookieStore {
  InMemoryNeCookieStore({Duration ttl = const Duration(days: 10)})
    : _cache = _CookieCache(ttl);

  final _CookieCache _cache;

  static const String _singletonKey = '<singleton>';

  @override
  Future<NeCookieRecord?> read() async => _cache.lookup(_singletonKey);

  @override
  Future<void> write(NeCookieRecord record) async {
    _cache.store(_singletonKey, record);
  }

  @override
  Future<void> clear() async => _cache.clear();

  void close() => _cache.close();
}

class _CookieCache extends TtlCache<String, NeCookieRecord> {
  // ignore: use_super_parameters
  _CookieCache(Duration ttl) : super(ttl: ttl, capacity: 1);
}
