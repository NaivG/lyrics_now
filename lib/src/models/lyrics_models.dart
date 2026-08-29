// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Line- and word-level lyrics primitives.
//
// All timestamps are stored in **milliseconds** to match LDDC's interchange
// format and make JSON serialization straightforward. A duration extension
// helper is included for ergonomic usage at call sites.

/// A single lyrical token, optionally framed by start/end timestamps.
///
/// Either [start] or [end] may be `null` when the source format does not
/// provide enough information (for example plain LRC without word timings).
class LyricsWord {
  const LyricsWord({this.start, this.end, required this.text});

  /// Start offset in **milliseconds**, or `null` when unknown.
  final int? start;

  /// End offset in **milliseconds**, or `null` when unknown.
  final int? end;

  /// The token itself. Should not contain line breaks.
  final String text;

  Duration? get startDuration =>
      start == null ? null : Duration(milliseconds: start!);
  Duration? get endDuration =>
      end == null ? null : Duration(milliseconds: end!);

  /// Convenience helper for emitting LRC tokens.
  String renderText() => text;

  Map<String, Object?> toJson() => {
    if (start != null) 'start': start,
    if (end != null) 'end': end,
    'text': text,
  };

  static LyricsWord fromJson(Map<String, Object?> json) {
    return LyricsWord(
      start: (json['start'] as num?)?.toInt(),
      end: (json['end'] as num?)?.toInt(),
      text: json['text']?.toString() ?? '',
    );
  }

  LyricsWord copyWith({int? start, int? end, String? text}) {
    return LyricsWord(
      start: start ?? this.start,
      end: end ?? this.end,
      text: text ?? this.text,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LyricsWord &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);

  @override
  String toString() => 'LyricsWord(${start ?? '-'}→${end ?? '-'}:"$text")';
}

/// A line of lyrics (one or more [LyricsWord]s), bounded by timestamps.
class LyricsLine {
  const LyricsLine({this.start, this.end, required this.words});

  /// Line start offset in **milliseconds**, or `null` when unknown.
  final int? start;

  /// Line end offset in **milliseconds**, or `null` when unknown.
  final int? end;

  /// Word-level decomposition. May contain zero words for blank/instrumental
  /// markers.
  final List<LyricsWord> words;

  /// Concatenated text of all words in the line.
  String get text => words.map((w) => w.text).join();

  Duration? get startDuration =>
      start == null ? null : Duration(milliseconds: start!);
  Duration? get endDuration =>
      end == null ? null : Duration(milliseconds: end!);

  Map<String, Object?> toJson() => {
    if (start != null) 'start': start,
    if (end != null) 'end': end,
    'words': words.map((w) => w.toJson()).toList(growable: false),
  };

  static LyricsLine fromJson(Map<String, Object?> json) {
    final raw = (json['words'] as List?) ?? const <Object?>[];
    return LyricsLine(
      start: (json['start'] as num?)?.toInt(),
      end: (json['end'] as num?)?.toInt(),
      words: raw
          .whereType<Map>()
          .map((m) => LyricsWord.fromJson(m.cast<String, Object?>()))
          .toList(growable: false),
    );
  }

