// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Top-level multi-track lyrics container. Mirrors `LyricsBase` / `Lyrics` /
// `FSLyrics` from upstream LDDC.

import 'language.dart';
import 'lyric_info.dart';
import 'lyrics_models.dart';
import 'lyrics_type.dart';
import 'source.dart';
import 'song_info.dart';

/// Standard track names used across the library.
class TrackNames {
  TrackNames._();

  /// Original / source-language lyrics.
  static const String orig = 'orig';

  /// Translation.
  static const String ts = 'ts';

  /// Romanization.
  static const String roma = 'roma';

  /// Raw line-by-line LRC fallback.
  static const String origLrc = 'orig_lrc';
}

/// Multi-track lyrics: `orig`, `ts` (translation), `roma` (romanization),
/// `orig_lrc` (line-by-line fallback), and provider-specific extras.
///
/// [LyricsBase] keeps the `info` provenance record immutable (matching the
/// Python LDDC implementation). Subclasses expose mutation hooks specific to
/// their track type (`LyricsData` vs `FSLyricsData`).
abstract class LyricsBase<T> {
  LyricsBase(LyricInfo info)
    : _info = LyricInfo(
        source: info.source,
        songInfo: info.songInfo,
        id: info.id,
        accessKey: info.accessKey,
        duration: info.duration,
        creator: info.creator,
        score: info.score,
        cached: info.cached,
      ) {
    _tracks = <String, T>{};
    _tags = <String, String>{};
    _types = <String, LyricsType>{};
  }

  late Map<String, T> _tracks;
  late Map<String, String> _tags;
  late Map<String, LyricsType> _types;

  /// Provenance record (immutable).
  LyricInfo get info => _info;
  final LyricInfo _info;

  /// LRC `[ti:...]`, `[ar:...]`, etc. style tags.
  Map<String, String> get tags => _tags;

  /// Per-track [LyricsType] granularity map.
  Map<String, LyricsType> get types => _types;

  Source get source => _info.source;
  SongInfo get song => _info.songInfo;
  int? get duration => _info.duration;

  /// Provider-specific numeric id (when present).
  Object? get id => _info.id ?? _info.songInfo.id;

  /// Title with the `[ti:]` tag as fallback.
  String? get title => _info.songInfo.title ?? _tags['ti'];

  /// Joined artist string with `[ar:]` tag as fallback.
  String get artistString {
    final base = _info.songInfo.artistString;
    if (base.isNotEmpty) return base;
    return _tags['ar'] ?? '';
  }

  /// Album name with `[al:]` tag as fallback.
  String? get album => _info.songInfo.album ?? _tags['al'];

  /// Read-only view of all track entries (name → data).
  Map<String, T> get tracks => Map.unmodifiable(_tracks);

  /// Track names.
  Iterable<String> get trackNames => _tracks.keys;

  /// Whether the original track appears to have no lyrics.
  bool get isInstrumental {
    if (_info.songInfo.language == Language.instrumental) return true;
    final orig = this['orig'] as LyricsData?;
    if (orig == null || orig.isEmpty) return false;
    if (orig.length > 9) return false;
    final lastText = orig.last.text.trim();
    return lastText == '此歌曲为没有填词的纯音乐，请您欣赏' || lastText == '纯音乐，请欣赏';
  }

  /// Inferred duration in milliseconds, falling back across [info.duration],
  /// the last `orig` line and its words, then any track.
  int get inferredDuration {
    if (_info.duration != null) return _info.duration!;
    final orig = this['orig'] as LyricsData?;
    if (orig != null && orig.isNotEmpty) {
      final last = orig.last;
      if (last.end != null) return last.end!;
      if (last.words.isNotEmpty) {
        if (last.words.last.end != null) return last.words.last.end!;
        if (last.words.last.start != null) return last.words.last.start!;
      }
      if (last.start != null) return last.start!;
    }
    for (final entry in _tracks.entries) {
      final data = entry.value;
      if (data is LyricsData && data.isNotEmpty) {
        final last = data.last;
        if (last.end != null) return last.end!;
        if (last.words.isNotEmpty) {
          if (last.words.last.end != null) return last.words.last.end!;
          if (last.words.last.start != null) return last.words.last.start!;
        }
        if (last.start != null) return last.start!;
      }
    }
    return 0;
  }

  /// Get the data for [key], or `null` if not present.
  T? operator [](Object? key) => _tracks[key as String];

  /// Set or replace the data for [key].
  void operator []=(String key, T value) => _tracks[key] = value;

