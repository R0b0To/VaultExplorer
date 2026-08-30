import 'dart:io';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Full-screen viewer for a real image file, with swipe between the other
/// images in the same folder and pinch-to-zoom on each page.
///
/// Kept intentionally simple and separate from the vault's
/// `MediaViewerScreen`: that screen's complexity (playlist gestures,
/// video/audio playback, hybrid PDF routing) exists to serve decrypted
/// container content streamed through native code. A real on-disk image
/// just needs `Image.file` -- no decrypt round-trip, no container.
class LocalImageViewerScreen extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const LocalImageViewerScreen({
    super.key,
    required this.imagePaths,
    required this.initialIndex,
  });

  @override
  State<LocalImageViewerScreen> createState() => _LocalImageViewerScreenState();
}

class _LocalImageViewerScreenState extends State<LocalImageViewerScreen> {
  static const _api = VaultExplorerApi();

  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    final ok = await _api.shareLocalFiles([widget.imagePaths[_index]]);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.filesShareFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.imagePaths[_index].split('/').last,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: context.l10n.filesShare,
            onPressed: _share,
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.imagePaths.length,
        onPageChanged: (i) => setState(() => _index = i),
        itemBuilder: (context, i) => InteractiveViewer(
          minScale: 1.0,
          maxScale: 5.0,
          child: Center(
            child: Image.file(
              File(widget.imagePaths[i]),
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => const Icon(
                Icons.broken_image_rounded,
                color: Colors.white54,
                size: 64,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
