/// What the gallery filter knows about one photo beyond its name, size and
/// file date: reads from its media database, read here from
/// the file's own header (EXIF and XMP) because a vault has no media database.
///
/// Every field is optional: most files carry only some of them, and files of a
/// type that is not parsed (videos, HEIC) carry none.
class GalleryMeta {
  const GalleryMeta({
    this.takenSecs,
    this.latitude,
    this.longitude,
    this.make,
    this.model,
    this.tags = const [],
    this.rating,
    this.width,
    this.height,
  });

  /// Nothing known (also what is stored for files that were looked at and had
  /// nothing, so they are not read again).
  static const GalleryMeta empty = GalleryMeta();

  /// When the photo was taken, as the camera's wall clock: the EXIF date has
  /// no time zone, so it is kept as "seconds since epoch of that wall-clock
  /// time read as UTC". Read it back with [takenWallClock].
  final int? takenSecs;
  final double? latitude;
  final double? longitude;
  final String? make;
  final String? model;

  /// Keywords (XMP `dc:subject`, digiKam tags), as written.
  final List<String> tags;

  /// XMP `xmp:Rating`, 1..5 (0 and "rejected" are not kept).
  final int? rating;

  /// Pixel size as shown (already turned by the EXIF orientation), when the
  /// file header says.
  final int? width;
  final int? height;

  bool get isEmpty =>
      takenSecs == null &&
      latitude == null &&
      make == null &&
      model == null &&
      tags.isEmpty &&
      rating == null &&
      width == null;

  bool get hasLocation => latitude != null && longitude != null;

  /// The moment of [takenSecs] as a date without a zone (year, month, day,
  /// hour... exactly as the camera wrote them).
  DateTime? get takenWallClock => takenSecs == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(takenSecs! * 1000, isUtc: true);

  /// "Make Model" without repeating the make when the model already starts
  /// with it ("Canon" + "Canon EOS R5" is "Canon EOS R5").
  String? get camera {
    final mk = make?.trim() ?? '';
    final md = model?.trim() ?? '';
    if (mk.isEmpty && md.isEmpty) return null;
    if (mk.isEmpty) return md;
    if (md.isEmpty) return mk;
    return md.toLowerCase().contains(mk.toLowerCase()) ? md : '$mk $md';
  }

  /// The place cell of this photo: its coordinates rounded to
  /// [placeCellDegrees]. Photos of the same cell are "the same place".
  ///
  /// There is no network in this app, so a name for the cell (a city) would
  /// need an offline gazetteer; until one is added the cell is labelled with
  /// its coordinates (see [placeLabel]).
  String? get placeCell {
    if (!hasLocation) return null;
    final lat = (latitude! / placeCellDegrees).round();
    final lon = (longitude! / placeCellDegrees).round();
    return '$lat,$lon';
  }

  /// Size of a place cell in degrees (0.1 is about 11 km of latitude).
  static const double placeCellDegrees = 0.1;

  /// A readable label for a [placeCell]: its centre, like `48.9°N 2.4°E`.
  static String placeLabel(String cell) {
    final parts = cell.split(',');
    if (parts.length != 2) return cell;
    final lat = int.tryParse(parts[0]);
    final lon = int.tryParse(parts[1]);
    if (lat == null || lon == null) return cell;
    final la = lat * placeCellDegrees;
    final lo = lon * placeCellDegrees;
    String fmt(double v, String pos, String neg) =>
        '${v.abs().toStringAsFixed(1)}°${v >= 0 ? pos : neg}';
    return '${fmt(la, 'N', 'S')} ${fmt(lo, 'E', 'W')}';
  }

  List<Object?> toJson() => [
    takenSecs,
    latitude,
    longitude,
    make,
    model,
    tags,
    rating,
    width,
    height,
  ];

  static GalleryMeta? tryFromJson(Object? raw) {
    if (raw is! List || raw.length != 9) return null;
    final taken = raw[0];
    final lat = raw[1];
    final lon = raw[2];
    final make = raw[3];
    final model = raw[4];
    final tags = raw[5];
    final rating = raw[6];
    final width = raw[7];
    final height = raw[8];
    if (taken != null && taken is! int) return null;
    if (lat != null && lat is! num) return null;
    if (lon != null && lon is! num) return null;
    if (make != null && make is! String) return null;
    if (model != null && model is! String) return null;
    if (tags is! List) return null;
    if (rating != null && rating is! int) return null;
    if (width != null && width is! int) return null;
    if (height != null && height is! int) return null;
    return GalleryMeta(
      takenSecs: taken as int?,
      latitude: (lat as num?)?.toDouble(),
      longitude: (lon as num?)?.toDouble(),
      make: make as String?,
      model: model as String?,
      tags: [
        for (final t in tags)
          if (t is String) t,
      ],
      rating: rating as int?,
      width: width as int?,
      height: height as int?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GalleryMeta &&
      other.takenSecs == takenSecs &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.make == make &&
      other.model == model &&
      other.rating == rating &&
      other.width == width &&
      other.height == height &&
      _sameList(other.tags, tags);

  @override
  int get hashCode => Object.hash(
    takenSecs,
    latitude,
    longitude,
    make,
    model,
    rating,
    width,
    height,
    Object.hashAll(tags),
  );

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
