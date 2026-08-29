// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

double textDifference(String a, String b) {
  if (a == b) return 1.0;
  if (a.isEmpty || b.isEmpty) return 0.0;
  final bigrams = <String>{};
  for (var i = 0; i < a.length - 1; i++) {
    bigrams.add(a.substring(i, i + 2));
  }
  if (bigrams.isEmpty) return 0.0;
  var overlap = 0;
  for (var i = 0; i < b.length - 1; i++) {
    if (bigrams.remove(b.substring(i, i + 2))) overlap++;
  }
  return 2.0 * overlap / (a.length + b.length - 2);
}
