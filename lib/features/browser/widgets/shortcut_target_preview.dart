import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/api/vault_file_io_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// Resolves a Cryptomator symbolic link (and any links it points to) without
/// ever allowing the result to escape the current vault.
Future<String?> resolveShortcutTargetPath({
  required VaultFileIoApi fileIoApi,
  required MountedContainer container,
  required String linkPath,
}) async {
  var currentPath = p.posix.normalize(linkPath);
  final visited = <String>{};
  var followedLink = false;

  for (var hop = 0; hop < 40; hop++) {
    if (!visited.add(currentPath)) return null;
    final target = await fileIoApi.readVaultSymlink(container, currentPath);
    if (target == null || target.isEmpty) {
      return followedLink ? currentPath : null;
    }
    followedLink = true;
    // Absolute targets are deliberately rejected. Relative targets are
    // resolved from the link's containing directory and confined to the vault.
    if (p.posix.isAbsolute(target)) return null;
    final resolved = p.posix.normalize(
      p.posix.join(p.posix.dirname(currentPath), target),
    );
    if (resolved == '..' ||
        resolved.startsWith('../') ||
        p.posix.isAbsolute(resolved)) {
      return null;
    }
    currentPath = resolved;
  }
  return null;
}

typedef ShortcutTargetPreviewBuilder = Widget Function(
  BuildContext context,
  String targetPath,
  String targetName,
);

/// Small async adapter used by list, grid and masonry tiles to render the
/// same file-type presentation as the shortcut's resolved target.
class ShortcutTargetPreview extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String linkPath;
  final Widget fallback;
  final ShortcutTargetPreviewBuilder builder;

  const ShortcutTargetPreview({
    super.key,
    required this.container,
    required this.linkPath,
    required this.fallback,
    required this.builder,
  });

  @override
  ConsumerState<ShortcutTargetPreview> createState() =>
      _ShortcutTargetPreviewState();
}

class _ShortcutTargetPreviewState
    extends ConsumerState<ShortcutTargetPreview> {
  late Future<String?> _targetPath;

  @override
  void initState() {
    super.initState();
    _targetPath = _resolve();
  }

  @override
  void didUpdateWidget(covariant ShortcutTargetPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.linkPath != widget.linkPath ||
        oldWidget.container.volId != widget.container.volId) {
      _targetPath = _resolve();
    }
  }

  Future<String?> _resolve() => resolveShortcutTargetPath(
    fileIoApi: ref.read(vaultFileIoApiProvider),
    container: widget.container,
    linkPath: widget.linkPath,
  );

  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
    future: _targetPath,
    builder: (context, snapshot) {
      final targetPath = snapshot.data;
      if (targetPath == null) return widget.fallback;
      return widget.builder(
        context,
        targetPath,
        p.posix.basename(targetPath),
      );
    },
  );
}
