import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/browser/models/tab_id.dart';
import 'package:vaultexplorer/features/library/controllers/library_providers.dart';
import 'package:vaultexplorer/features/library/controllers/music_mode.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/features/library/widgets/music_scope_sheet.dart';
import 'package:vaultexplorer/features/settings/file_manager_toolbar_settings_controller.dart';

/// The music mode entry of the tab [tabId] showing [container]; what that
/// tab's toolbar button and bar both listen to. Every tab has its own, so music
/// mode in one tab never switches another tab on the same container.
MusicModeEntry musicModeEntryFor(
  WidgetRef ref,
  MountedContainer container,
  TabId tabId,
) => ref.read(musicModeRegistryProvider).entryFor(container, tabId);

/// The toolbar button: turns music mode off in the tab that owns [entry], or
/// asks which folders to cover and turns it on there.
Future<void> toggleMusicMode(
  BuildContext context,
  WidgetRef ref,
  MusicModeEntry entry,
) async {
  final container = entry.container;
  final fileIo = ref.read(vaultFileIoApiProvider);
  await entry.load();
  if (entry.config.enabled) {
    await entry.disable();
    return;
  }
  if (!context.mounted) return;
  final effectiveToolbarUri = container.isLocalStorage ? null : container.uri;
  final toolbarSettings =
      ref.read(fileManagerToolbarSettingsProvider(effectiveToolbarUri));
  final isSkipped =
      toolbarSettings.config.isMusicPromptSkippedForStorage(container.uri);

  if (isSkipped) {
    await entry.enable(folders: entry.config.folders);
    return;
  }

  final res = await showMusicScopeSheet(
    context,
    container: container,
    access: libraryFileAccess(fileIo, container),
    initialFolders: entry.config.folders,
    initialDontAskAgain: isSkipped,
    turningOn: true,
    preferChoosing: container.isLocalStorage && entry.config.folders.isEmpty,
  );
  if (res == null) return;
  if (res.dontAskAgain != isSkipped) {
    await ref
        .read(fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier)
        .setMusicPromptSkippedForStorage(container.uri, res.dontAskAgain);
  }
  await entry.enable(folders: res.folders);
}

/// Changes which folders music mode covers (for every tab on the container).
Future<void> editMusicFolders(
  BuildContext context,
  WidgetRef ref,
  MusicModeEntry entry,
) async {
  final container = entry.container;
  final fileIo = ref.read(vaultFileIoApiProvider);
  final effectiveToolbarUri = container.isLocalStorage ? null : container.uri;
  final toolbarSettings =
      ref.read(fileManagerToolbarSettingsProvider(effectiveToolbarUri));
  final isSkipped =
      toolbarSettings.config.isMusicPromptSkippedForStorage(container.uri);

  final res = await showMusicScopeSheet(
    context,
    container: container,
    access: libraryFileAccess(fileIo, container),
    initialFolders: entry.config.folders,
    initialDontAskAgain: isSkipped,
    turningOn: false,
    preferChoosing: false,
  );
  if (res == null) return;
  if (res.dontAskAgain != isSkipped) {
    await ref
        .read(fileManagerToolbarSettingsProvider(effectiveToolbarUri).notifier)
        .setMusicPromptSkippedForStorage(container.uri, res.dontAskAgain);
  }
  await entry.setFolders(res.folders);
}
