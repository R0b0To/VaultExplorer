// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'media_viewer_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(MediaViewerSession)
final mediaViewerSessionProvider = MediaViewerSessionFamily._();

final class MediaViewerSessionProvider
    extends $NotifierProvider<MediaViewerSession, MediaViewerSessionState> {
  MediaViewerSessionProvider._({
    required MediaViewerSessionFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'mediaViewerSessionProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$mediaViewerSessionHash();

  @override
  String toString() {
    return r'mediaViewerSessionProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  MediaViewerSession create() => MediaViewerSession();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(MediaViewerSessionState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<MediaViewerSessionState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is MediaViewerSessionProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$mediaViewerSessionHash() =>
    r'e5faebaf9fa1a604fa56e69ece146b98df5f0a75';

final class MediaViewerSessionFamily extends $Family
    with
        $ClassFamilyOverride<
          MediaViewerSession,
          MediaViewerSessionState,
          MediaViewerSessionState,
          MediaViewerSessionState,
          String
        > {
  MediaViewerSessionFamily._()
    : super(
        retry: null,
        name: r'mediaViewerSessionProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  MediaViewerSessionProvider call(String sessionKey) =>
      MediaViewerSessionProvider._(argument: sessionKey, from: this);

  @override
  String toString() => r'mediaViewerSessionProvider';
}

abstract class _$MediaViewerSession extends $Notifier<MediaViewerSessionState> {
  late final _$args = ref.$arg as String;
  String get sessionKey => _$args;

  MediaViewerSessionState build(String sessionKey);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<MediaViewerSessionState, MediaViewerSessionState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<MediaViewerSessionState, MediaViewerSessionState>,
              MediaViewerSessionState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
