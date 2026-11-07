import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/library/controllers/library_providers.dart';
import 'package:vaultexplorer/features/library/controllers/music_mode.dart';
import 'package:vaultexplorer/features/library/widgets/music_library_body.dart';
import 'package:vaultexplorer/features/library/widgets/music_mini_player.dart';

/// Wraps one file manager tab's content and adds music mode to it.
///
/// With the mode off [child] (the normal file listing) fills the space exactly
/// as before. With it on, the Albums / Artists / Genres / Tracks views replace
/// the listing and a mini player appears above the music mode toolbar while
/// music plays. The listing is kept alive underneath, so its folder, selection
/// and scroll position are restored when music mode is turned off.
///
/// The library is shared: every tab with music mode on feeds the same merged
/// library (see `MusicHub`), so a vault and the phone's music appear together,
/// and two tabs on the same location share one scan. A location's library exists
/// only while at least one tab holds it with the mode on; closing the tab or
/// locking the vault drops it from memory.
class MusicModeHost extends ConsumerStatefulWidget {
  final MountedContainer container;
  final Widget child;

  const MusicModeHost({
    super.key,
    required this.container,
    required this.child,
  });

  @override
  ConsumerState<MusicModeHost> createState() => _MusicModeHostState();
}

class _MusicModeHostState extends ConsumerState<MusicModeHost> {
  late final MusicModeRegistry _registry;
  late final MusicModeEntry _entry;
  late final MusicLibrary _library;

  bool _attached = false;

  @override
  void initState() {
    super.initState();
    _registry = ref.read(musicModeRegistryProvider);
    _library = ref.read(musicLibraryProvider);
    _entry = _registry.acquire(widget.container);
    _entry.addListener(_onEntryChanged);
    _syncLibrary();
  }

  @override
  void dispose() {
    _entry.removeListener(_onEntryChanged);
    _detach();
    _registry.release(widget.container);
    super.dispose();
  }

  void _onEntryChanged() {
    if (!mounted) return;
    _syncLibrary();
    setState(() {});
  }

  /// Joins, leaves or re-scopes the shared library to match the saved config.
  void _syncLibrary() {
    final config = _entry.config;
    if (config.enabled && !_attached) {
      _attached = true;
      _library.hub.attach(widget.container, folders: config.folders);
      unawaited(_library.covers.loadCustom(widget.container));
    } else if (!config.enabled && _attached) {
      _detach();
    } else if (config.enabled && _attached) {
      unawaited(_library.hub.setFolders(widget.container, config.folders));
    }
  }

  void _detach() {
    if (!_attached) return;
    _attached = false;
    _library.hub.detach(widget.container);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = _entry.config.enabled;
    final showLibrary = _entry.libraryVisible && _attached;

    // The music mode toolbar is supplied through the file manager's bottom
    // toolbar slot, so it takes layout space instead of covering this content.
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: HeroMode(
                  enabled: !showLibrary,
                  child: Offstage(
                    offstage: showLibrary,
                    child: TickerMode(
                      enabled: !showLibrary,
                      child: widget.child,
                    ),
                  ),
                ),
              ),
              if (showLibrary)
                Positioned.fill(
                  child: MusicLibraryBody(
                    container: widget.container,
                    library: _library,
                    entry: _entry,
                  ),
                ),
            ],
          ),
        ),
        if (enabled)
          MusicMiniPlayer(hub: _library.hub, covers: _library.covers)
        else
          const SizedBox.shrink(),
      ],
    );
  }
}
