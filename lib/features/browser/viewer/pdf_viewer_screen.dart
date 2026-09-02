import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
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
    final fileName = filePath.split('/').last;

    if (container.isLocalStorage) {
      final fullPath =
          p.isAbsolute(filePath) ? filePath : p.join(container.uri, filePath);
      return FutureBuilder<String?>(
        future: ref.read(vaultLocalShareApiProvider).getLocalFileUri(fullPath),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            final cs = Theme.of(context).colorScheme;
            return Scaffold(
              appBar: AppBar(
                title: Text(fileName, overflow: TextOverflow.ellipsis),
              ),
              body: Container(
                color: cs.surface,
                child: const Center(
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }
          final localUri = snapshot.data;
          return PdfViewerRouter(
            localUri: localUri,
            title: fileName,
            isLocked: false,
          );
        },
      );
    }

    final isContainerLocked = ref.watch(pdfViewerLockProvider(container.volId));
    return PdfViewerRouter(
      container: container,
      pdfPath: filePath,
      title: fileName,
      isLocked: isContainerLocked,
    );
  }
}
