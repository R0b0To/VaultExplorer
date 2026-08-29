// Cross-cutting event plumbing extracted from the legacy VaultExplorerApi's
// static listener registries + initMethodCallHandler() (Phase 2 of the
// Riverpod migration). Exposed as a single @Riverpod(keepAlive: true)
// instance (see lib/core/providers/vault_engine_providers.dart) so it keeps
// exactly the "one native MethodCallHandler for the process lifetime"
// behaviour the old static singleton had, without a hand-rolled singleton.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/services/cache_coordinator.dart';
import 'package:vaultexplorer/core/utils/listener_registry.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';

import 'vault_engine_types.dart';

class VaultEngineEvents {
  void Function(String ext, String pkg)? onAppSelectedCallback;

  Completer<bool>? _cameraPermissionCompleter;
  Completer<bool>? _storagePermissionCompleter;
  Completer<bool>? _notificationPermissionCompleter;

  Future<bool> awaitCameraPermissionResult() {
    final completer = Completer<bool>();
    _cameraPermissionCompleter = completer;
    return completer.future;
  }

  Future<bool> awaitStoragePermissionResult() {
    final completer = Completer<bool>();
    _storagePermissionCompleter = completer;
    return completer.future;
  }

  Future<bool> awaitNotificationPermissionResult() {
    final completer = Completer<bool>();
    _notificationPermissionCompleter = completer;
    return completer.future;
  }

  final ListenerRegistry<int> _usbContainerDetachedRegistry =
      ListenerRegistry<int>();
  void addUsbContainerDetachedListener(void Function(int volId) listener) =>
      _usbContainerDetachedRegistry.add(listener);
  void removeUsbContainerDetachedListener(
    void Function(int volId) listener,
  ) => _usbContainerDetachedRegistry.remove(listener);

  final ListenerRegistry<int> _hiddenVolumeProtectionTriggeredRegistry =
      ListenerRegistry<int>();
  void addHiddenVolumeProtectionTriggeredListener(
    void Function(int volId) listener,
  ) => _hiddenVolumeProtectionTriggeredRegistry.add(listener);
  void removeHiddenVolumeProtectionTriggeredListener(
    void Function(int volId) listener,
  ) => _hiddenVolumeProtectionTriggeredRegistry.remove(listener);

  final ListenerRegistry<int> _vaultForceLockedRegistry =
      ListenerRegistry<int>();
  void addVaultForceLockedListener(void Function(int volId) listener) =>
      _vaultForceLockedRegistry.add(listener);
  void removeVaultForceLockedListener(void Function(int volId) listener) =>
      _vaultForceLockedRegistry.remove(listener);

  final ListenerRegistry<MountedContainer> _vaultAutomationUnlockedRegistry =
      ListenerRegistry<MountedContainer>();
  void addVaultAutomationUnlockedListener(
    void Function(MountedContainer container) listener,
  ) => _vaultAutomationUnlockedRegistry.add(listener);
  void removeVaultAutomationUnlockedListener(
    void Function(MountedContainer container) listener,
  ) => _vaultAutomationUnlockedRegistry.remove(listener);

  final ListenerRegistry<int> _containerLockedRegistry = ListenerRegistry<int>();
  void addContainerLockedListener(void Function(int volId) listener) =>
      _containerLockedRegistry.add(listener);
  void removeContainerLockedListener(void Function(int volId) listener) =>
      _containerLockedRegistry.remove(listener);
  void notifyContainerLocked(int volId) =>
      _containerLockedRegistry.notify(volId);

  final ListenerRegistry<int> _backgroundRecordingStopRequestedRegistry =
      ListenerRegistry<int>();
  void addBackgroundRecordingStopRequestedListener(
    void Function(int volId) listener,
  ) => _backgroundRecordingStopRequestedRegistry.add(listener);
  void removeBackgroundRecordingStopRequestedListener(
    void Function(int volId) listener,
  ) => _backgroundRecordingStopRequestedRegistry.remove(listener);

