import 'package:lyrics_now/src/models/artist.dart';
import 'package:lyrics_now/src/models/song_info.dart';
import 'package:lyrics_now/src/models/source.dart';
import 'package:test/test.dart';

void main() {
  group('SongInfo serialization', () {
    test('round-trip', () {
      final original = SongInfo(
        source: Source.qm,
        title: 'connect',
        artist: Artist('ClariS'),
        album: 'connect',
        duration: 250000,
        id: '123',
        mid: '456',
        hash: '789',
      );
      final json = original.toJson();
      final restored = SongInfo.fromJson(json);
      expect(restored, original);
    });

    test('minimal fields', () {
      final original = SongInfo(source: Source.lrclib, title: 'test');
      final json = original.toJson();
      final restored = SongInfo.fromJson(json);
      expect(restored.source, Source.lrclib);
      expect(restored.title, 'test');
      expect(restored.artist, isNull);
    });

    test('missing source defaults to multi', () {
      final restored = SongInfo.fromJson({'title': 'x'});
      expect(restored.source, Source.multi);
    });
  });
}
