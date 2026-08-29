// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Heterogeneous, source-aware list returned by provider searches.
//
// Mirrors LDDC's APIResultList: items are interleaved round-robin by
// `Source` order so the UI can show one entry per provider side-by-side.

import 'dart:collection';

import 'info_base.dart';
import 'source.dart';

/// Per-source `(start, end, total)` triple describing which subset of items
/// contributed to the list (0-indexed bounds, inclusive).
typedef SourceRange = ({int start, int end, int total});

/// Iterable list of provider results, optionally annotated with per-source
/// ranges and cache provenance.
///
/// `T` is restricted to records that carry a [Source] (any subclass of
/// [InfoBase]). Items from multiple providers are interleaved so that the
/// Nth element from each non-empty provider comes at position `N*k+i`.
class APIResultList<T extends InfoBase> with ListMixin<T> implements List<T> {
  APIResultList({
    required Iterable<T> items,
    this.cached = false,
    this.info,
    Map<Source, SourceRange>? sourceRanges,
  }) : _items = List<T>.from(items),
       _sourceRanges = Map.unmodifiable(
         sourceRanges ?? <Source, SourceRange>{},
       );

  /// Decorated copy of another [APIResultList].
  APIResultList.from(
    APIResultList<T> other, {
    Iterable<T>? items,
    InfoBase? info,
    Map<Source, SourceRange>? sourceRanges,
    bool? cached,
  }) : _items = List<T>.from(items ?? other._items),
       _sourceRanges = Map.unmodifiable(
         sourceRanges ?? Map<Source, SourceRange>.from(other._sourceRanges),
       ),
       info = info ?? other.info,
       cached = cached ?? other.cached;

  final List<T> _items;
  final Map<Source, SourceRange> _sourceRanges;

  /// Optional metadata (usually a [SearchInfo]).
  final InfoBase? info;

  /// Whether these results were served from a cache.
  final bool cached;

  /// Source ranges copy (read-only).
  Map<Source, SourceRange> get sourceRanges => _sourceRanges;

  /// All sources with at least one entry.
  List<Source> get sources => _sourceRanges.keys.toList(growable: false);

  /// Read-only view of the contained items.
  List<T> get itemsList => List.unmodifiable(_items);

  /// Per-source sparse iterables.
  Iterable<T> itemsFor(Source source) =>
      _items.where((i) => i.source == source);

  /// Whether any of the listed sources still has more pages.
  List<Source> get moreSources => [
    for (final entry in _sourceRanges.entries)
      if (entry.value.end - entry.value.start + 1 < entry.value.total)
        entry.key,
  ];

  // ---- ListMixin / List<T> implementation ----

  @override
  int get length => _items.length;

  @override
  set length(int value) => _items.length = value;

  @override
  T operator [](int index) => _items[index];

  @override
  void operator []=(int index, T value) => _items[index] = value;

  @override
  void add(T element) => _items.add(element);

  @override
  void addAll(Iterable<T> iterable) => _items.addAll(iterable);

  @override
  void clear() => _items.clear();

  @override
  Iterator<T> get iterator => _items.iterator;

  @override
  void insert(int index, T element) => _items.insert(index, element);

  @override
  void insertAll(int index, Iterable<T> iterable) =>
      _items.insertAll(index, iterable);

  @override
  T removeAt(int index) => _items.removeAt(index);

  @override
  T removeLast() => _items.removeLast();

  @override
  void removeWhere(bool Function(T) test) => _items.removeWhere(test);

  @override
  void retainWhere(bool Function(T) test) => _items.retainWhere(test);

  @override
  void setAll(int index, Iterable<T> iterable) =>
      _items.setAll(index, iterable);

  @override
  void sort([int Function(T a, T b)? compare]) => _items.sort(compare);

  @override
  bool remove(Object? element) => _items.remove(element);

  @override
  void removeRange(int start, int end) => _items.removeRange(start, end);

  @override
  void replaceRange(int start, int end, Iterable<T> newContents) =>
      _items.replaceRange(start, end, newContents);

  @override
  void fillRange(int start, int end, [T? fill]) {
    if (fill == null) {
      throw ArgumentError('fillRange requires a non-null fillValue');
    }
    _items.fillRange(start, end, fill);
  }

  @override
  void setRange(
    int start,
    int end,
    Iterable<T> iterable, [
    int skipCount = 0,
  ]) => _items.setRange(start, end, iterable, skipCount);

  @override
  Iterable<T> get reversed => _items.reversed;

  @override
  int indexOf(Object? element, [int start = 0]) =>
      _items.indexOf(element as T, start);

  @override
  int lastIndexOf(Object? element, [int? start]) {
    if (start == null) return _items.lastIndexOf(element as T);
    return _items.lastIndexOf(element as T, start);
  }

  @override
  bool contains(Object? element) => _items.contains(element);

  @override
  T elementAt(int index) => _items.elementAt(index);

  @override
  List<T> sublist(int start, [int? end]) =>
      end == null ? _items.sublist(start) : _items.sublist(start, end);

  @override
  String toString() =>
      'APIResultList(sources=$sources, length=$length, cached=$cached)';

  /// Merge with another [APIResultList] (sources must not collide).
  APIResultList<T> merged(APIResultList<T> other) {
    final combined = <T>[..._items, ...other._items];
    final ranges = <Source, SourceRange>{
      ..._sourceRanges,
      ...other._sourceRanges,
    };
    return APIResultList<T>(
      items: combined,
      sourceRanges: ranges,
      info: info ?? other.info,
      cached: cached && other.cached,
    );
  }
}
