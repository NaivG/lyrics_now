import 'package:lyrics_now/src/matcher/text_similarity.dart';
import 'package:test/test.dart';

void main() {
  group('textDifference', () {
    test('identical strings', () {
      expect(textDifference('hello', 'hello'), 1.0);
    });

    test('completely different', () {
      expect(textDifference('abc', 'xyz'), 0.0);
    });

    test('partial overlap', () {
      final score = textDifference('kud wafter', 'kud wafter');
      expect(score, 1.0);
    });

    test('empty strings', () {
      expect(textDifference('', ''), 1.0);
      expect(textDifference('a', ''), 0.0);
      expect(textDifference('', 'a'), 0.0);
    });

    test('similar but not identical', () {
      final score = textDifference('hello', 'hallo');
      expect(score, greaterThan(0.0));
      expect(score, lessThan(1.0));
    });
  });
}
