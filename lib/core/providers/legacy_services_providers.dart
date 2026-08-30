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
// ThumbnailCacheService also got this treatment, but only partially: its
// static module state (in-memory LRU byte-budget cache) stays static either
// way (this is DI plumbing, not a reactive Notifier), but its ~13-method
// surface (several with named params / record returns, 15 call-site files)
// is too large to hand-transcribe in one blind pass with no compiler to
// catch a mismatched forwarder signature. So only the 4 methods
// media_viewer_screen.dart actually calls (fetch/store/peekMemory/
// cacheInMemory) have forwarders + are rewired so far -- see the doc
// comment on ThumbnailCacheService itself. The other 6 widget call sites
// (file_tile, file_grid_view, file_masonry_view, playlist_carousel_overlay,
// media_player_widget, encrypted_image_widget, image_editor_screen) are
// still plain Stateful/StatelessWidget, not ConsumerWidget/ConsumerState,
// so they still call the ThumbnailCacheService statics directly -- widening
// this provider's coverage to them means converting those widget classes
// first (and threading `ref` through their private child widgets), which is
// its own pass, done widget-by-widget and checked as it goes, same as this
// one was. VideoThumbnailFetcher (static-only, same shape as
// ThumbnailCacheService) and the non-widget bootstrap-time callers
// (app_bootstrap.dart, device_capability_service.dart,
// cache_coordinator.dart -- all called before/outside the widget tree, no
// `ref` naturally in scope) are left on the statics for the same reason.
//
// NOT included here yet:
//  - SessionLockController: now converted -- see
//    lib/data/services/session_lock_controller.dart. It wasn't a true
//    singleton (built fresh per VaultDashboardState via constructor-
//    injected callbacks), so it's a keepAlive provider wrapping a plain
//    class with a configure() entry point instead of a generated Notifier.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/logcat_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

part 'legacy_services_providers.g.dart';

@Riverpod(keepAlive: true)
ContainerRepository containerRepository(Ref ref) => ContainerRepository.instance;

@Riverpod(keepAlive: true)
FileOperationService fileOperationService(Ref ref) => FileOperationService.instance;

@Riverpod(keepAlive: true)
AppSettingsService appSettingsService(Ref ref) => const AppSettingsService();

@Riverpod(keepAlive: true)
LogcatService logcatService(Ref ref) => const LogcatService();

@Riverpod(keepAlive: true)
ThumbnailCacheService thumbnailCacheService(Ref ref) => const ThumbnailCacheService();