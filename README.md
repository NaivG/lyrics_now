# lyrics_now

> A pure-Dart lyric finder library inspired by
> [LDDC](https://github.com/chenmozhijin/LDDC).

`lyrics_now` searches and matches precise (word-by-word / line-by-line) lyrics
across multiple music platforms:

| Source | Coverage | Status |
|---|---|---|
| QQ Music | song/album/song-list search + song-list fetch + cloud-QRC lyrics (3DES + zlib decrypt) | ✅ `QmProvider` shipped |
| Kugou | song/album/play-list search + song-list fetch + KRC lyrics (decrypt + parser) | ✅ `KgProvider` shipped |
| NetEase | song/album/playlist search + song-list fetch + EAPI-encrypted lyrics (YRC + tlyric + romalrc) | ✅ `NeProvider` shipped (with anonymous auto-login) |
| LRCLIB | song search + sync/plain lyrics | ✅ `LrclibProvider` shipped |

The library includes:

- A `LyricsProvider` abstraction (`abstract interface class`) with default
  implementations.
- An injectable `LyricsHttpClient` (default `PackageHttpClient` over
  `package:http`, HTTP/2 transport slot reserved for a future `package:http2`
  integration).
- Lyric data primitives (`LyricsWord`, `LyricsLine`, `LyricsData`, `Lyrics`,
  `FSLyrics`) with full JSON round-tripping.
- LRC parser supporting plain, verbatim, enhanced inline, and
  NetEase-style multi-stamp lines (one line per timestamp); plus QRC, KRC
  and YRC parsers.
- Crypto primitives (`lib/src/crypto/`):
  - `aes_ecb.dart` — AES-128-ECB with PKCS#7 padding (NIST vector verified).
  - `des_ede.dart` — 3DES (DES-EDE-EDE) for QQ cloud QRC decryption.
  - `qmc1.dart` — QMC1 XOR stream cipher for local QRC files.
  - `qrc.dart` — orchestrator for QRC decrypt (`QrcType.local` / `QrcType.cloud`).
  - `krc.dart` — KRC decryption (magic-check + XOR + `zlib` inflate).
  - `eapi.dart` — NetEase EAPI AES-128-ECB envelope (request sign, response
    decrypt, anonymous-username derivation, cache-key helper).
  - `kugou_sign.dart` — Kugou signature + header helpers.
- `NeCookieStore` interface + `InMemoryNeCookieStore` default for persisting
  anonymous-login cookies (default TTL = 10 days, matching upstream).
- `LyricFinder` facade with parallel fan-out across providers, configurable
  TTL cache, and `fetchLyrics` waterfall.

## Quick start

```dart
import 'package:lyrics_now/lyrics_now.dart';

Future<void> main() async {
  final http = PackageHttpClient();
  final finder = LyricFinder(
    http: http,
    providers: [
      LrclibProvider(http),
      KgProvider(http),
      QmProvider(http),
      NeProvider(http),
    ],
  );

  try {
    final results = await finder.searchSongs(
      const SearchQuery(keyword: 'Kud Wafter', searchType: SearchType.song),
    );
    if (results.isEmpty) return;
    final lyrics = await finder.fetchLyrics(song: results.first);
    if (lyrics == null) return;
    print(lyrics['orig']?.first.text ?? '(no lyrics)');
  } finally {
    finder.close();
  }
}
```

Run the bundled CLI:

```bash
dart run bin/lyrics_now.dart "Kud Wafter --search"
```

## NetEase anonymous-login persistence

`NeProvider` performs a one-time anonymous auto-login on first use and caches
the negotiated cookies via `NeCookieStore`. The default
`InMemoryNeCookieStore` survives until the process exits; supply your own
implementation to persist across restarts:

```dart
final store = FileNeCookieStore(
  path: '${Platform.environment['HOME']}/.lyrics_now/ne_cookies.json',
);
final provider = NeProvider(http, cookieStore: store);
```

## Testing

```bash
dart pub get
dart analyze
dart test
```

## License

GPL-3.0-only. See [LICENSE](./LICENSE).
