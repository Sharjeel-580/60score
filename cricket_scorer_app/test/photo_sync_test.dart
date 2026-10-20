// Unit tests for PhotoSync pure helpers (hash, compression, JSON strip).
// The Firestore push/pull paths are integration-tested on-device; they
// swallow all errors and are never exercised here.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:cricket_scorer_app/photo_sync.dart';

Uint8List _testJpeg(int w, int h) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(30, 120, 200));
  return img.encodeJpg(image, quality: 95);
}

void main() {
  group('PhotoSync.hashBytes', () {
    test('is stable for the same bytes', () {
      final a = utf8.encode('player-photo-bytes');
      expect(PhotoSync.hashBytes(a), PhotoSync.hashBytes(a));
    });

    test('differs for different bytes', () {
      expect(
        PhotoSync.hashBytes(utf8.encode('photo-a')),
        isNot(PhotoSync.hashBytes(utf8.encode('photo-b'))),
      );
    });

    test('returns 16 lowercase hex characters', () {
      final h = PhotoSync.hashBytes(utf8.encode('x'));
      expect(h.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(h), isTrue);
    });
  });

  group('PhotoSync.compressPhoto', () {
    test('shrinks a large image to at most 512 on the longest side', () {
      final src = _testJpeg(1024, 768);
      final out = PhotoSync.compressPhoto(src);
      expect(out, isNotNull);
      final back = img.decodeImage(out!);
      expect(back, isNotNull);
      expect(back!.width, PhotoSync.maxDimension);
      expect(back.height, lessThanOrEqualTo(PhotoSync.maxDimension));
    });

    test('leaves a small image unchanged in size', () {
      final src = _testJpeg(200, 100);
      final out = PhotoSync.compressPhoto(src);
      final back = img.decodeImage(out!);
      expect(back!.width, 200);
      expect(back.height, 100);
    });

    test('returns null for bytes that are not an image', () {
      expect(
        PhotoSync.compressPhoto(utf8.encode('definitely not an image')),
        isNull,
      );
    });
  });

  group('PhotoSync.stripPhotos', () {
    test('blanks a record photo without mutating the input', () {
      final input = {'id': 'p1', 'photoBase64': 'AAAA', 'name': 'Ali'};
      final stripped = PhotoSync.stripPhotos(input);
      expect(stripped['photoBase64'], '');
      expect(stripped['name'], 'Ali');
      expect(input['photoBase64'], 'AAAA'); // input untouched
    });

    test('blanks nested team player photos', () {
      final input = {
        'id': 't1',
        'players': [
          {'id': 'p1', 'photoBase64': 'AAAA'},
          {'id': 'p2'},
        ],
      };
      final stripped = PhotoSync.stripPhotos(input);
      final players = stripped['players'] as List;
      expect((players[0] as Map)['photoBase64'], '');
      expect((players[1] as Map).containsKey('photoBase64'), isFalse);
    });

    test('handles maps with no photo fields', () {
      final input = {'id': 't2', 'name': 'Team'};
      expect(PhotoSync.stripPhotos(input)['name'], 'Team');
    });
  });
}
