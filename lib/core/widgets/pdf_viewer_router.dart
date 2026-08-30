import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart' show AppBannerTone;
import 'package:vaultexplorer/core/widgets/jetpack_pdf_viewer_view.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_base.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_router_controller.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

class PdfViewerRouter extends ConsumerStatefulWidget {
  final MountedContainer? container;
  final String? pdfPath;
  final String? localUri;
  final String title;
  final bool isLocked;

  const PdfViewerRouter({
    super.key,
    this.container,
    this.pdfPath,
    this.localUri,
    required this.title,
    this.isLocked = false,
  });

  @override
  ConsumerState<PdfViewerRouter> createState() => _PdfViewerRouterState();
}

class _PdfViewerRouterState extends ConsumerState<PdfViewerRouter> {
  // Tied to the native PlatformView instance, not domain data -- created
  // lazily and only ever touched while in jetpack mode.
  final _viewerKey = GlobalKey<JetpackPdfViewerViewState>();

  void _onNativeEditRequested() {
    showAppSnackBar(
      context,
      message: context.l10n.pdfViewerEditUnavailable,
      tone: AppBannerTone.info,
    );
  }

  Future<void> _toggleSearch() async {
    HapticFeedback.lightImpact();
    await _viewerKey.currentState?.toggleSearch();
  }

  void _printPdf() {
    unawaited(
      ref.read(vaultPdfApiProvider).printPdf(
        container: widget.container,
        fileName: widget.pdfPath,
        localUri: widget.localUri,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    final state = ref.watch(
      pdfViewerRouterControllerProvider(widget.container, widget.pdfPath, widget.localUri),
    );

    switch (state.mode) {
      case PdfViewerMode.probing:
        return _buildProbingScaffold(context);
      case PdfViewerMode.fallback:
        return PdfViewerBase(
          container: widget.container,
          pdfPath: widget.pdfPath,
          localUri: widget.localUri,
          title: widget.title,
          isLocked: widget.isLocked,
          onPrint: _printPdf,
        );
      case PdfViewerMode.jetpack:
        return _buildJetpackScaffold(context, state);
    }
  }

  Widget _buildProbingScaffold(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, overflow: TextOverflow.ellipsis),
      ),
      body: Container(
        color: cs.surface,
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      ),
    );
  }

  Widget _buildJetpackScaffold(BuildContext context, PdfViewerRouterState state) {
    final cs = Theme.of(context).colorScheme;
    final activeUri = state.contentUri;
    if (activeUri == null) {
      return _buildProbingScaffold(context);
    }
    final controller = ref.read(
      pdfViewerRouterControllerProvider(widget.container, widget.pdfPath, widget.localUri).notifier,
    );
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: cs.surface,
      body: SafeArea(
        top: false,
        bottom: false,
        child: Column(
          children: [
            _JetpackTopBar(
              title: widget.title,
              onSearch: state.jetpackLoaded ? _toggleSearch : null,
              onPrint: state.jetpackLoaded ? _printPdf : null,
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  JetpackPdfViewerView(
                    key: _viewerKey,
                    contentUri: activeUri,
                    onLoaded: controller.onJetpackLoaded,
                    onError: (_) => controller.onJetpackError(),
                    onEditRequested: _onNativeEditRequested,
                  ),
                  if (!state.jetpackLoaded)
                    Container(
                      color: cs.surface,
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(strokeWidth: 2.5),
                            const SizedBox(height: 16),
                            Text(context.l10n.pdfViewerLoadingDocument),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JetpackTopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onSearch;
  final VoidCallback? onPrint;

  const _JetpackTopBar({
    required this.title,
    this.onSearch,
    this.onPrint,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      color: cs.surface,
      padding: EdgeInsets.only(
        top: topInset + 4,
        bottom: 8,
        left: 8,
        right: 8,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            tooltip: context.l10n.backTooltip,
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).maybePop();
            },
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (onSearch != null)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: context.l10n.search,
              onPressed: onSearch!,
            ),
          if (onPrint != null)
            IconButton(
              icon: const Icon(Icons.print_rounded),
              tooltip: 'Print',
              onPressed: onPrint!,
            ),
        ],
      ),
    );
  }
}