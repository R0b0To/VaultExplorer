import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_base.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// PDF viewer used inside the vault file-browser.
///
/// This is a thin wrapper around [PdfViewerBase] that adds vault-specific
/// behaviour: the native view receives `volId` + `pdfPath` as creation
/// params, and the screen blacks out when the container is locked
/// mid-session.
class PdfViewerScreen extends StatefulWidget {
  final MountedContainer container;
  final String filePath;

  const PdfViewerScreen({
    super.key,
    required this.container,
    required this.filePath,
  });

  @override
  State<PdfViewerScreen> createState() => _PdfViewerScreenState();
}

class _PdfViewerScreenState extends State<PdfViewerScreen> {
  bool _isContainerLocked = false;

  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
  }

  @override
  void dispose() {
    VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    super.dispose();
  }

  String get _fileName => widget.filePath.split('/').last;

  @override
  Widget build(BuildContext context) {
    return PdfViewerBase(
      creationParams: {
        'volId': widget.container.volId,
        'pdfPath': widget.filePath,
      },
      title: _fileName,
      isLocked: _isContainerLocked,
    );
  }
}