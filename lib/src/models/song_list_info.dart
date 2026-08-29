// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Metadata for albums and curated playlists.

import 'info_base.dart';

/// Discriminates between an album and a playlist.
enum SongListType { album, songList }

/// Information describing an album or playlist. Used as the address argument
/// for `LyricsProvider.getSongList` / search-by-album flows.
class SongListInfo extends InfoBase {
  const SongListInfo({
    required super.source,
    required this.type,
    required this.id,
    required this.title,
    required this.imgUrl,
    this.songCount,
    this.publishTime,
    required this.author,
    this.mid,
  });

  /// Album vs playlist.
  final SongListType type;

  /// Provider-specific list id.
  final String id;

  /// Title shown in the UI.
  final String title;

  /// Cover-art URL.
  final String imgUrl;

  /// Number of tracks when known.
  final int? songCount;

  /// Publish / create timestamp in seconds since epoch.
  final int? publishTime;

  /// Author for playlists, artist for albums.
  final String author;

  /// QQ Music `mid` when applicable.
  final String? mid;

  /// `"yyyy-MM-dd"` published-at string, or `""`.
  String get formatPublishTime {
    final ts = publishTime;
    if (ts == null) return '';
    return DateTime.fromMillisecondsSinceEpoch(
      ts * 1000,
      isUtc: true,
    ).toIso8601String().substring(0, 10);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SongListInfo || other.source != source) return false;
    return type == other.type &&
        id == other.id &&
        mid == other.mid &&
        title == other.title;
  }

  @override
  int get hashCode => Object.hash(source, type, id, mid, title);
}