  /// True when [name] has a track.
  bool containsTrack(String name) => _tracks.containsKey(name);

  /// Drop all tracks / tags / types.
  void clear() {
    _tracks.clear();
    _tags.clear();
    _types.clear();
  }

  /// Number of tracks currently stored (alias of [trackNames.length]).
  int get length => _tracks.length;

  /// Shift every timestamp by [offsetMs] (in milliseconds), returning a new
  /// container of the same concrete type.
  LyricsBase<T> addOffset(int offsetMs);
}

/// Multi-track lyrics whose timestamps are allowed to be `null`.
class Lyrics extends LyricsBase<LyricsData> {
  Lyrics(super.info);

  /// Convenience constructor when only a [SongInfo] is known.
  Lyrics.fromSong(SongInfo song)
    : super(LyricInfo(source: song.source, songInfo: song));

  /// Walk each language track and produce a full-timestamp copy.
  FSLyrics toFullTimestamp({int? durationMs}) {
    final effectiveDuration = durationMs ?? inferredDuration;
    final fs = FSLyrics(_infoWith(durationMs));
    fs._types.addAll(_types);
    fs._tags.addAll(_tags);
    for (final entry in _tracks.entries) {
      fs._tracks[entry.key] = _fillMissingTimestamps(
        entry.value,
        effectiveDuration,
      );
      fs._types[entry.key] = LyricsType.verbatim;
    }
    return fs;
  }

  LyricInfo _infoWith(int? durationMs) {
    if (durationMs == null || durationMs == _info.duration) return _info;
    return LyricInfo(
      source: _info.source,
      songInfo: _info.songInfo,
      id: _info.id,
      accessKey: _info.accessKey,
      duration: durationMs,
      creator: _info.creator,
      score: _info.score,
      cached: _info.cached,
    );
  }

  @override
  Lyrics addOffset(int offsetMs) {
    final shifted = Lyrics(
      LyricInfo(
        source: _info.source,
        songInfo: _info.songInfo,
        id: _info.id,
        accessKey: _info.accessKey,
        duration: _info.duration,
        creator: _info.creator,
        score: _info.score,
        cached: _info.cached,
      ),
    );
    shifted._tags.addAll(_tags);
    shifted._types.addAll(_types);
    for (final entry in _tracks.entries) {
      shifted._tracks[entry.key] = LyricsData(
        entry.value
            .map((line) => _shiftLine(line, offsetMs))
            .toList(growable: false),
      );
    }
    return shifted;
  }

  /// Empty instrumental placeholder.
  static Lyrics instrumental(SongInfo song) {
    final lyrics = Lyrics.fromSong(song);
    final placeholder = LyricsLine(words: [const LyricsWord(text: '纯音乐，请欣赏')]);
    lyrics._tracks[TrackNames.orig] = LyricsData([placeholder]);
    lyrics._types[TrackNames.orig] = LyricsType.plainText;
    return lyrics;
  }

  /// Encode as the cross-LDDC JSON interchange format.
  Map<String, Object?> toJson() => {
    'version': 1,
    'info': _infoToJson(_info),
    'tags': Map<String, String>.from(_tags),
    'types': {for (final entry in _types.entries) entry.key: entry.value.name},
    'lyrics': {
      for (final entry in _tracks.entries) entry.key: (entry.value).toJson(),
    },
  };
}

/// Full-timestamp version — every timestamp is guaranteed non-null.
class FSLyrics extends LyricsBase<FSLyricsData> {
  FSLyrics(super.info);

  /// Convenience constructor when only a [SongInfo] is known.
  FSLyrics.fromSong(SongInfo song)
    : super(LyricInfo(source: song.source, songInfo: song));

  /// Convert back to a [Lyrics] (lossless — timestamps are already known).
  Lyrics toPartial() {
    final result = Lyrics(
      LyricInfo(
        source: _info.source,
        songInfo: _info.songInfo,
        id: _info.id,
        accessKey: _info.accessKey,
        duration: _info.duration,
        creator: _info.creator,
        score: _info.score,
        cached: _info.cached,
      ),
    );
    result._types.addAll(_types);
    result._tags.addAll(_tags);
    for (final entry in _tracks.entries) {
      result._tracks[entry.key] = LyricsData(
        entry.value.map((line) => line.toPartial()).toList(growable: false),
      );
    }
    return result;
  }