  final List<void Function()> _screenOffListeners = [];
  void addScreenOffListener(void Function() listener) =>
      _screenOffListeners.add(listener);
  void removeScreenOffListener(void Function() listener) =>
      _screenOffListeners.remove(listener);

  final ListenerRegistry<int> _unlockStartedRegistry = ListenerRegistry<int>();
  void addUnlockStartedListener(void Function(int volId) listener) =>
      _unlockStartedRegistry.add(listener);
  void removeUnlockStartedListener(void Function(int volId) listener) =>
      _unlockStartedRegistry.remove(listener);

  final ListenerRegistry<UnlockProgress> _unlockProgressRegistry =
      ListenerRegistry<UnlockProgress>();
  void addUnlockProgressListener(
    void Function(UnlockProgress progress) listener,
  ) => _unlockProgressRegistry.add(listener);
  void removeUnlockProgressListener(
    void Function(UnlockProgress progress) listener,
  ) => _unlockProgressRegistry.remove(listener);

  final ListenerRegistry<ImportProgress> _importProgressRegistry =
      ListenerRegistry<ImportProgress>();
  void addImportProgressListener(
    void Function(ImportProgress progress) listener,
  ) => _importProgressRegistry.add(listener);
  void removeImportProgressListener(
    void Function(ImportProgress progress) listener,
  ) => _importProgressRegistry.remove(listener);

  final ListenerRegistry<ImportItemFinished> _importItemFinishedRegistry =
      ListenerRegistry<ImportItemFinished>();
  void addImportItemFinishedListener(
    void Function(ImportItemFinished progress) listener,
  ) => _importItemFinishedRegistry.add(listener);
  void removeImportItemFinishedListener(
    void Function(ImportItemFinished progress) listener,
  ) => _importItemFinishedRegistry.remove(listener);

  final ListenerRegistry<ExportProgress> _exportProgressRegistry =
      ListenerRegistry<ExportProgress>();
  void addExportProgressListener(
    void Function(ExportProgress progress) listener,
  ) => _exportProgressRegistry.add(listener);
  void removeExportProgressListener(
    void Function(ExportProgress progress) listener,
  ) => _exportProgressRegistry.remove(listener);

  final ListenerRegistry<ExportItemFinished> _exportItemFinishedRegistry =
      ListenerRegistry<ExportItemFinished>();
  void addExportItemFinishedListener(
    void Function(ExportItemFinished progress) listener,
  ) => _exportItemFinishedRegistry.add(listener);
  void removeExportItemFinishedListener(
    void Function(ExportItemFinished progress) listener,
  ) => _exportItemFinishedRegistry.remove(listener);

  final ListenerRegistry<SplitJoinProgress> _splitJoinProgressRegistry =
      ListenerRegistry<SplitJoinProgress>();
  void addSplitJoinProgressListener(
    void Function(SplitJoinProgress progress) listener,
  ) => _splitJoinProgressRegistry.add(listener);
  void removeSplitJoinProgressListener(
    void Function(SplitJoinProgress progress) listener,
  ) => _splitJoinProgressRegistry.remove(listener);

  final ListenerRegistry<CopyProgress> _copyProgressRegistry =
      ListenerRegistry<CopyProgress>();
  void addCopyProgressListener(
    void Function(CopyProgress progress) listener,
  ) => _copyProgressRegistry.add(listener);
  void removeCopyProgressListener(
    void Function(CopyProgress progress) listener,
  ) => _copyProgressRegistry.remove(listener);

  final ListenerRegistry<RepairLogLine> _repairLogRegistry =
      ListenerRegistry<RepairLogLine>();
  void addRepairLogListener(void Function(RepairLogLine line) listener) =>
      _repairLogRegistry.add(listener);
  void removeRepairLogListener(void Function(RepairLogLine line) listener) =>
      _repairLogRegistry.remove(listener);

  final ListenerRegistry<HashProgress> _hashProgressRegistry =
      ListenerRegistry<HashProgress>();
  void addHashProgressListener(
    void Function(HashProgress progress) listener,
  ) => _hashProgressRegistry.add(listener);
  void removeHashProgressListener(
    void Function(HashProgress progress) listener,
  ) => _hashProgressRegistry.remove(listener);

