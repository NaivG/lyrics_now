// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Describes a single search query issued by `LyricFinder`.

import 'info_base.dart';
import 'search_type.dart';
import 'source.dart';

/// Captured search query, used as both input and provenance metadata for
/// downstream result lists.
///
/// The `source` of the *query* is one or many [Source] values. When more
/// than one source is involved, the outer [InfoBase.source] is reported as
/// [Source.multi] so callers can distinguish "from a single provider" from
/// "merged across providers".
class SearchInfo extends InfoBase {
  /// Build for either a single or multi-source query. When [sources] is a
  /// [List], the resulting [source] becomes [Source.multi].
  SearchInfo({
    required Object sources,
    required this.keyword,
    required this.searchType,
    this.page,
    this.parent,
  }) : _sources = _normalize(sources),
       super(
         source: _normalize(sources) is List
             ? Source.multi
             : (_normalize(sources) as Source),
       );

  /// Convenience constructor for a single-source query.
  factory SearchInfo.single({
    required Source source,
    required String keyword,
    required SearchType searchType,
    int? page,
  }) {
    return SearchInfo(
      sources: source,
      keyword: keyword,
      searchType: searchType,
      page: page,
    );
  }

  /// Convenience constructor for a multi-source query.
  factory SearchInfo.many({
    required List<Source> sources,
    required String keyword,
    required SearchType searchType,
    int? page,
    InfoBase? parent,
  }) {
    return SearchInfo(
      sources: sources,
      keyword: keyword,
      searchType: searchType,
      page: page,
      parent: parent,
    );
  }

  static Object _normalize(Object input) {
    if (input is Source) return input;
    if (input is List) {
      return List<Source>.unmodifiable(input.cast<Source>());
    }
    throw ArgumentError.value(
      input,
      'sources',
      'must be Source or List<Source>',
    );
  }

  /// Either a single [Source] or an immutable `List<Source>` when the query
  /// spans multiple providers.
  final Object _sources;

  /// Cast back to [Source] or read the list as-is.
  Source? get singleSource => _sources is Source ? _sources : null;

  /// List of [Source]s involved or `null` for single-source queries.
  List<Source>? get sourceList => _sources is List<Source> ? _sources : null;

  /// True when this query spans multiple providers.
  bool get isMulti => _sources is List<Source>;

  /// Iterator over all sources touched by this query.
  Iterable<Source> get allSources {
    final s = _sources;
    if (s is Source) return <Source>[s];
    return s as List<Source>;
  }

  /// Raw user-typed query.
  final String keyword;

  /// What kind of entity was searched for.
  final SearchType searchType;

  /// 1-based page number when paginated.
  final int? page;

  /// Optional parent reference (when the query was spawned by an album or
  /// song-list expansion).
  final InfoBase? parent;

  @override
  String toString() =>
      'SearchInfo(${allSources.join(',')}: "$keyword" [$searchType, page=$page])';
}
