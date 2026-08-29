// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Ordered, unique list of artist names. Mirrors the upstream `Artist` tuple.

/// Ordered set of artist names. Preserves first-occurrence ordering and removes
/// duplicates. Canonical equality treats the same set of artists as equal,
/// regardless of order, so that `SongInfo` equality is well-defined when the
/// same artists appear in different orders.
class Artist {
  /// Returns an empty artist list.
  const Artist.empty() : _names = const <String>[];

  /// Build an artist from a single string, an iterable, an existing artist,
  /// or nothing (returns an empty artist).
  factory Artist([Object? value]) {
    if (value == null) return const Artist.empty();
    if (value is Artist) return value;
    if (value is String) {
      return value.isEmpty
          ? const Artist.empty()
          : Artist._fromList(<String>[value]);
    }
    if (value is Iterable) {
      final seen = <String>{};
      final ordered = <String>[];
      for (final entry in value) {
        final name = entry.toString();
        if (name.isEmpty) continue;
        if (seen.add(name)) ordered.add(name);
      }
      return Artist._fromList(List.unmodifiable(ordered));
    }
    throw ArgumentError.value(
      value,
      'value',
      'must be String, Iterable<String>, Artist, or null',
    );
  }

  const Artist._fromList(List<String> values) : _names = values;

  /// Names in their original (first-seen) order, with duplicates removed.
  final List<String> _names;

  /// Returns an immutable view of the underlying names.
  List<String> get names => List.unmodifiable(_names);

  /// Number of distinct artists.
  int get length => _names.length;

  /// Whether the list contains no artists.
  bool get isEmpty => _names.isEmpty;

  /// Whether the list contains at least one artist.
  bool get isNotEmpty => _names.isNotEmpty;

  /// Joined representation, for example `"Jay Chou / Vincent Fang"`.
  String str({String separator = '/'}) {
    if (_names.isEmpty) return '';
    return _names.join(separator);
  }

  @override
  String toString() => str();

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! Artist || length != other.length) return false;
    final mine = [..._names]..sort();
    final their = [...other._names]..sort();
    for (var i = 0; i < mine.length; i++) {
      if (mine[i] != their[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    final sorted = [..._names]..sort();
    var hash = 0;
    for (final name in sorted) {
      hash = 0x1fffffff & (hash + name.hashCode);
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
    hash ^= hash >> 11;
    return (0x1fffffff & (hash + ((0x00003fff & hash) << 15))) | 0;
  }
}
