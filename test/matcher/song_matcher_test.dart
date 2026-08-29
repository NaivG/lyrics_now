import 'package:lyrics_now/src/matcher/song_matcher.dart';
import 'package:lyrics_now/src/models/artist.dart';
import 'package:lyrics_now/src/models/song_info.dart';
import 'package:lyrics_now/src/models/source.dart';
import 'package:test/test.dart';

SongInfo _song({String? title, String? artist, String? album, int? duration}) =>
    SongInfo(
      source: Source.qm,
      title: title,
      artist: artist is String ? Artist(artist) : null,
      album: album,
      duration: duration,
    );

void main() {
  group('SongMatcher', () {
    late SongMatcher matcher;

    setUp(() {
      matcher = const SongMatcher();
    });

    test('identical match scores high', () {
      final target = _song(title: 'connect', artist: 'ClariS');
      final candidates = [_song(title: 'connect', artist: 'ClariS')];
      final results = matcher.findMatches(target, candidates);
      expect(results, hasLength(1));
      expect(results.first.score, greaterThan(90.0));
    });

    test('different title scores low', () {
      final target = _song(title: 'connect', artist: 'ClariS');
      final candidates = [_song(title: 'abc', artist: 'xyz')];
      final results = matcher.findMatches(target, candidates);
      expect(results, isEmpty);
    });

    test('duration mismatch filtered out', () {
      final matcher = const SongMatcher(durationToleranceMs: 4000);
      final target = _song(title: 'test', artist: 'A', duration: 200000);
      final candidates = [_song(title: 'test', artist: 'A', duration: 180000)];
      expect(target.duration, isNotNull);
      expect(candidates.first.duration, isNotNull);
      final diff = (target.duration! - candidates.first.duration!).abs();
      expect(diff, greaterThan(4000));
      final results = matcher.findMatches(target, candidates);
      expect(results, isEmpty);
    });

    test('scored empty candidates', () {
      final target = _song(title: 'test', artist: 'A');
      final results = matcher.findMatches(target, []);
      expect(results, isEmpty);
    });
  });
}
