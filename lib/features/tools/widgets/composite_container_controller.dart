import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_wizard_shared.dart';

part 'composite_container_controller.g.dart';

class CompositeContainerState {
  final bool isCreating; // true = creation tab, false = unlock tab
  final List<KeyfileRef> pickedCarriers;
  final CapacityProfile? profile;
  final bool isAnalyzing;
  final bool isOperating;
  final int safetyMarginPct; // Interpreted as carrier growth percentage (e.g. 5, 10, 20)
  final String fileSystem;
  final int cipherId;
  final int hashId;
  final int pim;
  final List<KeyfileRef> keyfiles;
  final bool pickingKeyfiles;
  final bool quickFormat;
  final String? error;
  final String? statusMessage;
  final bool remember;

  const CompositeContainerState({
    this.isCreating = true,
    this.pickedCarriers = const [],
    this.profile,
    this.isAnalyzing = false,
    this.isOperating = false,
    this.safetyMarginPct = 10, // Default 10% growth (stealthy)
    this.fileSystem = 'FAT',
    this.cipherId = 0, // Default AES
    this.hashId = 0,   // Default SHA-512
    this.pim = 0,
    this.keyfiles = const [],
    this.pickingKeyfiles = false,
    this.quickFormat = true,
    this.error,
    this.statusMessage,
    this.remember = false,
  });

  CompositeContainerState _copy({
    bool? isCreating,
    List<KeyfileRef>? pickedCarriers,
    CapacityProfile? profile,
    bool clearProfile = false,
    bool? isAnalyzing,
    bool? isOperating,
    int? safetyMarginPct,
    String? fileSystem,
    int? cipherId,
    int? hashId,
    int? pim,
    List<KeyfileRef>? keyfiles,
    bool? pickingKeyfiles,
    bool? quickFormat,
    String? error,
    bool clearError = false,
    String? statusMessage,
    bool clearStatus = false,
    bool? remember,
  }) =>
      CompositeContainerState(
        isCreating: isCreating ?? this.isCreating,
        pickedCarriers: pickedCarriers ?? this.pickedCarriers,
        profile: clearProfile ? null : (profile ?? this.profile),
        isAnalyzing: isAnalyzing ?? this.isAnalyzing,
        isOperating: isOperating ?? this.isOperating,
        safetyMarginPct: safetyMarginPct ?? this.safetyMarginPct,
        fileSystem: fileSystem ?? this.fileSystem,
        cipherId: cipherId ?? this.cipherId,
        hashId: hashId ?? this.hashId,
        pim: pim ?? this.pim,
        keyfiles: keyfiles ?? this.keyfiles,
        pickingKeyfiles: pickingKeyfiles ?? this.pickingKeyfiles,
        quickFormat: quickFormat ?? this.quickFormat,
        error: clearError ? null : (error ?? this.error),
        statusMessage: clearStatus ? null : (statusMessage ?? this.statusMessage),
        remember: remember ?? this.remember,
      );
}

@riverpod
class CompositeContainer extends _$CompositeContainer {
  @override
  CompositeContainerState build() => const CompositeContainerState();

  void setMode(bool isCreating) {
    state = state._copy(
      isCreating: isCreating,
      cipherId: isCreating ? 0 : 255,
      hashId: isCreating ? 0 : 255,
      clearError: true,
    );
  }

  void setFileSystem(String fs) => state = state._copy(fileSystem: fs);
  void setCipherId(int id) => state = state._copy(cipherId: id);
  void setHashId(int id) => state = state._copy(hashId: id);
  void setPim(int pim) => state = state._copy(pim: pim);
  void setQuickFormat(bool val) => state = state._copy(quickFormat: val);

  void setSafetyMargin(int pct) {
    state = state._copy(safetyMarginPct: pct);
    if (state.pickedCarriers.isNotEmpty) analyzeCarriers();
  }

  void setRemember(bool val) => state = state._copy(remember: val);

  void loadCarriersFromRecord(ContainerRecord record) {
    final carriers = record.compositeCarriers
        .map((c) => (uri: c['uri'] ?? '', displayName: c['name'] ?? ''))
        .toList();
    state = state._copy(isCreating: false, pickedCarriers: carriers, clearError: true);
    if (carriers.isNotEmpty) analyzeCarriers();
  }

  Future<void> pickCarriers() async {
    final lifecycle = ref.read(vaultLifecycleApiProvider);
    final picked = await lifecycle.pickCryptoFiles();
    if (picked.isEmpty || !ref.mounted) return;

    state = state._copy(
      pickedCarriers: mergeKeyfilesByUri(state.pickedCarriers, picked),
      clearError: true,
    );
    await analyzeCarriers();
  }

  void removeCarrier(int index) {
    if (index < 0 || index >= state.pickedCarriers.length) return;
    final updated = List<KeyfileRef>.from(state.pickedCarriers)..removeAt(index);
    state = state._copy(pickedCarriers: updated);
    if (updated.isEmpty) {
      state = state._copy(clearProfile: true);
    } else {
      analyzeCarriers();
    }
  }

  Future<void> pickKeyfiles() async {
    state = state._copy(pickingKeyfiles: true);
    try {
      final lifecycle = ref.read(vaultLifecycleApiProvider);
      final picked = await lifecycle.pickKeyfiles();
      if (!ref.mounted) return;
      if (picked.isNotEmpty) {
        state = state._copy(
          keyfiles: mergeKeyfilesByUri(state.keyfiles, picked),
          clearError: true,
        );
      }
    } finally {
      if (ref.mounted) state = state._copy(pickingKeyfiles: false);
    }
  }

