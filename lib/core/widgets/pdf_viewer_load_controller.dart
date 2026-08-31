import 'package:riverpod_annotation/riverpod_annotation.dart';
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
  @override
  PdfViewerLoadState build(String identityKey) {
    ref.onDispose(() {
      final handle = state.handle;
      if (handle != null) {
        ref.read(vaultPdfApiProvider).closePdf(handle);
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
      final result = await ref.read(vaultPdfApiProvider).openPdf(
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
      final result = await ref.read(vaultPdfApiProvider).openLocalPdf(localUri);
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