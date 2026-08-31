import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_pdf_api.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'pdf_viewer_load_controller.g.dart';

class PdfViewerLoadState {
  final bool isLoading;
  final bool hasError;
  final String errorMessage;
  final int? handle;
  final int pageCount;

  const PdfViewerLoadState({
    this.isLoading = true,
    this.hasError = false,
    this.errorMessage = '',
    this.handle,
    this.pageCount = 0,
  });

  bool get isReady =>
      !isLoading && !hasError && handle != null && pageCount > 0;
}

@riverpod
class PdfViewerLoad extends _$PdfViewerLoad {
  // Captured once in build() -- Riverpod disallows calling ref.read() from
  // inside a ref.onDispose() callback body ("Cannot use Ref or modify other
  // providers inside life-cycles/selectors"), so the API instance has to be
  // grabbed during build()'s own synchronous execution and stashed on the
  // notifier instance for the dispose closure (and every other method) to
  // reuse. Safe because vaultPdfApiProvider is a keepAlive singleton-style
  // wrapper -- the same instance for the life of the app either way.
  late final VaultPdfApi _api;

  @override
  PdfViewerLoadState build(String identityKey) {
    _api = ref.read(vaultPdfApiProvider);
    ref.onDispose(() {
      final handle = state.handle;
      if (handle != null) {
        _api.closePdf(handle);
      }
    });
    return const PdfViewerLoadState();
  }

  Future<void> openVaultPdf(
    MountedContainer container,
    String pdfPath,
    AppLocalizations l10n,
  ) async {
    try {
      final result = await _api.openPdf(
        container,
        pdfPath,
      );
      if (!ref.mounted) return;
      if (result.pageCount <= 0) {
        state = PdfViewerLoadState(
          isLoading: false,
          hasError: true,
          errorMessage: l10n.pdfViewerFileEmpty,
        );
        return;
      }
      state = PdfViewerLoadState(
        handle: result.handle,
        pageCount: result.pageCount,
        isLoading: false,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = PdfViewerLoadState(
        isLoading: false,
        hasError: true,
        errorMessage: l10n.pdfViewerFailedToInspectSize('$e'),
      );
    }
  }

  Future<void> openLocalPdf(String localUri, AppLocalizations l10n) async {
    try {
      final result = await _api.openLocalPdf(localUri);
      if (!ref.mounted) return;
      if (result.pageCount <= 0) {
        state = PdfViewerLoadState(
          isLoading: false,
          hasError: true,
          errorMessage: l10n.pdfViewerFileEmpty,
        );
        return;
      }
      state = PdfViewerLoadState(
        handle: result.handle,
        pageCount: result.pageCount,
        isLoading: false,
      );
    } catch (e) {
      if (!ref.mounted) return;
      state = PdfViewerLoadState(
        isLoading: false,
        hasError: true,
        errorMessage: '${l10n.pdfViewerFailedToLoad}: $e',
      );
    }
  }

  void setNoSourceError(String message) {
    state = PdfViewerLoadState(
      isLoading: false,
      hasError: true,
      errorMessage: message,
    );
  }
}