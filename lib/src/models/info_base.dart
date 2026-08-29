// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Common supertype for `InfoBase` records.

import 'source.dart';

/// Base type for typed info records returned by providers.
///
/// Concrete subclasses include [SongInfo], [SongListInfo], and [LyricInfo].
/// All records carry at least the [Source] that produced them so that a
/// heterogeneous list can be sorted back into its original provider ordering.
abstract class InfoBase {
  const InfoBase({required this.source});

  /// Which provider produced this record.
  final Source source;
}
