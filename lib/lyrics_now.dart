// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only
//
// Public API surface for the `lyrics_now` library.
//
// All consumers should import this file (`package:lyrics_now/lyrics_now.dart`)
// rather than the implementation files under `lib/src/`.

export 'src/exceptions.dart';
export 'src/cache.dart';
export 'src/http_client.dart';
export 'src/finder.dart';

export 'src/models/api_result_list.dart';
export 'src/models/artist.dart';
export 'src/models/info_base.dart';
export 'src/models/language.dart';
export 'src/models/lyric_info.dart';
export 'src/models/lyrics.dart';
export 'src/models/lyrics_format.dart';
export 'src/models/lyrics_models.dart';
export 'src/models/lyrics_type.dart';
export 'src/models/search_info.dart';
export 'src/models/search_type.dart';
export 'src/models/song_info.dart';
export 'src/models/song_list_info.dart';
export 'src/models/source.dart';

export 'src/parser/krc.dart';
export 'src/parser/lrc.dart';
export 'src/parser/qrc.dart';
export 'src/parser/yrc.dart';

export 'src/provider/lyrics_provider.dart';
export 'src/provider/query.dart';

export 'src/providers/kg_provider.dart';
export 'src/providers/lrclib_provider.dart';
export 'src/providers/ne_provider.dart';
export 'src/providers/qm_provider.dart';

export 'src/crypto/aes_ecb.dart';
export 'src/crypto/des_ede.dart';
export 'src/crypto/eapi.dart';
export 'src/crypto/krc.dart';
export 'src/crypto/qmc1.dart';
export 'src/crypto/qrc.dart';
export 'src/crypto/kugou_sign.dart';

export 'src/matcher/song_matcher.dart';

export 'src/persistent_cache/store.dart';
export 'src/persistent_cache/json_file_cache_store.dart';

export 'src/converter/convert.dart';
export 'src/converter/lrc_converter.dart';
export 'src/converter/srt_converter.dart';