  @override
  FSLyrics addOffset(int offsetMs) {
    final shifted = FSLyrics(
      LyricInfo(
        source: _info.source,
        songInfo: _info.songInfo,
        id: _info.id,
        accessKey: _info.accessKey,
        duration: _info.duration,
        creator: _info.creator,
        score: _info.score,
        cached: _info.cached,
      ),
    );
    shifted._tags.addAll(_tags);
    shifted._types.addAll(_types);
    for (final entry in _tracks.entries) {
      shifted._tracks[entry.key] = FSLyricsData(
        entry.value
            .map((line) => _shiftFSLine(line, offsetMs))
            .toList(growable: false),
      );
    }
    return shifted;
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'info': _infoToJson(_info),
    'tags': Map<String, String>.from(_tags),
    'types': {for (final entry in _types.entries) entry.key: entry.value.name},
    'lyrics': {
      for (final entry in _tracks.entries) entry.key: (entry.value).toJson(),
    },
    'full': true,
  };
}

Map<String, Object?> _infoToJson(LyricInfo info) {
  return {
    'source': info.source.id,
    'song': {
      'title': info.songInfo.title,
      'subtitle': info.songInfo.subtitle,
      'artist': info.songInfo.artist?.names ?? const <String>[],
      'album': info.songInfo.album,
      'duration': info.songInfo.duration,
      'id': info.songInfo.id,
      'mid': info.songInfo.mid,
      'hash': info.songInfo.hash,
      'language': info.songInfo.language?.name,
    },
    'id': info.id,
    'accessKey': info.accessKey,
    'duration': info.duration,
    'creator': info.creator,
    'score': info.score,
  };
}

LyricsLine _shiftLine(LyricsLine line, int offsetMs) {
  return line.copyWith(
    start: line.start == null ? null : _clamp(line.start! + offsetMs),
    end: line.end == null ? null : _clamp(line.end! + offsetMs),
    words: line.words
        .map(
          (w) => w.copyWith(
            start: w.start == null ? null : _clamp(w.start! + offsetMs),
            end: w.end == null ? null : _clamp(w.end! + offsetMs),
          ),
        )
        .toList(growable: false),
  );
}

FSLyricsLine _shiftFSLine(FSLyricsLine line, int offsetMs) {
  return FSLyricsLine(
    start: _clamp(line.start + offsetMs),
    end: _clamp(line.end + offsetMs),
    words: line.words
        .map(
          (w) => FSLyricsWord(
            start: _clamp(w.start + offsetMs),
            end: _clamp(w.end + offsetMs),
            text: w.text,
          ),
        )
        .toList(growable: false),
  );
}

int _clamp(int ms) => ms < 0 ? 0 : ms;

FSLyricsData _fillMissingTimestamps(LyricsData source, int durationMs) {
  final list = <FSLyricsLine>[];
  for (var i = 0; i < source.length; i++) {
    final line = source[i];
    final next = i + 1 < source.length ? source[i + 1] : null;
    final prev = i > 0 ? list[i - 1] : null;

    final int lineStart;
    {
      int? candidate = line.start;
      candidate ??= line.words
          .firstWhere(
            (w) => w.start != null,
            orElse: () => const LyricsWord(text: ''),
          )
          .start;
      candidate ??= prev?.end;
      lineStart = _clamp(candidate ?? 0);
    }

    final int lineEnd;
    {
      int? candidate = line.end;
      if (candidate == null && line.words.isNotEmpty) {
        candidate = line.words
            .lastWhere(
              (w) => w.end != null,
              orElse: () => const LyricsWord(text: ''),
            )
            .end;
      }
      candidate ??= next?.start;
      candidate ??= durationMs > lineStart ? durationMs : lineStart;
      lineEnd = _clamp(candidate);
    }

    final fsWords = <FSLyricsWord>[];
    for (var j = 0; j < line.words.length; j++) {
      final word = line.words[j];
      final nextWord = j + 1 < line.words.length ? line.words[j + 1] : null;
      final prevFs = j > 0 ? fsWords[j - 1] : null;

      final int wordStart;
      {
        int? candidate = word.start;
        candidate ??= j == 0 ? lineStart : prevFs?.end;
        wordStart = _clamp(candidate ?? 0);
      }

      final int wordEnd;
      {
        int? candidate = word.end;
        candidate ??= nextWord?.start;
        candidate ??= j == line.words.length - 1 ? lineEnd : wordStart;
        wordEnd = _clamp(candidate);
      }
      fsWords.add(
        FSLyricsWord(start: wordStart, end: wordEnd, text: word.text),
      );
    }

    list.add(FSLyricsLine(start: lineStart, end: lineEnd, words: fsWords));
  }
  return FSLyricsData(list);
}
