// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import '../models/lyrics.dart';

String srtConverter(
  FSLyrics lyrics, {
  List<String> langsOrder = const ['orig', 'ts', 'roma'],
}) {
  final buffer = StringBuffer();
  var index = 1;

  final orig = lyrics[TrackNames.orig];
  if (orig == null || orig.isEmpty) return '';

  for (var i = 0; i < orig.length; i++) {
    final origLine = orig[i];
    final texts = <String>[];
    for (final lang in langsOrder) {
      if (lang == TrackNames.orig) {
        texts.add(origLine.text);
        continue;
      }
      final track = lyrics[lang];
      if (track == null || i >= track.length) {
        texts.add('');
        continue;
      }
      texts.add(track[i].text);
    }
    final nonEmpty = texts.where((t) => t.isNotEmpty).toList();
    if (nonEmpty.isEmpty) continue;

    buffer.writeln(index);
    buffer.writeln('${_srtTime(origLine.start)} --> ${_srtTime(origLine.end)}');
    buffer.writeln(nonEmpty.join('\n'));
    buffer.writeln();
    index++;
  }

  return buffer.toString();
}

String _srtTime(int ms) {
  final totalSec = ms ~/ 1000;
  final hours = totalSec ~/ 3600;
  final minutes = (totalSec ~/ 60) % 60;
  final seconds = totalSec % 60;
  final millis = ms % 1000;
  return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')},${millis.toString().padLeft(3, '0')}';
}
