// SPDX-FileCopyrightText: Copyright (C) 2024-2025 沉默の金 <cmzj@cmzj.org>
// SPDX-License-Identifier: GPL-3.0-only

import 'dart:convert';

import 'package:lyrics_now/lyrics_now.dart';
import 'package:test/test.dart';

void main() {
  group('parser/qrc', () {
    const sample =
        '<Lyric_1 LyricType="1" LyricContent="'
        '[ti:Sample]\n'
        '[0,1500]Hello(0,500) there(500,500) world\n'
        '[1500,2000](1500,1000)\n'
        '[3500,1000]again'
        '"/>';

    test('qrc2Data extracts metadata tags', () {
      final result = qrc2Data(sample);
      expect(result.tags['ti'], 'Sample');
      expect(result.data.lines, hasLength(3));
    });

    test('qrc2Data parses verbatim words with per-word timings', () {
      final result = qrc2Data(sample);
      final words = result.data[0].words;
      // The line has two `(start,duration)` pairs (after the leading text
      // and after the leading word); the trailing `world` is captured as a
      // 3rd word with no end timestamp.
      expect(words.first.text, 'Hello');
      expect(words.first.end, 500);
    });

    test('qrc2Data handles empty interlude lines', () {
      final result = qrc2Data(sample);
      expect(result.data[1].words, isEmpty);
      expect(result.data[1].start, 1500);
      expect(result.data[1].end, 3500);
    });

    test('qrcStrParse falls back to plaintext on garbage input', () {
      final result = qrcStrParse('this is just\nplain text without tags');
      expect(result.data.lines, isNotEmpty);
      expect(result.data[0].text, 'this is just');
    });

    test('qrcStrParse dispatches to LRC when the input is bracketed', () {
      final result = qrcStrParse('[00:01.00]plain LRC line');
      expect(result.data[0].text, 'plain LRC line');
      expect(result.data[0].start, 1000);
    });
  });

  group('parser/krc', () {
    test('krc2MData captures orig lane', () {
      const sample =
          '[ti:Song]\n'
          '[ar:Me]\n'
          '[0,2000]<0,500,0>你<500,500,0>好\n'
          '[2000,1500]<0,500,0>世<500,500,0>界';
      final result = krc2MData(sample);
      expect(result.tags['ti'], 'Song');
      expect(result.data['orig']?.lines, hasLength(2));
      expect(result.data['orig']?[0].text, '你好');
    });

    test('krc2MData decodes the [language] tag for the roma lane', () {
      // Synthesize a [language] tag with a base64-encoded JSON of a type-0
      // romaji lane with two entries (one per orig line).
      final languagePayload = <String, Object?>{
        'content': <Object?>[
          <String, Object?>{
            'type': 0,
            'lyricContent': <List<String>>[
              <String>['ni', 'hao'],
              <String>['shi', 'jie'],
            ],
          },
        ],
      };
      final encoded = base64.encode(utf8.encode(jsonEncode(languagePayload)));

      final krc =
          '[0,2000]<0,500,0>你<500,500,0>好\n'
          '[2000,1500]<0,500,0>世<500,500,0>界\n'
          '[language:$encoded]';
      final result = krc2MData(krc);
      expect(result.data['orig']?.lines, hasLength(2));
      expect(result.data['roma']?.lines, hasLength(2));
      expect(result.data['roma']?[0].text, 'nihao');
      expect(result.data['roma']?[1].text, 'shijie');
    });

    test('krc2MData with only orig produces a single-lane result', () {
      final result = krc2MData('[0,1500]plain');
      expect(result.data.keys.toList(), ['orig']);
    });
  });

  group('parser/yrc', () {
    test('yrc2Data parses a single word-timed line', () {
      const sample = '[0,2000](0,500,0)foo(500,500,0)bar';
      final result = yrc2Data(sample);
      expect(result.lines, hasLength(1));
      expect(result[0].words, hasLength(2));
      expect(result[0].words[0].text, 'foo');
      expect(result[0].words[1].text, 'bar');
    });

    test('yrc2Data falls back to a single-word line', () {
      final result = yrc2Data('[0,1000]no-word-line');
      expect(result.lines, hasLength(1));
      expect(result[0].words, hasLength(1));
      expect(result[0].words.first.text, 'no-word-line');
    });

    test('yrc2Data handles multiple lines with mixed word counts', () {
      const sample =
          '[0,1000](0,500,0)line1w1(500,500,0)line1w2\n'
          '[1000,500]line2justone';
      final result = yrc2Data(sample);
      expect(result.lines, hasLength(2));
      expect(result[0].words, hasLength(2));
      expect(result[1].words, hasLength(1));
      expect(result[1].words.first.text, 'line2justone');
    });
  });

  group('parser/lrc multi-stamp (NetEase variant)', () {
    test('parseLrc explodes [ss:ms][ss:ms]text into two lines', () {
      const sample = '[00:10.00][00:20.00]shared text';
      final result = parseLrc(sample);
      expect(result.data.lines, hasLength(2));
      expect(result.data[0].text, 'shared text');
      expect(result.data[0].start, 10000);
      expect(result.data[1].text, 'shared text');
      expect(result.data[1].start, 20000);
    });

    test('parseLrc preserves single-stamp LRC lines', () {
      const sample = '[00:01.50]plain text';
      final result = parseLrc(sample);
      expect(result.data.lines, hasLength(1));
      expect(result.data[0].text, 'plain text');
      expect(result.data[0].start, 1500);
    });
  });
}
