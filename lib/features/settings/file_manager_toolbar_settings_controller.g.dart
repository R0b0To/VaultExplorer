// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'file_manager_toolbar_settings_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(FileManagerToolbarSettings)
final fileManagerToolbarSettingsProvider = FileManagerToolbarSettingsFamily._();

final class FileManagerToolbarSettingsProvider
    extends
        $NotifierProvider<
          FileManagerToolbarSettings,
          FileManagerToolbarSettingsState
        > {
  FileManagerToolbarSettingsProvider._({
    required FileManagerToolbarSettingsFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'fileManagerToolbarSettingsProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$fileManagerToolbarSettingsHash();

  @override
  String toString() {
    return r'fileManagerToolbarSettingsProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  FileManagerToolbarSettings create() => FileManagerToolbarSettings();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(FileManagerToolbarSettingsState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<FileManagerToolbarSettingsState>(
        value,
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is FileManagerToolbarSettingsProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$fileManagerToolbarSettingsHash() =>
    r'e4fbd2f538213e7d00fcf169a82519503beb6bd1';

final class FileManagerToolbarSettingsFamily extends $Family
    with
        $ClassFamilyOverride<
          FileManagerToolbarSettings,
          FileManagerToolbarSettingsState,
          FileManagerToolbarSettingsState,
          FileManagerToolbarSettingsState,
          String?
        > {
  FileManagerToolbarSettingsFamily._()
    : super(
        retry: null,
        name: r'fileManagerToolbarSettingsProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  FileManagerToolbarSettingsProvider call(String? containerUri) =>
      FileManagerToolbarSettingsProvider._(argument: containerUri, from: this);

  @override
  String toString() => r'fileManagerToolbarSettingsProvider';
}

abstract class _$FileManagerToolbarSettings
    extends $Notifier<FileManagerToolbarSettingsState> {
  late final _$args = ref.$arg as String?;
  String? get containerUri => _$args;

  FileManagerToolbarSettingsState build(String? containerUri);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              FileManagerToolbarSettingsState,
              FileManagerToolbarSettingsState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                FileManagerToolbarSettingsState,
                FileManagerToolbarSettingsState
              >,
              FileManagerToolbarSettingsState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
