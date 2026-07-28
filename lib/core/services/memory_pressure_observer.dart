import 'package:flutter/widgets.dart';
import 'package:vaultexplorer/core/services/cache_coordinator.dart';

/// Flutter-level memory pressure listener (ADR-011, ADR-018, Finding F-15).
///
/// Listens to [WidgetsBindingObserver.didHaveMemoryPressure] (triggered by iOS
/// OS memory pressure or Flutter engine memory warnings) and dispatches a
/// severe memory trim across all memory-tier caches via [CacheCoordinator.trimAll].
class MemoryPressureObserver with WidgetsBindingObserver {
  static MemoryPressureObserver? _instance;

  MemoryPressureObserver._();

  /// Registers the singleton observer with [WidgetsBinding.instance].
  static void register() {
    if (_instance != null) return;
    _instance = MemoryPressureObserver._();
    WidgetsBinding.instance.addObserver(_instance!);
  }

  /// Unregisters the observer if active.
  static void unregister() {
    if (_instance == null) return;
    WidgetsBinding.instance.removeObserver(_instance!);
    _instance = null;
  }

  @override
  void didHaveMemoryPressure() {
    CacheCoordinator.trimAll(TrimLevel.severe);
  }
}