  LyricsLine copyWith({int? start, int? end, List<LyricsWord>? words}) {
    return LyricsLine(
      start: start ?? this.start,
      end: end ?? this.end,
      words: words ?? this.words,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LyricsLine &&
      other.start == start &&
      other.end == end &&
      _listEquals(other.words, words);

  @override
  int get hashCode => Object.hash(start, end, Object.hashAll(words));

  @override
  String toString() =>
      'LyricsLine(${start ?? '-'}→${end ?? '-'}:"${text.replaceAll('\n', '⏎')}")';
}

/// Mutable list of [LyricsLine] that backs one lyrics track (e.g. `orig`,
/// `ts`, `roma`, ...).
class LyricsData extends Iterable<LyricsLine> {
  LyricsData([Iterable<LyricsLine>? initial])
    : _lines = List<LyricsLine>.from(initial ?? const <LyricsLine>[]);

  final List<LyricsLine> _lines;

  /// Read-only view.
  List<LyricsLine> get lines => List.unmodifiable(_lines);

  @override
  int get length => _lines.length;
  @override
  bool get isEmpty => _lines.isEmpty;
  @override
  bool get isNotEmpty => _lines.isNotEmpty;

  void add(LyricsLine line) => _lines.add(line);
  void addAll(Iterable<LyricsLine> lines) => _lines.addAll(lines);
  void clear() => _lines.clear();

  /// Sort the underlying list of lines using [compare]. By default sorts by
  /// `[start] -> null -> infinity` so missing timestamps fall after any
  /// timestamped line.
  void sort([int Function(LyricsLine a, LyricsLine b)? compare]) {
    final cmp =
        compare ??
        (a, b) {
          final sa = a.start;
          final sb = b.start;
          if (sa == null && sb == null) return 0;
          if (sa == null) return 1;
          if (sb == null) return -1;
          return sa.compareTo(sb);
        };
    _lines.sort(cmp);
  }

  LyricsLine operator [](int index) => _lines[index];

  void operator []=(int index, LyricsLine value) => _lines[index] = value;

  @override
  Iterator<LyricsLine> get iterator => _lines.iterator;

  Map<String, Object?> toJson() => {
    'lines': _lines.map((l) => l.toJson()).toList(growable: false),
  };

  static LyricsData fromJson(Map<String, Object?> json) {
    final raw = (json['lines'] as List?) ?? const <Object?>[];
    return LyricsData(
      raw
          .whereType<Map>()
          .map((m) => LyricsLine.fromJson(m.cast<String, Object?>()))
          .toList(growable: false),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LyricsData && _listEquals(other._lines, _lines);

  @override
  int get hashCode => Object.hashAll(_lines);
}

/// Full-timestamp version of [LyricsWord] — all timestamps are guaranteed
/// non-null.
class FSLyricsWord {
  const FSLyricsWord({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;

  Duration get startDuration => Duration(milliseconds: start);
  Duration get endDuration => Duration(milliseconds: end);

  Map<String, Object?> toJson() => {'start': start, 'end': end, 'text': text};

  static FSLyricsWord fromJson(Map<String, Object?> json) => FSLyricsWord(
    start: ((json['start'] as num?) ?? 0).toInt(),
    end: ((json['end'] as num?) ?? 0).toInt(),
    text: json['text']?.toString() ?? '',
  );

  LyricsWord toPartial() => LyricsWord(start: start, end: end, text: text);

  @override
  bool operator ==(Object other) =>
      other is FSLyricsWord &&
      other.start == start &&
      other.end == end &&
      other.text == text;

  @override
  int get hashCode => Object.hash(start, end, text);
}

/// Full-timestamp line — every timestamp position is non-null.
class FSLyricsLine {
  const FSLyricsLine({
    required this.start,
    required this.end,
    required this.words,
  });

  final int start;
  final int end;
  final List<FSLyricsWord> words;

  String get text => words.map((w) => w.text).join();
  Duration get startDuration => Duration(milliseconds: start);
  Duration get endDuration => Duration(milliseconds: end);

  Map<String, Object?> toJson() => {
    'start': start,
    'end': end,
    'words': words.map((w) => w.toJson()).toList(growable: false),
  };

  static FSLyricsLine fromJson(Map<String, Object?> json) {
    final raw = (json['words'] as List?) ?? const <Object?>[];
    return FSLyricsLine(
      start: ((json['start'] as num?) ?? 0).toInt(),
      end: ((json['end'] as num?) ?? 0).toInt(),
      words: raw
          .whereType<Map>()
          .map((m) => FSLyricsWord.fromJson(m.cast<String, Object?>()))
          .toList(growable: false),
    );
  }

  LyricsLine toPartial() => LyricsLine(
    start: start,
    end: end,
    words: words.map((w) => w.toPartial()).toList(growable: false),
  );
}

/// Full-timestamp track.
class FSLyricsData extends Iterable<FSLyricsLine> {
  FSLyricsData([Iterable<FSLyricsLine>? initial])
    : _lines = List<FSLyricsLine>.from(initial ?? const <FSLyricsLine>[]);

  final List<FSLyricsLine> _lines;

  List<FSLyricsLine> get lines => List.unmodifiable(_lines);
  @override
  int get length => _lines.length;
  @override
  bool get isEmpty => _lines.isEmpty;
  @override
  bool get isNotEmpty => _lines.isNotEmpty;

  void add(FSLyricsLine line) => _lines.add(line);
  void addAll(Iterable<FSLyricsLine> lines) => _lines.addAll(lines);
  void clear() => _lines.clear();

  void sort([int Function(FSLyricsLine a, FSLyricsLine b)? compare]) {
    _lines.sort(compare);
  }

  FSLyricsLine operator [](int index) => _lines[index];
  void operator []=(int index, FSLyricsLine value) => _lines[index] = value;

  @override
  Iterator<FSLyricsLine> get iterator => _lines.iterator;

  Map<String, Object?> toJson() => {
    'lines': _lines.map((l) => l.toJson()).toList(growable: false),
  };

  static FSLyricsData fromJson(Map<String, Object?> json) {
    final raw = (json['lines'] as List?) ?? const <Object?>[];
    return FSLyricsData(
      raw
          .whereType<Map>()
          .map((m) => FSLyricsLine.fromJson(m.cast<String, Object?>()))
          .toList(growable: false),
    );
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
