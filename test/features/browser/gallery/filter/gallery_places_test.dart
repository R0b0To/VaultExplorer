import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_meta.dart';
import 'package:vaultexplorer/features/browser/gallery/filter/gallery_places.dart';

void main() {
  // The real bundled list: these tests also guard `scripts/build_gazetteer.py`
  // and the file it produced.
  final resolver = GalleryPlaceResolver.fromBytes(File('assets/geo/cities.bin').readAsBytesSync());

  group('GalleryPlaceResolver', () {
    test('names the city a photo was taken in', () {
      final p = resolver.nearest(48.8566, 2.3522)!;
      expect(p.label, 'Paris, France');
      expect(p.isCity, isTrue);
    });

    test('a photo in a suburb is filed under the nearest city', () {
      expect(resolver.nearest(48.9, 2.45)?.label.endsWith('France'), isTrue);
    });

    test('US cities carry their state', () {
      expect(resolver.nearest(40.7128, -74.0060)!.label.endsWith(', NY, United States'), isTrue);
    });

    test('nothing within range in the middle of the ocean or desert', () {
      expect(resolver.nearest(0, -30), isNull);
      expect(resolver.nearest(-45, -140), isNull);
      expect(resolver.nearest(22, 12), isNull);
    });

    test('works across the antimeridian and at the poles', () {
      expect(resolver.nearest(-18.14, 178.44)?.label.endsWith('Fiji'), isTrue);
      expect(resolver.nearest(-18.14, -181.56), isNull); // out of range input
      expect(resolver.nearest(90, 0), isNull);
      expect(resolver.nearest(-90, 0), isNull);
    });

    test('rejects other files', () {
      expect(() => GalleryPlaceResolver.fromBytes(Uint8List(20)), throwsA(isA<FormatException>()));
    });
  });

  group('galleryPlaceOf', () {
    const paris = GalleryMeta(latitude: 48.8566, longitude: 2.3522);
    const nowhere = GalleryMeta(latitude: 0.0, longitude: -30.0);

    test('city when one is close, coordinates when not, null without GPS', () {
      expect(galleryPlaceOf(paris, resolver)!.label, 'Paris, France');
      final far = galleryPlaceOf(nowhere, resolver)!;
      expect(far.isCity, isFalse);
      expect(far.label, '0.0°N 30.0°W');
      expect(galleryPlaceOf(GalleryMeta.empty, resolver), isNull);
    });

    test('before the list is loaded places are coordinates', () {
      expect(galleryPlaceOf(paris, null)!.isCity, isFalse);
    });
  });
}
