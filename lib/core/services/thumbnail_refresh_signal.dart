import 'package:flutter/foundation.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Announces that the bytes behind one file path have changed.
///
/// Thumbnail widgets are intentionally stateful and keep decoded bytes while
/// their tile remains mounted. Clearing the disk/memory cache alone is not
/// enough: a live [AsyncThumbnailLoader] would continue painting its old
/// provider state. This path-scoped signal tells only loaders for the changed
/// file to discard that state and fetch again.
class ThumbnailRefreshSignal {
  ThumbnailRefreshSignal._();

  static int _generation = 0;

  static final ValueNotifier<ThumbnailInvalidation?> invalidation =
      ValueNotifier<ThumbnailInvalidation?>(null);

  static void invalidate(MountedContainer container, String filePath) {
    invalidation.value = ThumbnailInvalidation(
      volId: container.volId,
      mountedAtMillis: container.mountedAt.millisecondsSinceEpoch,
      filePath: filePath,
      generation: ++_generation,
    );
  }
}

class ThumbnailInvalidation {
  const ThumbnailInvalidation({
    required this.volId,
    required this.mountedAtMillis,
    required this.filePath,
    required this.generation,
  });

  final int volId;
  final int mountedAtMillis;
  final String filePath;
  final int generation;
}