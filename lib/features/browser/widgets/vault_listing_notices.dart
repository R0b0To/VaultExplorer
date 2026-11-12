import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/utils/vault_symlink.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';

/// What a Cryptomator folder contains that a normal listing cannot show:
///
///  * **Symbolic links.** A link is neither a file nor a folder here. It is never followed (its target could
///    point anywhere), so the sheet only *shows* where it points.
///  * **Hidden entries.** Things that exist on disk inside the vault but are not listed -- most often
///    sync-conflict copies such as "name (1)" made by a cloud sync app, or a node whose upload has not
///    finished. Without this notice they are simply invisible.
///
/// Renders nothing at all unless there is something to report, and nothing for anything that is not a
/// Cryptomator vault, so it is safe to place above every folder listing.
class VaultListingNotices extends ConsumerStatefulWidget {
  const VaultListingNotices({
    super.key,
    required this.container,
    required this.dirPath,
    required this.listingToken,
  });

  final MountedContainer container;
  final String dirPath;

  /// Anything whose identity changes when the folder listing is reloaded (the browser passes its item list),
  /// so the notice is refreshed together with the listing.
  final Object listingToken;

  @override
  ConsumerState<VaultListingNotices> createState() =>
      _VaultListingNoticesState();
}

class _VaultListingNoticesState extends ConsumerState<VaultListingNotices> {
  List<VaultSymlink> _links = const [];
  int _hidden = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(VaultListingNotices oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dirPath != widget.dirPath ||
        oldWidget.container.volId != widget.container.volId ||
        !identical(oldWidget.listingToken, widget.listingToken)) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final api = ref.read(vaultFileIoApiProvider);
    final links = await api.listVaultSymlinks(widget.container, widget.dirPath);
    final hidden = await api.hiddenEntryCount(widget.container, widget.dirPath);
    if (!mounted || generation != _generation) return;
    final shownHidden = hidden < 0 ? 0 : hidden;
    if (shownHidden == _hidden && listEquals(links, _links)) return;
    setState(() {
      _links = links;
      _hidden = shownHidden;
    });
  }

  String _pathOf(VaultSymlink link) =>
      widget.dirPath.isEmpty ? link.name : '${widget.dirPath}/${link.name}';

  void _openDetails() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _DetailsSheet(
        container: widget.container,
        links: _links,
        hidden: _hidden,
        pathOf: _pathOf,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_links.isEmpty && _hidden == 0) return const SizedBox.shrink();
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final parts = <String>[
      if (_links.isNotEmpty) l10n.vaultListingSymbolicLinkCount(_links.length),
      if (_hidden > 0) l10n.vaultListingHiddenEntryCount(_hidden),
    ];
    final warn = _hidden > 0;
    return Material(
      color: warn ? scheme.tertiaryContainer : scheme.surfaceContainerHighest,
      child: InkWell(
        onTap: _openDetails,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                warn ? Icons.visibility_off_outlined : Icons.link,
                size: 18,
                color: warn
                    ? scheme.onTertiaryContainer
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  parts.join(' \u00B7 '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: warn
                        ? scheme.onTertiaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Text(
                l10n.vaultListingDetails,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: warn ? scheme.onTertiaryContainer : scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailsSheet extends ConsumerStatefulWidget {
  const _DetailsSheet({
    required this.container,
    required this.links,
    required this.hidden,
    required this.pathOf,
  });

  final MountedContainer container;
  final List<VaultSymlink> links;
  final int hidden;
  final String Function(VaultSymlink) pathOf;

  @override
  ConsumerState<_DetailsSheet> createState() => _DetailsSheetState();
}

class _DetailsSheetState extends ConsumerState<_DetailsSheet> {
  // link name -> target text (null while loading, '' if unreadable is represented by a marker)
  final Map<String, String?> _targets = {};
  final Set<String> _done = {};

  @override
  void initState() {
    super.initState();
    _loadTargets();
  }

  Future<void> _loadTargets() async {
    final api = ref.read(vaultFileIoApiProvider);
    for (final link in widget.links) {
      final target = await api.readVaultSymlink(
        widget.container,
        widget.pathOf(link),
      );
      if (!mounted) return;
      setState(() {
        _targets[link.name] = target;
        _done.add(link.name);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final textTheme = Theme.of(context).textTheme;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            if (widget.hidden > 0) ...[
              Text(
                l10n.vaultListingHiddenEntriesTitle,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.vaultListingHiddenEntriesBody,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
            ],
            if (widget.links.isNotEmpty) ...[
              Text(
                l10n.vaultListingSymbolicLinksTitle,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.vaultListingSymbolicLinksNote,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              for (final link in widget.links)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link),
                  title: Text(
                    link.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: !_done.contains(link.name)
                      ? null
                      : Text(
                          _targets[link.name] ??
                              l10n.vaultListingTargetUnreadable,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: _targets[link.name] == null
                      ? null
                      : () {
                          Clipboard.setData(
                            ClipboardData(text: _targets[link.name]!),
                          );
                          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                            SnackBar(
                              content: Text(l10n.vaultListingLinkTargetCopied),
                            ),
                          );
                        },
                ),
            ],
          ],
        ),
      ),
    );
  }
}
