import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/controllers/library_providers.dart';
import 'package:vaultexplorer/features/library/controllers/music_mode.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/features/library/widgets/music_scope_sheet.dart';

/// The music mode entry for [container]; what the toolbar button and the bar
/// both listen to.
MusicModeEntry musicModeEntryFor(WidgetRef ref, MountedContainer container) =>
    ref.read(musicModeRegistryProvider).entryFor(container);

/// The toolbar button: turns music mode off, or asks which folders to cover and
/// turns it on.
Future<void> toggleMusicMode(
  BuildContext context,
  WidgetRef ref,
  MountedContainer container,
) async {
  final entry = musicModeEntryFor(ref, container);
  final fileIo = ref.read(vaultFileIoApiProvider);
  await entry.load();
  if (entry.config.enabled) {
    await entry.disable();
    return;
  }
  if (!context.mounted) return;
  final folders = await showMusicScopeSheet(
    context,
    container: container,
    access: libraryFileAccess(fileIo, container),
    initialFolders: entry.config.folders,
    turningOn: true,
    preferChoosing: container.isLocalStorage && entry.config.folders.isEmpty,
  );
  if (folders == null) return;
  await entry.enable(folders: folders);
}

/// Changes which folders music mode covers.
Future<void> editMusicFolders(
  BuildContext context,
  WidgetRef ref,
  MountedContainer container,
) async {
  final entry = musicModeEntryFor(ref, container);
  final fileIo = ref.read(vaultFileIoApiProvider);
  final folders = await showMusicScopeSheet(
    context,
    container: container,
    access: libraryFileAccess(fileIo, container),
    initialFolders: entry.config.folders,
    turningOn: false,
    preferChoosing: false,
  );
  if (folders == null) return;
  await entry.setFolders(folders);
}
