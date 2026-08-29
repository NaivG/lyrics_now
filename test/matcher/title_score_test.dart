import 'package:lyrics_now/src/matcher/title_score.dart';
import 'package:test/test.dart';

void main() {
  group('calculateTitleScore', () {
    test('identical titles', () {
      expect(
        calculateTitleScore('connect', 'connect'),
        greaterThanOrEqualTo(90.0),
      );
    });

    test('version tag stripped', () {
      final score = calculateTitleScore('Rising Hope (TV size)', 'Rising Hope');
      expect(score, greaterThanOrEqualTo(80.0));
    });

    test('karaoke tag', () {
      final score = calculateTitleScore(
        'Adrenaline!!! -Karaoke',
        'Adrenaline!!!',
      );
      expect(score, greaterThanOrEqualTo(80.0));
    });

    test('completely different', () {
      expect(calculateTitleScore('abc', 'xyz'), lessThan(20.0));
    });

    test('empty strings', () {
      expect(calculateTitleScore('', ''), 100.0);
      expect(calculateTitleScore('test', ''), 0.0);
    });

    test('same title same score', () {
      final score = calculateTitleScore('crossing field', 'crossing field');
      expect(score, greaterThanOrEqualTo(90.0));
    });
  });
}
