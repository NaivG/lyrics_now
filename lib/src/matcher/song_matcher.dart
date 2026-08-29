// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import '../models/lyrics_models.dart';
import '../models/song_info.dart';
import '../models/source.dart';
import 'artist_score.dart';
import 'text_similarity.dart';
import 'title_score.dart';

class ScoredSong {
  const ScoredSong({required this.song, required this.score});
  final SongInfo song;
  final double score;
}

class SongMatcher {
  const SongMatcher({this.minScore = 55, this.durationToleranceMs = 4000});

  final double minScore;
  final int durationToleranceMs;

  List<ScoredSong> findMatches(SongInfo target, List<SongInfo> candidates) {
    final scored = <ScoredSong>[];
    for (final candidate in candidates) {
      if (_durationMismatch(target, candidate)) continue;
      final score = scoreSong(target, candidate);
      if (score < minScore) continue;
      scored.add(ScoredSong(song: candidate, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    if (scored.isEmpty) return scored;
    final bestScore = scored.first.score;
    return scored.where((s) => s.score >= bestScore - 15).toList();
  }

  double scoreSong(SongInfo target, SongInfo candidate) {
    final titleScore = calculateTitleScore(
      target.fullTitle,
      candidate.fullTitle,
    );
    final artistScore = calculateArtistScore(
      target.artistString,
      candidate.artistString,
    );
    final albumScore =
        textDifference(
          (target.album ?? '').toLowerCase(),
          (candidate.album ?? '').toLowerCase(),
        ) *
        100.0;

    var score = 0.0;
    final hasArtist =
        target.artist != null &&
        target.artist!.isNotEmpty &&
        candidate.artist != null &&
        candidate.artist!.isNotEmpty;
    final hasAlbum =
        target.album != null &&
        target.album!.isNotEmpty &&
        candidate.album != null &&
        candidate.album!.isNotEmpty;

    if (hasArtist) {
      score = _max(
        titleScore * 0.5 + artistScore * 0.5,
        titleScore * 0.5 + artistScore * 0.35 + albumScore * 0.15,
      );
    } else if (hasAlbum) {
      score = _max(titleScore * 0.7 + albumScore * 0.3, titleScore * 0.8);
    } else {
      score = titleScore;
    }

    if (titleScore < 30) score -= 35;

    return score.clamp(0.0, 100.0);
  }

  bool _durationMismatch(SongInfo target, SongInfo candidate) {
    if (target.duration == null || candidate.duration == null) return false;
    return (target.duration! - candidate.duration!).abs() > durationToleranceMs;
  }

  static double _max(double a, double b) => a > b ? a : b;
}

Map<int, int> findClosestMatch(
  LyricsData data1,
  LyricsData data2, [
  LyricsData? data3,
  Source? source,
]) {
  if (data1.isEmpty || data2.isEmpty) return {};

  if (source == Source.qm || source == Source.kg) {
    if (data1.length == data2.length) {
      return {for (var i = 0; i < data1.length; i++) i: i};
    }
  }

  if (source == Source.ne && data3 != null && data3.isNotEmpty) {
    if (_lineCountMatch(data3, data2)) {
      return {for (var i = 0; i < data3.length; i++) i: i};
    }
    return _timeBasedMatch(data3, data2);
  }

  return _timeBasedMatch(data1, data2);
}

bool _lineCountMatch(LyricsData a, LyricsData b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final tA = a[i].text.trim();
    final tB = b[i].text.trim();
    if (tA.isEmpty != tB.isEmpty) return false;
  }
  return true;
}

Map<int, int> _timeBasedMatch(LyricsData source, LyricsData target) {
  final used = <int>{};
  final result = <int, int>{};
  final pairs = <_Pair>[];

  for (var i = 0; i < source.length; i++) {
    for (var j = 0; j < target.length; j++) {
      final diff = _timeDiff(source[i], target[j]);
      if (diff == null) continue;
      pairs.add(_Pair(i: i, j: j, diff: diff));
    }
  }

  pairs.sort((a, b) => a.diff.compareTo(b.diff));

  for (final pair in pairs) {
    if (used.contains(pair.j)) continue;
    if (result.containsKey(pair.i)) continue;
    result[pair.i] = pair.j;
    used.add(pair.j);
  }

  return result;
}

int? _timeDiff(LyricsLine a, LyricsLine b) {
  if (a.start == null || b.start == null) return null;
  return (a.start! - b.start!).abs();
}

class _Pair {
  const _Pair({required this.i, required this.j, required this.diff});
  final int i;
  final int j;
  final int diff;
}
