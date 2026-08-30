// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'html_viewer_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(HtmlViewer)
final htmlViewerProvider = HtmlViewerFamily._();

final class HtmlViewerProvider
    extends $NotifierProvider<HtmlViewer, HtmlViewerState> {
  HtmlViewerProvider._({
    required HtmlViewerFamily super.from,
    required int super.argument,
  }) : super(
         retry: null,
         name: r'htmlViewerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$htmlViewerHash();

  @override
  String toString() {
    return r'htmlViewerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  HtmlViewer create() => HtmlViewer();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(HtmlViewerState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<HtmlViewerState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is HtmlViewerProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$htmlViewerHash() => r'9ed6b012d3c89693a427eee892c8f4a0542bfd86';

final class HtmlViewerFamily extends $Family
    with
        $ClassFamilyOverride<
          HtmlViewer,
          HtmlViewerState,
          HtmlViewerState,
          HtmlViewerState,
          int
        > {
  HtmlViewerFamily._()
    : super(
        retry: null,
        name: r'htmlViewerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  HtmlViewerProvider call(int volId) =>
      HtmlViewerProvider._(argument: volId, from: this);

  @override
  String toString() => r'htmlViewerProvider';
}

abstract class _$HtmlViewer extends $Notifier<HtmlViewerState> {
  late final _$args = ref.$arg as int;
  int get volId => _$args;

  HtmlViewerState build(int volId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<HtmlViewerState, HtmlViewerState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<HtmlViewerState, HtmlViewerState>,
              HtmlViewerState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
