# Changelog

## 0.3.0

- New providers: `QmProvider` (QQ Music `musicu.fcg` envelope with cloud-QRC
  decrypt via 3DES-EDE-EDE + zlib) and `NeProvider` (NetEase Cloud Music EAPI
  envelope with anonymous auto-login and lazy session bootstrap).
- New `NeCookieStore` interface + `InMemoryNeCookieStore` default for persisting
  anonymous-login cookies (default TTL = 10 days, matching upstream).
- `package:archive` added; `KRC` and `QRC` decryption paths migrated from
  `dart:io` zlib to a pure-Dart `ZLibDecoder` for cross-platform support.
- YRC parser preserved per upstream LDDC; multi-stamp LRC parser now produces
  one line per timestamp to match `LDDC\core\parser\lrc.py` behaviour.
- Fixed `QmProvider._ensureComm` recursion (the inner `GetSession` call now
  passes `needsSession: false` so `_request` doesn't loop forever waiting on
  the same comm block).
- 80 tests passing; `dart analyze` clean; default `LyricFinder` chain now
  includes QQ and NetEase.

## 0.2.0

- Add Kugou (`KgProvider`) — full search + album + playlist + KRC lyrics
  decryption via `LDDC\core\decryptor\__init__.py` parity (XOR + zlib) with
  the canonical `LnT6xpN3khm36zse0QzvmgTZ3waWdRSA` signature.
- New crypto layer (`lib/src/crypto/`):
  - `aes_ecb.dart` — AES-128-ECB with PKCS#7 padding (NIST vector verified).
  - `des_ede.dart` — 3DES (DES-EDE-EDE) for QQ cloud QRC decryption.
  - `qmc1.dart` — QMC1 XOR stream cipher for local QRC files.
  - `qrc.dart` — orchestrator for QRC decrypt (`QrcType.local` / `QrcType.cloud`).
  - `krc.dart` — KRC decryption (magic-check + XOR + zlib).
  - `eapi.dart` — NetEase EAPI AES-128-ECB envelope (request sign, response
    decrypt, anonymous-username derivation, cache-key helper).
  - `kugou_sign.dart` — Kugou signature + header helpers.
- New parsers (`lib/src/parser/`):
  - `qrc.dart` — QRC XML parser (per-word timings, interlude markers).
  - `krc.dart` — KRC plaintext parser with `[language]` romaji/translation
    lane handling.
  - `yrc.dart` — NetEase YRC word-timed parser.
- Expand `LyricsHttpClient` with a `send(LyricsHttpRequest)` API plus
  `LyricsHttpRequest` envelope (forward-compatible with HTTP/2 transports).
- `LyricsProvider` gains a nullable `searchSongList(SearchQuery)` hook so the
  album/playlist path is opt-in.
- `LyricFinder` adds a TTL-cached `searchSongs` and a `fetchLyrics(song)`
  waterfall that walks providers in priority order.
- New exceptions: `LyricsDecryptError`, `LyricsSignError`,
  `LyricsRateLimitedException`.
- Tests: crypto primitives, QRC/KRC/YRC parsers, Kugou provider stub,
  HTTP client envelope. 59 tests pass; `dart analyze` is clean.

## 0.1.0

- Initial scaffold.
- Core data models: `Source`, `SearchType`, `LyricsFormat`, `Language`,
  `LyricsType`, `SongInfo`, `SongListInfo`, `LyricInfo`, `SearchInfo`,
  `Artist`, `LyricsWord`, `LyricsLine`, `LyricsData`, `FSLyrics*`, `Lyrics`,
  `FSLyrics`, `APIResultList`.
- `LyricsHttpClient` abstraction with `package:http` implementation.
- `LyricsProvider` interface (search / getLyricsList / getLyrics).
- LRCLIB provider as the first concrete reference implementation.
- GPL-3.0-only license inherited from upstream LDDC.
