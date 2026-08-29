// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Information about a single track.

import 'artist.dart';
import 'info_base.dart';
import 'language.dart';
import 'source.dart';

/// Identifying metadata for a single track.
///
/// All fields are best-effort — providers fill what they know. Any unknown
/// field is `null` rather than an empty default, mirroring the upstream
/// Python LDDC implementation so callers can rely on `null` to mean "unknown".
class SongInfo extends InfoBase {
  const SongInfo({
    required super.source,
    this.title,
    this.subtitle,
    this.artist,
    this.album,
    this.duration,
    this.id,
    this.mid,
    this.hash,
    this.language,
  });

  /// Track title.
  final String? title;

  /// Optional subtitle or version tag.
  final String? subtitle;

  /// One or more artist names.
  final Artist? artist;

  /// Album name.
  final String? album;

  /// Track length in **milliseconds**.
  final int? duration;

  /// Provider-specific track id (the most stable identifier).
  final String? id;

  /// QQ Music's `mid` (a numeric-ish song key).
  final String? mid;

  /// Kugou's `hash` (the unique audio hash that maps to a lyric).
  final String? hash;

  /// Coarse language tag.
  final Language? language;

  /// `"title (subtitle)"` if [subtitle] is present, otherwise `"title"`,
  /// or `""` if [title] is null.
  String get fullTitle {
    final t = title;
    if (t == null || t.isEmpty) return '';
    final s = subtitle;
    if (s == null || s.isEmpty) return t;
    return '$t ($s)';
  }

  /// Joined artist string, or `""` if unknown.
  String get artistString => artist?.str() ?? '';

  /// `"artist - title"` with graceful handling of missing pieces.
  String artistTitle({bool full = false, bool replace = false}) {
    final rawTitle = full ? fullTitle : (title ?? '');
    final titleText = rawTitle.isEmpty ? (replace ? '?' : '') : rawTitle;
    final artistText = (artistString.isEmpty)
        ? (replace ? '?' : '')
        : artistString;
    if (titleText.isNotEmpty && artistText.isNotEmpty) {
      return '$artistText - $titleText';
    }
    return artistText + titleText;
  }

  /// `"mm:ss"` formatted duration, or `""` if unknown.
  String get formatDuration {
    final d = duration;
    if (d == null) return '';
    final minutes = (d ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((d ~/ 1000) % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  /// Build a copy with selected fields replaced.
  SongInfo copyWith({
    Source? source,
    String? title,
    String? subtitle,
    Artist? artist,
    String? album,
    int? duration,
    String? id,
    String? mid,
    String? hash,
    Language? language,
  }) {
    return SongInfo(
      source: source ?? this.source,
      title: title ?? this.title,
      subtitle: subtitle ?? this.subtitle,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      id: id ?? this.id,
      mid: mid ?? this.mid,
      hash: hash ?? this.hash,
      language: language ?? this.language,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SongInfo || other.source != source) return false;
    return title == other.title &&
        subtitle == other.subtitle &&
        artist == other.artist &&
        album == other.album &&
        duration == other.duration &&
        id == other.id &&
        mid == other.mid &&
        hash == other.hash &&
        language == other.language;
  }

  @override
  int get hashCode => Object.hash(
    source,
    title,
    subtitle,
    artist,
    album,
    duration,
    id,
    mid,
    hash,
    language,
  );

  Map<String, Object?> toJson() => {
    'source': source.id,
    'title': title,
    'subtitle': subtitle,
    'artist': artist?.names,
    'album': album,
    'duration': duration,
    'id': id,
    'mid': mid,
    'hash': hash,
    'language': language?.name,
  };

  static SongInfo fromJson(Map<String, Object?> json) {
    return SongInfo(
      source:
          Source.fromId((json['source'] as num?)?.toInt() ?? 0) ?? Source.multi,
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
      artist: json['artist'] != null ? Artist(json['artist'] as List) : null,
      album: json['album'] as String?,
      duration: (json['duration'] as num?)?.toInt(),
      id: json['id'] as String?,
      mid: json['mid'] as String?,
      hash: json['hash'] as String?,
      language: _parseLanguage(json['language'] as String?),
    );
  }

  static Language? _parseLanguage(String? name) {
    if (name == null) return null;
    for (final lang in Language.values) {
      if (lang.name == name) return lang;
    }
    return null;
  }

  @override
  String toString() => 'SongInfo(${artistTitle()})';
}
