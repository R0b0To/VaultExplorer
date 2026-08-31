// Phase 3: resolves the remaining hand-rolled singletons through Riverpod.
//
// ContainerRepository and FileOperationService already exposed a
// `.instance` -- the provider below returns that *same* instance
// unchanged, so old call sites (`ContainerRepository.instance.foo()`) and
// newly-migrated ones (`ref.watch(containerRepositoryProvider).foo()`)
// share one cache/notifier. This was deliberately NOT a "real" @riverpod
// Notifier with its own reactive `state` at the time this file was
// written -- both of these hold real mutable state read by several
// screens (10 and 5 call-site files respectively), so rebuilding their
// internals to be Riverpod-reactive was deferred to be done together with
// migrating those screens to ConsumerWidget in Phase 4/5, not
// blind/unverified ahead of it.
//
// UPDATE: every consuming screen for both (file_browser_screen.dart,
// media_viewer_screen.dart, vault_dashboard_screen.dart,
// container_config_sheet.dart, unlock_controller.dart/
// usb_unlock_controller.dart, etc.) is now ConsumerStatefulWidget/a
// @riverpod Notifier, so the Phase 4/5 gate above is met -- rebuilding
// ContainerRepository/FileOperationService into real reactive Notifiers is
// the next thing to pick up here, still one service at a time with a
// build_runner + analyze check in between, same as CrossContainerClipboard
// below was (see its own doc comment for that worked example: immutable
// state record + instance forwarders so call sites didn't all need to
// change shape at once).
//
// AppSettingsService and LogcatService were pure static-method utility
// classes with no (or trivial) internal state, so they got a `const`
// instance + forwarding methods (see the two files themselves) and are
// wrapped as true "pure keep-alive providers" per the plan's Phase 3 rule.
//
// ThumbnailCacheService also got this treatment, but only partially at
// first: its static module state (in-memory LRU byte-budget cache) stays
// static either way (this is DI plumbing, not a reactive Notifier), but
// its ~13-method surface (several with named params / record returns, 15
// call-site files) was too large to hand-transcribe in one blind pass with
// no compiler to catch a mismatched forwarder signature. So forwarders
// were added and call sites rewired incrementally, widget-by-widget,
// checked as each one went -- see the doc comment on ThumbnailCacheService
// itself for the running list of which methods that covers.
//
// UPDATE: that pass is now complete. file_tile.dart, file_grid_view.dart,
// file_masonry_view.dart, playlist_carousel_overlay.dart,
// media_player_widget.dart, encrypted_image_widget.dart, and
// image_editor_screen.dart all resolve ThumbnailCacheService via
// `ref.read(thumbnailCacheServiceProvider)` now -- in most cases by
// converting just the specific inner thumbnail-rendering widget (e.g.
// file_tile.dart's `_ListImageThumb`/`_ListVideoThumb`) to ConsumerWidget
// rather than the whole outer Stateful screen, since a ConsumerWidget
// nests freely inside a plain widget tree without its ancestor needing to
// be Consumer too. VideoThumbnailFetcher (static-only, same shape as
// ThumbnailCacheService) and the non-widget bootstrap-time callers
// (app_bootstrap.dart, device_capability_service.dart,
// cache_coordinator.dart -- all called before/outside the widget tree, no
// `ref` naturally in scope) are intentionally left on the statics, not a
// pending item -- there's no `ref` to resolve a provider with at those
// call sites.
//
// NOT included here yet:
//  - SessionLockController: now converted -- see
//    lib/data/services/session_lock_controller.dart. It wasn't a true
//    singleton (built fresh per VaultDashboardState via constructor-
//    injected callbacks), so it's a keepAlive provider wrapping a plain
//    class with a configure() entry point instead of a generated Notifier.
//  - CrossContainerClipboard: now converted -- see
//    lib/data/services/cross_container_clipboard.dart. It *was* a true
//    singleton with real mutable state read reactively (the app bar
//    clipboard chip), so unlike SessionLockController it became a proper
//    `@riverpod` Notifier over an immutable state record, not a bridge
//    class here -- worked example for the ContainerRepository/
//    FileOperationService rebuild called out above.
//
// FileManagerToolbarService: same shape as ContainerRepository/
// FileOperationService above (a `.instance` singleton with real cached
// state -- see its own doc comment, which calls this out explicitly as
// "parallel in spirit" to those two) -- so it gets the identical
// "provider returns the same `.instance`" treatment, not a rebuilt
// Notifier, for the same reason, and is part of the same still-pending
// rebuild noted above.
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:vaultexplorer/data/services/app_settings_service.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/models/file_operation.dart';
import 'package:vaultexplorer/data/services/file_manager_toolbar_service.dart';
import 'package:vaultexplorer/data/services/logcat_service.dart';
import 'package:vaultexplorer/data/services/thumbnail_cache_service.dart';

part 'legacy_services_providers.g.dart';

@Riverpod(keepAlive: true)
ContainerRepository containerRepository(Ref ref) => ContainerRepository.instance;

@Riverpod(keepAlive: true)
FileOperationService fileOperationService(Ref ref) => FileOperationService.instance;

@Riverpod(keepAlive: true)
FileManagerToolbarService fileManagerToolbarService(Ref ref) => FileManagerToolbarService.instance;

@Riverpod(keepAlive: true)
AppSettingsService appSettingsService(Ref ref) => const AppSettingsService();

@Riverpod(keepAlive: true)
LogcatService logcatService(Ref ref) => const LogcatService();

@Riverpod(keepAlive: true)
ThumbnailCacheService thumbnailCacheService(Ref ref) => const ThumbnailCacheService();