import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_router.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/viewer/pdf_viewer_lock_controller.dart';

class PdfViewerScreen extends ConsumerWidget {
  final MountedContainer container;
  final String filePath;
  const PdfViewerScreen({
    super.key,
    required this.container,
    required this.filePath,
  });
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isContainerLocked = ref.watch(pdfViewerLockProvider(container.volId));
    final fileName = filePath.split('/').last;
    return PdfViewerRouter(
      container: container,
      pdfPath: filePath,
      title: fileName,
      isLocked: isContainerLocked,
    );
  }
}
