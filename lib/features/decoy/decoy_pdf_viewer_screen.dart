import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/services/disguise_mode_api.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_base.dart';
import 'package:vaultexplorer/data/services/discrete_mode_repository.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

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
  String? _localPath;

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
    _resolveUri();
  }

  Future<void> _resolveUri() async {
    if (widget.uri.startsWith('content://')) {
      final path = await disguiseModeApi.cacheContentUri(widget.uri);
      if (mounted && path != null) {
        setState(() {
          _localPath = path;
        });
      }
    } else {
      setState(() {
        _localPath = widget.uri;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_localPath == null) {
      return Scaffold(
        appBar: AppBar(
          title: HiddenVaultTrigger(child: Text(widget.displayName)),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    
    return PdfViewerBase(
      localUri: _localPath,
      title: widget.displayName,
      titleBuilder: (child) => HiddenVaultTrigger(child: child),
      pageCounterBuilder: (child) => HiddenVaultTrigger(child: child),
      searchConfig: const PdfSearchConfig.decoy(),
    );
  }
}