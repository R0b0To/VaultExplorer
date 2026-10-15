import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/archive_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_wizard_shared.dart';
import 'package:vaultexplorer/l10n/generated/app_localizations.dart';

part 'composite_container_controller.g.dart';

bool isUnsupportedArchiveCarrierName(
  String displayName, {
  String? detectedFormat,
}) {
  if (detectedFormat == 'composite_carrier') return false;
  if (detectedFormat == 'archive_unsupported') return true;
  final dot = displayName.lastIndexOf('.');
  if (dot < 0 || dot == displayName.length - 1) return false;
  return ArchiveService.isArchive(displayName.substring(dot + 1));
}

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

  bool get hasUnsupportedArchiveCarrier {
    for (var index = 0; index < pickedCarriers.length; index++) {
      final matchingBudgets = profile?.carriers
          .where((budget) => budget.inputIndex == index)
          .toList();
      final detectedFormat = matchingBudgets == null || matchingBudgets.isEmpty
          ? null
          : matchingBudgets.first.detectedFormat;
      if (isUnsupportedArchiveCarrierName(
        pickedCarriers[index].displayName,
        detectedFormat: detectedFormat,
      )) {
        return true;
      }
    }
    return false;
  }

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
  int _carrierProfileRequestId = 0;

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
    analyzeCarriers();
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
    final requestId = ++_carrierProfileRequestId;
    final carriers = List<KeyfileRef>.of(state.pickedCarriers);
    final safetyMarginPct = state.safetyMarginPct;
    state = state._copy(
      isAnalyzing: carriers.isNotEmpty,
      clearProfile: true,
      clearError: true,
    );
    if (carriers.isEmpty) return;

    final compositeApi = ref.read(vaultCompositeApiProvider);
    final profile = await compositeApi.profileCarriers(
      carrierUris: carriers.map((e) => e.uri).toList(),
      safetyMarginPct: safetyMarginPct,
    );

    if (!ref.mounted || requestId != _carrierProfileRequestId) return;
    state = state._copy(
      profile: profile,
      clearProfile: profile == null,
      isAnalyzing: false,
    );
  }

  /// [userEntropy]: bytes from the wizard's "Add randomness" step (see
  /// `EntropyPool.takeBytes`); null/empty means the OS generator alone. The
  /// caller owns the array and should wipe it once this returns.
  Future<bool> createContainer({
    required String password,
    required String confirmPassword,
    AppLocalizations? l10n,
    Uint8List? userEntropy,
  }) async {
    if (state.hasUnsupportedArchiveCarrier) return false;
    final profile = state.profile;
    if (profile == null || profile.carriers.isEmpty || profile.totalAllocatableBytes < 300 * 1024) {
      state = state._copy(error: l10n?.compositeSpaceTooSmallError ?? 'Allocatable space is too small (minimum 300 KB required)');
      return false;
    }
    if (password.isEmpty && state.keyfiles.isEmpty) {
      state = state._copy(error: l10n?.passwordOrKeyfileRequired ?? 'Password or at least one keyfile is required');
      return false;
    }
    if (password.isNotEmpty && password != confirmPassword) {
      state = state._copy(error: l10n?.passwordsDoNotMatch ?? 'Passwords do not match');
      return false;
    }

    state = state._copy(
      isOperating: true,
      clearError: true,
      statusMessage: l10n?.compositeInitializingStatusMessage ?? 'Initializing composite VeraCrypt volume…',
    );

    final carrierUris = state.pickedCarriers.map((e) => e.uri).toList();
    final orderedBudgets = List.of(profile.carriers)
      ..sort((a, b) => a.fileIndex.compareTo(b.fileIndex));
    final payloadOffsets = orderedBudgets.map((c) => c.payloadOffset).toList();
    final extentLengths = orderedBudgets.map((c) => c.allocatableBytes).toList();

    final compositeApi = ref.read(vaultCompositeApiProvider);
    final ok = await compositeApi.createCompositeContainer(
      carrierUris: carrierUris,
      payloadOffsets: payloadOffsets,
      extentLengths: extentLengths,
      safetyMarginPct: state.safetyMarginPct,
      password: password,
      pim: state.pim,
      fileSystem: state.fileSystem.toLowerCase(),
      cipherId: state.cipherId,
      hashId: state.hashId,
      keyfilePaths: state.keyfiles.map((k) => k.uri).toList(),
      quickFormat: state.quickFormat,
      userEntropy: userEntropy,
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
      error: ok ? null : (l10n?.compositeCreationFailedError ?? 'Failed creating composite container'),
    );
    return ok;
  }

  Future<({MountedContainer container, ContainerRecord? record})?> unlockContainer({
    required String password,
    ContainerRecord? existingRecord,
    AppLocalizations? l10n,
  }) async {
    if (state.pickedCarriers.isEmpty) {
      state = state._copy(error: l10n?.compositeSelectCarriersFirstError ?? 'Please select carrier files first');
      return null;
    }
    if (password.isEmpty && state.keyfiles.isEmpty) {
      state = state._copy(error: l10n?.compositePasswordOrKeyfileRequiredError ?? 'Password or keyfile is required');
      return null;
    }

    state = state._copy(
      isOperating: true,
      clearError: true,
      statusMessage: l10n?.compositeMountingStatusMessage ?? 'Mounting composite volume…',
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
        error: l10n?.compositeAuthFailedOrCarrierMismatchError ?? 'Authentication failed or carrier set mismatch',
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
