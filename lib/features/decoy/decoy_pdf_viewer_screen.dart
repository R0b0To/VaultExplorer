import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_base.dart';
import 'package:vaultexplorer/data/services/discrete_mode_repository.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

/// PDF viewer used inside the Discrete Mode decoy reader.
///
/// This is a thin wrapper around [PdfViewerBase] that adds decoy-specific
/// behaviour: the native view receives a `localUri` creation param, the
/// title and page-counter are wrapped in [HiddenVaultTrigger], a print
/// action is added, and the file is recorded in [DiscreteModeRepository].
class DecoyPdfViewerScreen extends StatefulWidget {
  final String uri;
  final String displayName;

  const DecoyPdfViewerScreen({
    super.key,
    required this.uri,
    required this.displayName,
  });

  @override
  State<DecoyPdfViewerScreen> createState() => _DecoyPdfViewerScreenState();
}

class _DecoyPdfViewerScreenState extends State<DecoyPdfViewerScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(
      DiscreteModeRepository.recordOpened(
        DecoyRecentFile(
          uri: widget.uri,
          displayName: widget.displayName,
          openedAt: DateTime.now(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PdfViewerBase(
      creationParams: {'localUri': widget.uri},
      title: widget.displayName,
      titleBuilder: (child) => HiddenVaultTrigger(child: child),
      pageCounterBuilder: (child) => HiddenVaultTrigger(child: child),
      searchConfig: const PdfSearchConfig.decoy(),
    );
  }
}