  void removeKeyfile(KeyfileRef keyfile) {
    state = state._copy(keyfiles: removeKeyfileByValue(state.keyfiles, keyfile));
  }

  Future<void> analyzeCarriers() async {
    if (state.pickedCarriers.isEmpty) return;
    state = state._copy(isAnalyzing: true, clearError: true);

    final compositeApi = ref.read(vaultCompositeApiProvider);
    final profile = await compositeApi.profileCarriers(
      carrierUris: state.pickedCarriers.map((e) => e.uri).toList(),
      safetyMarginPct: state.safetyMarginPct,
    );

    if (!ref.mounted) return;
    state = state._copy(profile: profile, isAnalyzing: false);
  }

  Future<bool> createContainer({
    required String password,
    required String confirmPassword,
  }) async {
    final profile = state.profile;
    if (profile == null || profile.carriers.isEmpty || profile.totalAllocatableBytes < 300 * 1024) {
      state = state._copy(error: 'Allocatable space is too small (minimum 300 KB required)');
      return false;
    }
    if (password.isEmpty && state.keyfiles.isEmpty) {
      state = state._copy(error: 'Password or at least one keyfile is required');
      return false;
    }
    if (password.isNotEmpty && password != confirmPassword) {
      state = state._copy(error: 'Passwords do not match');
      return false;
    }

    state = state._copy(
      isOperating: true,
      clearError: true,
      statusMessage: 'Initializing composite VeraCrypt volume…',
    );

    final carrierUris = state.pickedCarriers.map((e) => e.uri).toList();
    final payloadOffsets = profile.carriers.map((c) => c.payloadOffset).toList();
    final extentLengths = profile.carriers.map((c) => c.allocatableBytes).toList();

    final compositeApi = ref.read(vaultCompositeApiProvider);
    final ok = await compositeApi.createCompositeContainer(
      carrierUris: carrierUris,
      payloadOffsets: payloadOffsets,
      extentLengths: extentLengths,
      password: password,
      pim: state.pim,
      fileSystem: state.fileSystem.toLowerCase(),
      cipherId: state.cipherId,
      hashId: state.hashId,
      keyfilePaths: state.keyfiles.map((k) => k.uri).toList(),
      quickFormat: state.quickFormat,
    );

    if (!ref.mounted) return false;

    if (ok && state.remember) {
      final compositeUri = 'composite:${carrierUris.first}';
      await ref.read(containerRepositoryProvider).save(ContainerRecord(
            uri: compositeUri,
            label: 'Composite Container (${carrierUris.length} files)',
            rememberPassword: false,
            unlockMethod: ContainerUnlockMethod.password,
            cipherId: state.cipherId,
            hashId: state.hashId,
            containerFormat: 'veracrypt',
            keyfiles: state.keyfiles
                .map((k) => {'uri': k.uri, 'name': k.displayName})
                .toList(),
            compositeCarriers: state.pickedCarriers
                .map((c) => {'uri': c.uri, 'name': c.displayName})
                .toList(),
          ));
      if (!ref.mounted) return false;
    }

    state = state._copy(
      isOperating: false,
      clearStatus: true,
      error: ok ? null : 'Failed creating composite container',
    );
    return ok;
  }

  Future<({MountedContainer container, ContainerRecord? record})?> unlockContainer({
    required String password,
    ContainerRecord? existingRecord,
  }) async {
    if (state.pickedCarriers.isEmpty) {
      state = state._copy(error: 'Please select carrier files first');
      return null;
    }
    if (password.isEmpty && state.keyfiles.isEmpty) {
      state = state._copy(error: 'Password or keyfile is required');
      return null;
    }

    state = state._copy(
      isOperating: true,
      clearError: true,
      statusMessage: 'Mounting composite volume…',
    );

    final compositeApi = ref.read(vaultCompositeApiProvider);
    final carrierUris = state.pickedCarriers.map((e) => e.uri).toList();
    final displayName =
        existingRecord?.label ?? 'Composite Container (${state.pickedCarriers.length} files)';

    final result = await compositeApi.unlockCompositeContainer(
      carrierUris: carrierUris,
      payloadOffsets: null,
      extentLengths: null,
      password: password,
      pim: state.pim,
      cipherId: state.cipherId,
      hashId: state.hashId,
      keyfilePaths: state.keyfiles.map((k) => k.uri).toList(),
      displayName: displayName,
    );

    if (!ref.mounted) return null;

    if (result == null) {
      state = state._copy(
        isOperating: false,
        clearStatus: true,
        error: 'Authentication failed or carrier set mismatch',
      );
      return null;
    }

    final container = MountedContainer(
      uri: 'composite:${carrierUris.first}',
      displayName: displayName,
      volId: result.volId,
      rootFiles: result.files,
      mountedAt: DateTime.now(),
      totalSpace: 0,
      freeSpace: 0,
      containerFormat: result.containerFormat,
    );

    var record = existingRecord;
    if (record == null && state.remember) {
      record = ContainerRecord(
        uri: container.uri,
        label: displayName,
        rememberPassword: false,
        unlockMethod: ContainerUnlockMethod.password,
        cipherId: result.matchedCipherId,
        hashId: result.matchedHashId,
        containerFormat: result.containerFormat,
        keyfiles: state.keyfiles.map((k) => {'uri': k.uri, 'name': k.displayName}).toList(),
        compositeCarriers:
            state.pickedCarriers.map((c) => {'uri': c.uri, 'name': c.displayName}).toList(),
      );
      await ref.read(containerRepositoryProvider).save(record);
      if (!ref.mounted) return null;
    }

    state = state._copy(isOperating: false, clearStatus: true);
    return (container: container, record: record);
  }
}