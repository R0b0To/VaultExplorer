import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/thumbnail_with_size.dart';
import 'package:vaultexplorer/core/utils/listener_registry.dart';
import 'package:vaultexplorer/data/services/vault_engine/channel_methods.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/core/services/cache_coordinator.dart';

part 'vault_explorer_api_crypto.dart';
part 'vault_explorer_api_container_lifecycle.dart';
part 'vault_explorer_api_file_io.dart';

typedef KeyfileRef = ({String uri, String displayName});
typedef UnlockProgress = ({
  int volId,
  int attempted,
  int total,
  int hashId,
  int cipherId,
  String containerFormat,
  int slot,
});
String hashAlgorithmName(int hashId) => HashAlgo.nameFor(hashId);
String cipherAlgorithmName(int cipherId) => CipherAlgo.nameFor(cipherId);

typedef ImportProgress = ({
  int opId,
  int done,
  int total,
  String currentName,
  int transferredBytes,
  int totalBytes,
});

void _logSwallowed(String method, Object error, {bool expected = false}) {
  debugPrint(
    '${expected ? '[VaultExplorerApi:expected]' : '[VaultExplorerApi]'} '
    '$method failed: $error',
  );
}

const _channel = MethodChannel('com.aeidolon.vaultexplorer/engine');

class VaultExplorerApi with _CryptoOps, _ContainerLifecycleOps, _FileIoOps {
  const VaultExplorerApi();

  static void Function(String ext, String pkg)? onAppSelectedCallback;
  static Completer<bool>? _cameraPermissionCompleter;

  static Future<bool> awaitCameraPermissionResult() {
    final completer = Completer<bool>();
    _cameraPermissionCompleter = completer;
    return completer.future;
  }

  static final ListenerRegistry<int> _usbContainerDetachedRegistry =
      ListenerRegistry<int>();
  static void addUsbContainerDetachedListener(
    void Function(int volId) listener,
  ) {
    _usbContainerDetachedRegistry.add(listener);
  }
  static void removeUsbContainerDetachedListener(
    void Function(int volId) listener,
  ) {
    _usbContainerDetachedRegistry.remove(listener);
  }

  static final ListenerRegistry<int> _containerLockedRegistry =
      ListenerRegistry<int>();
  static void addContainerLockedListener(void Function(int volId) listener) {
    _containerLockedRegistry.add(listener);
  }
  static void removeContainerLockedListener(void Function(int volId) listener) {
    _containerLockedRegistry.remove(listener);
  }
  static void notifyContainerLocked(int volId) {
    _containerLockedRegistry.notify(volId);
  }

  static final List<void Function()> _screenOffListeners = [];
  static void addScreenOffListener(void Function() listener) {
    _screenOffListeners.add(listener);
  }
  static void removeScreenOffListener(void Function() listener) {
    _screenOffListeners.remove(listener);
  }

  static final ListenerRegistry<int> _unlockStartedRegistry =
      ListenerRegistry<int>();
  static final ListenerRegistry<UnlockProgress> _unlockProgressRegistry =
      ListenerRegistry<UnlockProgress>();

  static void addUnlockStartedListener(void Function(int volId) listener) {
    _unlockStartedRegistry.add(listener);
  }
  static void removeUnlockStartedListener(void Function(int volId) listener) {
    _unlockStartedRegistry.remove(listener);
  }

  static void addUnlockProgressListener(
    void Function(UnlockProgress progress) listener,
  ) {
    _unlockProgressRegistry.add(listener);
  }
  static void removeUnlockProgressListener(
    void Function(UnlockProgress progress) listener,
  ) {
    _unlockProgressRegistry.remove(listener);
  }

  static final ListenerRegistry<ImportProgress> _importProgressRegistry =
      ListenerRegistry<ImportProgress>();
  static void addImportProgressListener(
    void Function(ImportProgress progress) listener,
  ) {
    _importProgressRegistry.add(listener);
  }
  static void removeImportProgressListener(
    void Function(ImportProgress progress) listener,
  ) {
    _importProgressRegistry.remove(listener);
  }

  static void initMethodCallHandler() {
    _channel.setMethodCallHandler((call) async {
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
      } else if (call.method == 'onCameraPermissionResult') {
        final granted = call.arguments['granted'] as bool? ?? false;
        _cameraPermissionCompleter?.complete(granted);
        _cameraPermissionCompleter = null;
      } else if (call.method == ChannelMethods.onTrimMemory) {
        final level = (call.arguments as Map<Object?, Object?>?)?['level'] as int? ?? 0;
        final trimLevel = level >= 15 ? TrimLevel.severe : TrimLevel.moderate;
        CacheCoordinator.trimAll(trimLevel);
      }
    });
  }

  static final Set<int> _activeBatches = {};
  static final Set<int> _lockPending = {};

  void beginBatch(int volId) {
    _activeBatches.add(volId);
  }

  void endBatch(int volId) {
    _activeBatches.remove(volId);
  }

  bool hasActiveBatch(int volId) => _activeBatches.contains(volId);

  bool acquireLockGuard(int volId) {
    if (_activeBatches.contains(volId) || _lockPending.contains(volId)) {
      return false;
    }
    _lockPending.add(volId);
    return true;
  }

  void releaseLockGuard(int volId) {
    _lockPending.remove(volId);
  }
}

VaultExplorerApi vaultExplorerApi = const VaultExplorerApi();