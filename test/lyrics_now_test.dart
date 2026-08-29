// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

void main() {
  test('package exposes public surface', () {
    expect(LyricFinder, isNotNull);
    expect(LrclibProvider, isNotNull);
    expect(Source.values, contains(Source.lrclib));
  });
}
