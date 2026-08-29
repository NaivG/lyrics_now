// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Command-line entry point for lyrics_now.
//
// Usage:
//   dart run bin/lyrics_now.dart "song keyword"
//   dart run bin/lyrics_now.dart --search "song keyword"
//   dart run bin/lyrics_now.dart --version
//
// The CLI instantiates a `LyricFinder` with all available providers and
// prints search results or lyrics.

import 'package:lyrics_now/lyrics_now.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    print('Usage: dart run bin/lyrics_now.dart "song keyword"');
    print('');
    print('Options:');
    print('  --version    Print library version information.');
    print('  --search     Run a song search and print results grouped by source.');
    return;
  }

  if (args.first == '--version') {
    print('lyrics_now 0.3.0 (LGPL/GPL LICENSE: GPL-3.0-only)');
    return;
  }

  var search = false;
  final positional = <String>[];
  for (final arg in args) {
    if (arg == '--search') {
      search = true;
    } else {
      positional.add(arg);
    }
  }
  if (positional.isEmpty) {
    print('No keyword provided.');
    return;
  }
  final keyword = positional.join(' ');

  final finder = LyricFinder(
    providers: [
      LrclibProvider(PackageHttpClient()),
      KgProvider(PackageHttpClient()),
      QmProvider(PackageHttpClient()),
      NeProvider(PackageHttpClient()),
    ],
  );

  try {
    if (search) {
      final results = await finder.searchSongs(
        SearchQuery(keyword: keyword, searchType: SearchType.song),
      );
      if (results.isEmpty) {
        print('No results found for "$keyword".');
        return;
      }
      for (final source in results.sources) {
        final songs = results.itemsFor(source);
        if (songs.isEmpty) continue;
        print('--- ${source.label} ---');
        for (final song in songs.take(3)) {
          print(
            '${song.artistString.isEmpty ? "?" : song.artistString} - '
            '${song.title ?? "?"} '
            '(${song.formatDuration})',
          );
        }
      }
      return;
    }

    // Default mode: search and fetch lyrics.
    final results = await finder.searchSongs(
      SearchQuery(keyword: keyword, searchType: SearchType.song),
    );
    if (results.isEmpty) {
      print('No results for "$keyword".');
      return;
    }
    final first = results.first;
    print(
      'Found: ${first.artistString} - ${first.title} '
      '[${first.formatDuration}] (${first.source.label})',
    );

    final lyrics = await finder.fetchLyrics(
      song: first,
      durationMs: first.duration ?? 0,
    );
    if (lyrics == null) {
      print('Could not fetch lyrics from any provider.');
      return;
    }

    print('--- lyrics ---');
    final tracker = lyrics['orig'];
    if (tracker == null) {
      print('(no orig track)');
      return;
    }
    for (final line in tracker) {
      final stamp = (s) {
        if (s == null) return '--:--';
        final mm = (s ~/ 60000).toString().padLeft(2, '0');
        final ss = ((s ~/ 1000) % 60).toString().padLeft(2, '0');
        final ms = (s % 1000 ~/ 10).toString().padLeft(2, '0');
        return '[$mm:$ss.$ms]';
      }(line.start);
      print('$stamp ${line.text}');
    }
  } finally {
    finder.close();
  }
}
