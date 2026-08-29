// Phase 3: resolves the remaining hand-rolled singletons through Riverpod.
//
// ContainerRepository and FileOperationService already exposed a
// `.instance` -- the provider below returns that *same* instance
// unchanged, so old call sites (`ContainerRepository.instance.foo()`) and
// newly-migrated ones (`ref.watch(containerRepositoryProvider).foo()`)
// share one cache/notifier. This is deliberately NOT yet a "real"
// @riverpod Notifier with its own reactive `state` -- both of these hold
// real mutable state read by several screens (10 and 5 call-site files
// respectively), so rebuilding their internals to be Riverpod-reactive is
// being done together with migrating those screens to ConsumerWidget in
// Phase 4/5, not blind/unverified ahead of it.
//
// AppSettingsService and LogcatService were pure static-method utility
// classes with no (or trivial) internal state, so they got a `const`
// instance + forwarding methods (see the two files themselves) and are
// wrapped as true "pure keep-alive providers" per the plan's Phase 3 rule.
//
// NOT included here yet:
//  - ThumbnailCacheService: static module state (in-memory LRU byte
//    budget cache) with 16 call-site files and several complex signatures
//    (named params, record returns). Wrapping it means hand-transcribing
//    that whole surface with no compiler to catch a mismatched signature --
//    deferring to Phase 4/5 so it happens alongside (and gets checked by)
//    the screens that actually call it.
//  - SessionLockController: not a singleton -- constructed fresh per
//    VaultDashboardState instance and wired via constructor-injected
//    callbacks into that screen's local state. Converting it in isolation
//    would mean inventing a fake Riverpod shape for it today and redoing
//    that work properly once VaultDashboardScreen itself becomes a
//    ConsumerStatefulWidget in Phase 4 Batch 1 -- so it's covered there.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/logcat_service.dart';

part 'legacy_services_providers.g.dart';

@Riverpod(keepAlive: true)
ContainerRepository containerRepository(Ref ref) => ContainerRepository.instance;

@Riverpod(keepAlive: true)
FileOperationService fileOperationService(Ref ref) => FileOperationService.instance;

@Riverpod(keepAlive: true)
AppSettingsService appSettingsService(Ref ref) => const AppSettingsService();

@Riverpod(keepAlive: true)
LogcatService logcatService(Ref ref) => const LogcatService();
