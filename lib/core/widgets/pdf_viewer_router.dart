import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart' show AppBannerTone;
import 'package:vaultexplorer/core/widgets/jetpack_pdf_viewer_view.dart';
import 'package:vaultexplorer/core/widgets/pdf_viewer_base.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

enum _PdfViewerMode { probing, jetpack, fallback }

class PdfViewerRouter extends StatefulWidget {
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
  State<PdfViewerRouter> createState() => _PdfViewerRouterState();
}

class _PdfViewerRouterState extends State<PdfViewerRouter> {
  static bool? _supportedCache;

  _PdfViewerMode _mode = _PdfViewerMode.probing;
  String? _contentUri;
  String? _sessionToken;
  bool _jetpackLoaded = false;
  var _viewerKey = GlobalKey<JetpackPdfViewerViewState>();

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    bool supported;
    try {
      supported = _supportedCache ??=
          await vaultExplorerApi.isJetpackPdfViewerSupported();
    } catch (_) {
      supported = false;
    }
    if (!supported) {
      VeLog.d('JetpackPdfViewer', 'Not supported on this device, falling back');
      if (mounted) setState(() => _mode = _PdfViewerMode.fallback);
      return;
    }
    await _registerSession();
  }

  Future<void> _registerSession() async {
    try {
      final JetpackPdfSession session;
      if (widget.container != null && widget.pdfPath != null) {
        session = await vaultExplorerApi.registerVaultJetpackPdfSession(
          widget.container!,
          widget.pdfPath!,
        );
      } else if (widget.localUri != null && widget.localUri!.isNotEmpty) {
        session = await vaultExplorerApi.registerLocalJetpackPdfSession(
          widget.localUri!,
        );
      } else {
        if (mounted) setState(() => _mode = _PdfViewerMode.fallback);
        return;
      }
      if (!mounted) {
        await vaultExplorerApi.revokeJetpackPdfSession(session.token);
        return;
      }
      setState(() {
        _contentUri = session.contentUri;
        _sessionToken = session.token;
        _mode = _PdfViewerMode.jetpack;
        _viewerKey = GlobalKey<JetpackPdfViewerViewState>();
      });
    } catch (_) {
      if (mounted) setState(() => _mode = _PdfViewerMode.fallback);
    }
  }

  void _onJetpackLoaded() {
    if (!mounted) return;
    setState(() => _jetpackLoaded = true);
  }

  void _onNativeEditRequested() {
    if (!mounted) return;
    showAppSnackBar(
      context,
      message: context.l10n.pdfViewerEditUnavailable,
      tone: AppBannerTone.info,
    );
  }

  void _onJetpackError(String message) {
    if (!mounted || _jetpackLoaded) return;
    _revokeSession();
    setState(() => _mode = _PdfViewerMode.fallback);
  }

  void _revokeSession() {
    final token = _sessionToken;
    if (token == null && _contentUri == null) return;
    _sessionToken = null;
    _contentUri = null;
    vaultExplorerApi.revokeJetpackPdfSession(token);
  }

  Future<void> _toggleSearch() async {
    HapticFeedback.lightImpact();
    await _viewerKey.currentState?.toggleSearch();
  }

  void _printPdf() {
    vaultExplorerApi.printPdf(
      container: widget.container,
      fileName: widget.pdfPath,
      localUri: widget.localUri,
    );
  }

  @override
  void dispose() {
    _revokeSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }

    switch (_mode) {
      case _PdfViewerMode.probing:
        return _buildProbingScaffold(context);
      case _PdfViewerMode.fallback:
        return PdfViewerBase(
          container: widget.container,
          pdfPath: widget.pdfPath,
          localUri: widget.localUri,
          title: widget.title,
          isLocked: widget.isLocked,
          onPrint: _printPdf,
        );
      case _PdfViewerMode.jetpack:
        return _buildJetpackScaffold(context);
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

  Widget _buildJetpackScaffold(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final activeUri = _contentUri;
    if (activeUri == null) {
      return _buildProbingScaffold(context);
    }
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
              onSearch: _jetpackLoaded ? _toggleSearch : null,
              onPrint: _jetpackLoaded ? _printPdf : null,
            ),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  JetpackPdfViewerView(
                    key: _viewerKey,
                    contentUri: activeUri,
                    onLoaded: _onJetpackLoaded,
                    onError: _onJetpackError,
                    onEditRequested: _onNativeEditRequested,
                  ),
                  if (!_jetpackLoaded)
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