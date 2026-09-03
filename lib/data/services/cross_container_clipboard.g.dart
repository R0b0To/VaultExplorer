// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'cross_container_clipboard.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(CrossContainerClipboard)
final crossContainerClipboardProvider = CrossContainerClipboardProvider._();

final class CrossContainerClipboardProvider
    extends $NotifierProvider<CrossContainerClipboard, ClipboardState> {
  CrossContainerClipboardProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'crossContainerClipboardProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$crossContainerClipboardHash();

  @$internal
  @override
  CrossContainerClipboard create() => CrossContainerClipboard();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ClipboardState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ClipboardState>(value),
    );
  }
}

String _$crossContainerClipboardHash() =>
    r'6943ec3953b132fe650e22614de33823ba6a8fc8';

abstract class _$CrossContainerClipboard extends $Notifier<ClipboardState> {
  ClipboardState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ClipboardState, ClipboardState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ClipboardState, ClipboardState>,
              ClipboardState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
