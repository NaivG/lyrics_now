// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'text_similarity.dart';

({List<String> groups, List<String> artists}) artistStr2List(String artist) {
  final groups = <String>[];
  final artists = <String>[];
  var work = artist.trim();

  while (work.isNotEmpty) {
    final cvMatch = _cvPattern.firstMatch(work);
    if (cvMatch != null && cvMatch.start == 0) {
      final group = cvMatch.group(1)!.trim();
      final names = cvMatch.group(2)!;
      if (group.isNotEmpty) groups.add(_normalize(group));
      for (final name in names.split('・')) {
        final n = name.trim();
        if (n.isNotEmpty) artists.add(_normalize(n));
      }
      work = work.substring(cvMatch.end).trim();
      continue;
    }
    final splitIdx = _indexOfAny(work, ['/', '&', 'vs', 'VS', 'Vs', '、']);
    final part = splitIdx < 0 ? work : work.substring(0, splitIdx);
    {
      final n = _stripParens(part.trim());
      if (n.isNotEmpty) artists.add(_normalize(n));
    }
    if (splitIdx < 0) break;
    work = work.substring(splitIdx + 1).trim();
  }
  return (groups: groups, artists: artists);
}

final RegExp _cvPattern = RegExp(
  r'^([^(（]*?)[(（]\s*CV\s*[:：]\s*([^)）]+)[)）]',
  caseSensitive: false,
);

int _indexOfAny(String s, List<String> chars) {
  var idx = -1;
  for (final c in chars) {
    final i = s.indexOf(c);
    if (i >= 0 && (idx < 0 || i < idx)) idx = i;
  }
  return idx;
}

String _stripParens(String s) {
  var work = s.trim();
  while (work.startsWith('(') || work.startsWith('（')) {
    final close = work.indexOf(work.startsWith('(') ? ')' : '）');
    if (close < 0) break;
    work = work.substring(close + 1).trim();
  }
  while (work.endsWith(')') || work.endsWith('）')) {
    final open = work.lastIndexOf(work.endsWith(')') ? '(' : '（');
    if (open < 0) break;
    work = work.substring(0, open).trim();
  }
  return work;
}

String _normalize(String s) => s.trim().toLowerCase();

double calculateArtistScore(String target, String candidate) {
  if (target.trim().isEmpty && candidate.trim().isEmpty) return 100.0;
  if (target.trim().isEmpty || candidate.trim().isEmpty) return 0.0;

  final t = artistStr2List(target);
  final c = artistStr2List(candidate);

  var score = 0.0;
  var weight = 0.0;

  if (t.artists.isNotEmpty && c.artists.isNotEmpty) {
    score += listMaxDifference(t.artists, c.artists) * 70.0;
    weight += 70.0;
  }
  if (t.groups.isNotEmpty && c.groups.isNotEmpty) {
    score += listMaxDifference(t.groups, c.groups) * 30.0;
    weight += 30.0;
  }
  if (weight == 0) {
    return textDifference(target.toLowerCase(), candidate.toLowerCase()) *
        100.0;
  }
  return score / weight * 100.0;
}

double listMaxDifference(List<String> list1, List<String> list2) {
  if (list1.isEmpty && list2.isEmpty) return 1.0;
  if (list1.isEmpty || list2.isEmpty) return 0.0;
  final scores = <(double, int, int)>[];
  for (var i = 0; i < list1.length; i++) {
    for (var j = 0; j < list2.length; j++) {
      scores.add((textDifference(list1[i], list2[j]), i, j));
    }
  }
  scores.sort((a, b) => b.$1.compareTo(a.$1));

  final used1 = <int>{};
  final used2 = <int>{};
  var total = 0.0;
  var count = 0;
  for (final (score, i, j) in scores) {
    if (used1.contains(i) || used2.contains(j)) continue;
    used1.add(i);
    used2.add(j);
    total += score;
    count++;
  }
  return count > 0 ? total / count : 0.0;
}
