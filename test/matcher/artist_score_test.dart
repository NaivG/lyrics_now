import 'package:lyrics_now/src/matcher/artist_score.dart';
import 'package:test/test.dart';

void main() {
  group('artistStr2List', () {
    test('simple artist name', () {
      final r = artistStr2List('LiSA');
      expect(r.artists, ['lisa']);
      expect(r.groups, isEmpty);
    });

    test('Japanese CV notation', () {
      final r = artistStr2List('LiSA( CV:LiSA )');
      expect(r.groups, ['lisa']);
      expect(r.artists, ['lisa']);
    });

    test('feat. artist', () {
      final r = artistStr2List('Aimer / TK from 凛として時雨');
      expect(r.artists, ['aimer', 'tk from 凛として時雨']);
    });
  });

  group('calculateArtistScore', () {
    test('identical artists', () {
      expect(calculateArtistScore('LiSA', 'LiSA'), 100.0);
    });

    test('completely different', () {
      expect(calculateArtistScore('LiSA', 'Taylor Swift'), lessThan(50.0));
    });

    test('empty strings', () {
      expect(calculateArtistScore('', ''), 100.0);
      expect(calculateArtistScore('LiSA', ''), 0.0);
    });

    test('same artist different format', () {
      final score = calculateArtistScore('ClariS', 'ClariS');
      expect(score, 100.0);
    });
  });
}
