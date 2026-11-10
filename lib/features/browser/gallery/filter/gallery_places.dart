import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'gallery_meta.dart';

/// A place a photo is filed under: a city, or (far from any city) a coordinate
/// cell.
class GalleryPlace {
  const GalleryPlace(this.key, this.label);

  /// Stable identity: `c<geonameId>` for a city, `x<cell>` for a coordinate cell.
  final String key;

  /// What the person sees: "Paris, France", "Springfield, IL, United States",
  /// or "48.9°N 2.4°E".
  final String label;

  bool get isCity => key.startsWith('c');
}

/// Finds the city nearest to a position without any network: the cities live
/// in the bundled `assets/geo/cities.bin` (GeoNames, see
/// `scripts/build_gazetteer.py` for the format and how to rebuild it).
///
/// A position with no city within [maxDistanceKm] has no city: the caller falls
/// back to its coordinates (see [galleryPlaceOf]), so a photo taken far from
/// anywhere is not filed under a town it has nothing to do with.
class GalleryPlaceResolver {
  GalleryPlaceResolver._(
    this._bytes,
    this._countries,
    this._citiesAt,
    this._namesAt,
    this.cityCount,
    this._lat,
    this._lon,
    this._grid,
  );

  static const double maxDistanceKm = 25;
  static const int _stride = 17;
  static const double _kmPerDegree = 111.32;
  static const int _memoLimit = 100000;

  final ByteData _bytes;
  final List<String> _countries;
  final int _citiesAt;
  final int _namesAt;
  final int cityCount;
  final Int32List _lat; // degrees * 1e4
  final Int32List _lon;
  final Map<int, List<int>> _grid;
  final Map<int, GalleryPlace?> _memo = {};

  /// Parses the file. Throws [FormatException] when it is not a city file.
  factory GalleryPlaceResolver.fromBytes(Uint8List data) {
    if (data.length < 11 ||
        data[0] != 0x56 || // V
        data[1] != 0x58 || // X
        data[2] != 0x47 || // G
        data[3] != 0x43) {
      throw const FormatException('Not a city list');
    }
    final bd = ByteData.sublistView(data);
    if (bd.getUint8(4) != 1) throw const FormatException('Unknown city list version');
    final countryCount = bd.getUint16(5, Endian.little);
    final cityCount = bd.getUint32(7, Endian.little);

    var o = 11;
    final countries = <String>[];
    for (var i = 0; i < countryCount; i++) {
      final len = bd.getUint8(o + 2);
      countries.add(utf8.decode(Uint8List.sublistView(data, o + 3, o + 3 + len)));
      o += 3 + len;
    }
    final citiesAt = o;
    final namesAt = citiesAt + cityCount * _stride;
    if (namesAt > data.length) throw const FormatException('Truncated city list');

    final lat = Int32List(cityCount);
    final lon = Int32List(cityCount);
    final grid = <int, List<int>>{};
    for (var i = 0; i < cityCount; i++) {
      final at = citiesAt + i * _stride;
      lat[i] = bd.getInt32(at, Endian.little);
      lon[i] = bd.getInt32(at + 4, Endian.little);
      grid
          .putIfAbsent(_cellKey((lat[i] / 1e4).floor(), (lon[i] / 1e4).floor()), () => [])
          .add(i);
    }
    return GalleryPlaceResolver._(bd, countries, citiesAt, namesAt, cityCount, lat, lon, grid);
  }

  static int _cellKey(int latCell, int lonCell) => (latCell + 90) * 360 + ((lonCell + 180) % 360);

  /// The nearest city within [maxDistanceKm], or null.
  GalleryPlace? nearest(double latitude, double longitude) {
    final memoKey =
        (latitude * 1000).round() * 1000003 + (longitude * 1000).round();
    if (_memo.containsKey(memoKey)) return _memo[memoKey];
    final result = _search(latitude, longitude);
    if (_memo.length >= _memoLimit) _memo.clear();
    _memo[memoKey] = result;
    return result;
  }

  GalleryPlace? _search(double latitude, double longitude) {
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;
    final cosLat = math.max(0.01, math.cos(latitude * math.pi / 180));
    final latCell = latitude.floor();
    final lonCell = longitude.floor();
    final lonSpan = math.min(180, (maxDistanceKm / (_kmPerDegree * cosLat)).ceil());

    var best = -1;
    var bestD2 = double.infinity;
    for (var la = latCell - 1; la <= latCell + 1; la++) {
      if (la < -90 || la > 90) continue;
      for (var dl = -lonSpan; dl <= lonSpan; dl++) {
        final list = _grid[_cellKey(la, lonCell + dl)];
        if (list == null) continue;
        for (final i in list) {
          final dy = (latitude - _lat[i] / 1e4) * _kmPerDegree;
          var dLon = longitude - _lon[i] / 1e4;
          if (dLon > 180) dLon -= 360;
          if (dLon < -180) dLon += 360;
          final dx = dLon * _kmPerDegree * cosLat;
          final d2 = dx * dx + dy * dy;
          if (d2 < bestD2) {
            bestD2 = d2;
            best = i;
          }
        }
      }
    }
    if (best < 0 || bestD2 > maxDistanceKm * maxDistanceKm) return null;
    return _placeAt(best);
  }

  GalleryPlace _placeAt(int i) {
    final at = _citiesAt + i * _stride;
    final id = _bytes.getUint32(at + 8, Endian.little);
    final nameOffset = _bytes.getUint32(at + 12, Endian.little);
    final country = _countries[_bytes.getUint8(at + 16)];
    final p = _namesAt + nameOffset;
    final len = _bytes.getUint8(p);
    final name = utf8.decode(
      Uint8List.sublistView(_bytes, p + 1, p + 1 + len),
      allowMalformed: true,
    );
    return GalleryPlace('c$id', '$name, $country');
  }
}

/// The place of a photo: its nearest city when [resolver] knows one close by,
/// else its coordinate cell, or null when it has no GPS position.
GalleryPlace? galleryPlaceOf(GalleryMeta meta, GalleryPlaceResolver? resolver) {
  if (!meta.hasLocation) return null;
  final city = resolver?.nearest(meta.latitude!, meta.longitude!);
  if (city != null) return city;
  final cell = meta.placeCell!;
  return GalleryPlace('x$cell', GalleryMeta.placeLabel(cell));
}
