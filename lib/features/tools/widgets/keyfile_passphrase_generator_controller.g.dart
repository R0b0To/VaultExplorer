// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'keyfile_passphrase_generator_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(KeyfilePassphraseGenerator)
final keyfilePassphraseGeneratorProvider =
    KeyfilePassphraseGeneratorProvider._();

final class KeyfilePassphraseGeneratorProvider
    extends
        $NotifierProvider<
          KeyfilePassphraseGenerator,
          KeyfilePassphraseGeneratorState
        > {
  KeyfilePassphraseGeneratorProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'keyfilePassphraseGeneratorProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$keyfilePassphraseGeneratorHash();

  @$internal
  @override
  KeyfilePassphraseGenerator create() => KeyfilePassphraseGenerator();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(KeyfilePassphraseGeneratorState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<KeyfilePassphraseGeneratorState>(
        value,
      ),
    );
  }
}

String _$keyfilePassphraseGeneratorHash() =>
    r'e86b797ab1b363192595f56a920dbf56a76c0a89';

abstract class _$KeyfilePassphraseGenerator
    extends $Notifier<KeyfilePassphraseGeneratorState> {
  KeyfilePassphraseGeneratorState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              KeyfilePassphraseGeneratorState,
              KeyfilePassphraseGeneratorState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                KeyfilePassphraseGeneratorState,
                KeyfilePassphraseGeneratorState
              >,
              KeyfilePassphraseGeneratorState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
