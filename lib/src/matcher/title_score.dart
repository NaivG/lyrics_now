// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'text_similarity.dart';

final Map<RegExp, String> _versionTags = {
  RegExp(
    r'\s*[-–—]\s*(original\s+)?(karaoke|off\s+vocal|offvocal|instrumental|inst)\s*(ver\.?\s*.*)?$',
    caseSensitive: false,
  ): '',
  RegExp(r'\s*[(（\[][Ss][Oo][Ll][Oo]\s+[Vv][Ee][Rr][.]?\s*[^)）\]]*[)）\]]'): '',
  RegExp(
    r'\s*[(（\[]\s*(solo|acoustic|remix|rearranged|rearrangement|short\s*ver|full\s*ver|game\s*ver|tv\s*size|movie\s*edit|anime\s*size|opening|ending|theme|insert|image)\s*(ver\.?\s*\d*)?\s*[)）\]]',
    caseSensitive: false,
  ): '',
  RegExp(r'\s*[(（\[]\s*cover\s*[)）\]]', caseSensitive: false): '',
  RegExp(
    r'\s*[-–—]\s*(オリジナル\s*)?(カラオケ|オフボーカル|インストゥルメンタル|インスト)\s*(ver\.?\s*.*)?$',
  ): '',
};

String _stripTags(String title) {
  var result = title.trim();
  for (final entry in _versionTags.entries) {
    result = result.replaceAll(entry.key, entry.value);
  }
  return result.trim();
}

String _commonPrefix(String a, String b) {
  var i = 0;
  while (i < a.length && i < b.length && a[i] == b[i]) {
    i++;
  }
  return a.substring(0, i);
}

double calculateTitleScore(String target, String candidate) {
  if (target.trim().isEmpty && candidate.trim().isEmpty) return 100.0;
  if (target.trim().isEmpty || candidate.trim().isEmpty) return 0.0;

  final t = target.trim().toLowerCase();
  final c = candidate.trim().toLowerCase();

  final rawSimilarity = textDifference(t, c);

  final tStripped = _stripTags(t);
  final cStripped = _stripTags(c);

  final prefix = _commonPrefix(tStripped, cStripped);
  final prefixRatio = tStripped.isEmpty
      ? 0.0
      : prefix.length /
            (tStripped.length > cStripped.length
                ? tStripped.length
                : cStripped.length);

  final suffixA = tStripped.substring(prefix.length).trim();
  final suffixB = cStripped.substring(prefix.length).trim();
  final suffixDiff = suffixA.isEmpty && suffixB.isEmpty
      ? 1.0
      : textDifference(suffixA, suffixB);

  final hasTagMatch = _hasMatchingTag(target, candidate);

  var score = 0.0;
  if (prefixRatio >= 0.4) {
    score = prefixRatio * 50.0 + suffixDiff * 40.0 + (hasTagMatch ? 10.0 : 0.0);
  } else {
    score = rawSimilarity * 100.0;
  }

  return score.clamp(0.0, 100.0);
}

bool _hasMatchingTag(String a, String b) {
  final tagsA = _extractTags(a);
  final tagsB = _extractTags(b);
  if (tagsA.isEmpty || tagsB.isEmpty) return false;
  for (final tag in tagsA) {
    if (tagsB.contains(tag)) return true;
  }
  return false;
}

final RegExp _tagExtract = RegExp(
  r'[(（\[]\s*(solo|acoustic|remix|rearranged|rearrangement|short ver|full ver|game ver|tv size|movie edit|anime size|opening|ending|theme|insert|image|cover|inst|instrumental|karaoke)\s*[)）\]]',
  caseSensitive: false,
);

Set<String> _extractTags(String title) {
  final result = <String>{};
  for (final match in _tagExtract.allMatches(title.toLowerCase())) {
    result.add(match.group(1)!);
  }
  return result;
}
