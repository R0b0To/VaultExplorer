import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_router.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

class PdfViewerScreen extends ConsumerStatefulWidget {
  final MountedContainer container;
  final String filePath;
  const PdfViewerScreen({
    super.key,
    required this.container,
    required this.filePath,
  });
  @override
  ConsumerState<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends ConsumerState<PdfViewerScreen> {
  bool _isContainerLocked = false;
  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    ref.read(vaultEngineEventsProvider).addContainerLockedListener(_onContainerLockedEvent);
  }

  @override
  void dispose() {
    ref.read(vaultEngineEventsProvider).removeContainerLockedListener(_onContainerLockedEvent);
    super.dispose();
  }

  String get _fileName => widget.filePath.split('/').last;

  @override
  Widget build(BuildContext context) {
    return PdfViewerRouter(
      container: widget.container,
      pdfPath: widget.filePath,
      title: _fileName,
      isLocked: _isContainerLocked,
    );
  }
}