  final Set<int> _activeBatches = {};
  final Set<int> _lockPending = {};

  void beginBatch(int volId) => _activeBatches.add(volId);
  void endBatch(int volId) => _activeBatches.remove(volId);
  bool hasActiveBatch(int volId) => _activeBatches.contains(volId);

  bool acquireLockGuard(int volId) {
    if (_activeBatches.contains(volId) || _lockPending.contains(volId)) {
      return false;
    }
    _lockPending.add(volId);
    return true;
  }

  void releaseLockGuard(int volId) => _lockPending.remove(volId);

  /// Attaches the native -> Dart method-call dispatch to [channel]. Called
  /// once by the `vaultEngineEventsProvider` (keepAlive), replacing the old
  /// `VaultExplorerApi.initMethodCallHandler()` static call from `main()`.
  void registerHandler(MethodChannel channel) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'onAppSelected') {
        final ext = call.arguments['extension'] as String?;
        final pkg = call.arguments['package'] as String?;
        if (ext != null && pkg != null) {
          onAppSelectedCallback?.call(ext, pkg);
        }
      } else if (call.method == 'onUsbContainerDetached') {
        final volId = call.arguments['volId'] as int?;
        if (volId != null) {
          _usbContainerDetachedRegistry.notify(volId);
        }
      } else if (call.method == 'onHiddenVolumeProtectionTriggered') {
        final args = call.arguments as Map<Object?, Object?>;
        final volId = args['volId'] as int?;
        if (volId != null) {
          _hiddenVolumeProtectionTriggeredRegistry.notify(volId);
        }
      } else if (call.method == 'onVaultForceLocked') {
        final args = call.arguments as Map<Object?, Object?>;
        final volId = args['volId'] as int?;
        if (volId != null) {
          _vaultForceLockedRegistry.notify(volId);
        }
      } else if (call.method == 'onVaultAutomationUnlocked') {
        final args = call.arguments as Map<Object?, Object?>;
        final volId = args['volId'] as int?;
        final uri = args['uri'] as String?;
        if (volId != null && uri != null) {
          _vaultAutomationUnlockedRegistry.notify(
            MountedContainer(
              uri: uri,
              displayName: args['displayName'] as String? ?? uri,
              volId: volId,
              rootFiles: (args['files'] as List?)?.cast<String>() ?? const [],
              mountedAt: DateTime.now(),
              totalSpace: 0,
              freeSpace: 0,
              containerFormat: args['containerFormat'] as String? ?? 'veracrypt',
              readOnly: args['readOnly'] as bool? ?? false,
            ),
          );
        }
      } else if (call.method == 'onBackgroundRecordingStopRequested') {
        final args = call.arguments as Map<Object?, Object?>;
        final volId = args['volId'] as int?;
        if (volId != null) {
          _backgroundRecordingStopRequestedRegistry.notify(volId);
        }
      } else if (call.method == 'onScreenOff') {
        for (final listener in List.of(_screenOffListeners)) {
          listener();
        }
      } else if (call.method == 'onUnlockStarted') {
        final volId = call.arguments['volId'] as int?;
        if (volId != null) {
          _unlockStartedRegistry.notify(volId);
        }
      } else if (call.method == 'onUnlockProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final volId = args['volId'] as int?;
        final attempted = args['attempted'] as int?;
        final total = args['total'] as int?;
        if (volId != null && attempted != null && total != null) {
          final progress = (
            volId: volId,
            attempted: attempted,
            total: total,
            hashId: args['hashId'] as int? ?? 255,
            cipherId: args['cipherId'] as int? ?? 255,
            containerFormat: args['containerFormat'] as String? ?? 'veracrypt',
            slot: args['slot'] as int? ?? 0,
          );
          _unlockProgressRegistry.notify(progress);
        }
      } else if (call.method == 'onImportProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final done = args['done'] as int?;
        final total = args['total'] as int?;
        if (opId != null && done != null && total != null) {
          final progress = (
            opId: opId,
            done: done,
            total: total,
            currentName: args['currentName'] as String? ?? '',
            transferredBytes: (args['transferredBytes'] as num?)?.toInt() ?? 0,
            totalBytes: (args['totalBytes'] as num?)?.toInt() ?? 0,
          );
          _importProgressRegistry.notify(progress);
        }
      } else if (call.method == 'onImportItemFinished') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final sourceName = args['sourceName'] as String?;
        final resolvedName = args['resolvedName'] as String?;
        final isDir = args['isDir'] as bool? ?? false;
        final success = args['success'] as bool? ?? false;
        if (opId != null && sourceName != null && resolvedName != null) {
          _importItemFinishedRegistry.notify((
            opId: opId,
            sourceName: sourceName,
            resolvedName: resolvedName,
            isDir: isDir,
            success: success,
          ));
        }
      } else if (call.method == 'onExportProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final done = args['done'] as int?;
        final total = args['total'] as int?;
        if (opId != null && done != null && total != null) {
          final progress = (
            opId: opId,
            done: done,
            total: total,
            currentName: args['currentName'] as String? ?? '',
            transferredBytes: (args['transferredBytes'] as num?)?.toInt() ?? 0,
            totalBytes: (args['totalBytes'] as num?)?.toInt() ?? 0,
          );
          _exportProgressRegistry.notify(progress);
        }
      } else if (call.method == 'onExportItemFinished') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final sourceName = args['sourceName'] as String?;
        final isDir = args['isDir'] as bool? ?? false;
        final success = args['success'] as bool? ?? false;
        if (opId != null && sourceName != null) {
          _exportItemFinishedRegistry.notify((
            opId: opId,
            sourceName: sourceName,
            isDir: isDir,
            success: success,
          ));
        }
      } else if (call.method == 'onSplitJoinProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final bytesDone = (args['bytesDone'] as num?)?.toInt();
        final bytesTotal = (args['bytesTotal'] as num?)?.toInt();
        if (opId != null && bytesDone != null && bytesTotal != null) {
          _splitJoinProgressRegistry.notify((
            opId: opId,
            bytesDone: bytesDone,
            bytesTotal: bytesTotal,
          ));
        }
      } else if (call.method == 'onCopyProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final bytesDelta = (args['bytesDelta'] as num?)?.toInt();
        if (opId != null && bytesDelta != null) {
          _copyProgressRegistry.notify((opId: opId, bytesDelta: bytesDelta));
        }
      } else if (call.method == 'onHashProgress') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final bytesDone = (args['bytesDone'] as num?)?.toInt();
        final bytesTotal = (args['bytesTotal'] as num?)?.toInt();
        if (opId != null && bytesDone != null && bytesTotal != null) {
          _hashProgressRegistry.notify((
            opId: opId,
            bytesDone: bytesDone,
            bytesTotal: bytesTotal,
          ));
        }
      } else if (call.method == 'onRepairLog') {
        final args = call.arguments as Map<Object?, Object?>;
        final opId = args['opId'] as int?;
        final message = args['message'] as String?;
        if (opId != null && message != null) {
          _repairLogRegistry.notify((opId: opId, message: message));
        }
      } else if (call.method == 'onCameraPermissionResult') {
        final granted = call.arguments['granted'] as bool? ?? false;
        _cameraPermissionCompleter?.complete(granted);
        _cameraPermissionCompleter = null;
      } else if (call.method == 'onStoragePermissionResult') {
        final granted = call.arguments['granted'] as bool? ?? false;
        _storagePermissionCompleter?.complete(granted);
        _storagePermissionCompleter = null;
      } else if (call.method == 'onNotificationPermissionResult') {
        final granted = call.arguments['granted'] as bool? ?? false;
        _notificationPermissionCompleter?.complete(granted);
        _notificationPermissionCompleter = null;
      } else if (call.method == ChannelMethods.onTrimMemory) {
        final level =
            (call.arguments as Map<Object?, Object?>?)?['level'] as int? ?? 0;
        final trimLevel = level >= 15 ? TrimLevel.severe : TrimLevel.moderate;
        CacheCoordinator.trimAll(trimLevel);
      }
    });
  }
}
