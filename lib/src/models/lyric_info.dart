// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Result of a lyric-fetch request: which song, which provider, which access
// key, and (optionally) the raw bytes for cached replay.

import 'dart:typed_data';

import 'info_base.dart';
import 'song_info.dart';
import 'source.dart';

/// Pointer returned by `LyricsProvider.getLyricsList` describing a single
/// candidate lyrics record on the provider's side.
class LyricInfo extends InfoBase {
  const LyricInfo({
    required super.source,
    required this.songInfo,
    this.id,
    this.accessKey,
    this.duration,
    this.creator,
    this.score,
    this.path,
    this.data,
    this.cached = false,
  });

  /// The track this lyric belongs to.
  final SongInfo songInfo;

  /// Provider-specific lyric id (where applicable, e.g. LRCLIB).
  final String? id;

  /// Access key for QQ-style APIs.
  final String? accessKey;

  /// Lyric length in **milliseconds**, when reported by the provider.
  final int? duration;

  /// Lyric creator/uploader nickname where known.
  final String? creator;

  /// User-assigned score (QQ Music's 0–100 ranking).
  final int? score;

  /// Local file path when the lyrics were loaded from disk.
  final String? path;

  /// Cached lyric payload, if the provider returned one.
  final Uint8List? data;

  /// True if this info was served from a cache.
  final bool cached;

  /// `"mm:ss"` formatted lyric duration.
  String get formatDuration {
    final d = duration;
    if (d == null) return '';
    final minutes = (d ~/ 60000).toString().padLeft(2, '0');
    final seconds = ((d ~/ 1000) % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  LyricInfo copyWith({
    Source? source,
    SongInfo? songInfo,
    String? id,
    String? accessKey,
    int? duration,
    String? creator,
    int? score,
    String? path,
    Uint8List? data,
    bool? cached,
  }) {
    return LyricInfo(
      source: source ?? this.source,
      songInfo: songInfo ?? this.songInfo,
      id: id ?? this.id,
      accessKey: accessKey ?? this.accessKey,
      duration: duration ?? this.duration,
      creator: creator ?? this.creator,
      score: score ?? this.score,
      path: path ?? this.path,
      data: data ?? this.data,
      cached: cached ?? this.cached,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LyricInfo || other.source != source) return false;
    return songInfo == other.songInfo &&
        id == other.id &&
        accessKey == other.accessKey &&
        duration == other.duration &&
        creator == other.creator &&
        score == other.score;
  }

  @override
  int get hashCode =>
      Object.hash(source, songInfo, id, accessKey, duration, creator, score);
}
