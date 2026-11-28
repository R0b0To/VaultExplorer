import 'dart:io' show Platform;
import 'dart:math' as math;

/// Whether this runs on a computer (as opposed to Android / iOS).
bool get isDesktopPlatform => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

/// How many video thumbnails a desktop makes at once.
///
/// A phone's few media codecs are why the shared tiers allow only 1-2 video thumbnails at a time. On a computer a video
/// thumbnail is the engine decoding one keyframe (see desktop_native_thumbnails.dart), most of it waiting on the vault
/// read, and the machine has the cores: half of them, at least 2 and at most 4. The thumbnail pool keeps room for image
/// tiles (it has `cores - 1` workers, up to 8), so videos cannot take all of it.
int desktopVideoThumbnailSlots({int? cores}) =>
    math.max(2, math.min((cores ?? Platform.numberOfProcessors) ~/ 2, 4));
