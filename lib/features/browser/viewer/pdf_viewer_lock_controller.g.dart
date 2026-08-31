// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pdf_viewer_lock_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Tracks whether the vault backing one PDF-viewer instance has locked.
///
/// PDF rendering, scrolling, zoom, and chrome remain local to the viewer;
/// only the cross-cutting engine event belongs in Riverpod.

@ProviderFor(PdfViewerLock)
final pdfViewerLockProvider = PdfViewerLockFamily._();

/// Tracks whether the vault backing one PDF-viewer instance has locked.
///
/// PDF rendering, scrolling, zoom, and chrome remain local to the viewer;
/// only the cross-cutting engine event belongs in Riverpod.
final class PdfViewerLockProvider
    extends $NotifierProvider<PdfViewerLock, bool> {
  /// Tracks whether the vault backing one PDF-viewer instance has locked.
  ///
  /// PDF rendering, scrolling, zoom, and chrome remain local to the viewer;
  /// only the cross-cutting engine event belongs in Riverpod.
  PdfViewerLockProvider._({
    required PdfViewerLockFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'pdfViewerLockProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$pdfViewerLockHash();

  @override
  String toString() {
    return r'pdfViewerLockProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  PdfViewerLock create() => PdfViewerLock();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(bool value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<bool>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PdfViewerLockProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$pdfViewerLockHash() => r'd5374bd0e45437033ae45686249ee9e0f6c5db4f';

/// Tracks whether the vault backing one PDF-viewer instance has locked.
///
/// PDF rendering, scrolling, zoom, and chrome remain local to the viewer;
/// only the cross-cutting engine event belongs in Riverpod.

final class PdfViewerLockFamily extends $Family
    with $ClassFamilyOverride<PdfViewerLock, bool, bool, bool, int> {
  PdfViewerLockFamily._()
    : super(
        retry: null,
        name: r'pdfViewerLockProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Tracks whether the vault backing one PDF-viewer instance has locked.
  ///
  /// PDF rendering, scrolling, zoom, and chrome remain local to the viewer;
  /// only the cross-cutting engine event belongs in Riverpod.

  PdfViewerLockProvider call(int volId) =>
      PdfViewerLockProvider._(argument: volId, from: this);

  @override
  String toString() => r'pdfViewerLockProvider';
}

/// Tracks whether the vault backing one PDF-viewer instance has locked.
///
/// PDF rendering, scrolling, zoom, and chrome remain local to the viewer;
/// only the cross-cutting engine event belongs in Riverpod.

abstract class _$PdfViewerLock extends $Notifier<bool> {
  late final _$args = ref.$arg as int;
  int get volId => _$args;

  bool build(int volId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<bool, bool>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<bool, bool>,
              bool,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
