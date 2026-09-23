import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/dashboard/vault_dashboard_controller.dart';
import 'package:vaultexplorer/features/sync/data/config/sync_config_store.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_plan.dart';
import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';
import 'package:vaultexplorer/features/sync/domain/sync_rule_validation.dart';
import 'package:vaultexplorer/features/sync/services/sync_providers.dart';
import 'package:vaultexplorer/features/sync/ui/sync_labels.dart';
// The manual Vault Sync tool has its own, unrelated `SyncDirection`; only
// the picker's result type is needed from that file.
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart'
    show VaultSyncSide;
import 'package:vaultexplorer/features/tools/widgets/vault_sync_location_picker_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_sync_target_style.dart';

/// Auto-sync settings for one folder of an unlocked vault: which folder it
/// is kept in step with, in which direction, what happens when both sides
/// changed a file, and when syncing runs.
///
/// One rule per vault folder. Saving writes the rule into the vault's
/// `/.vaultexplorer/sync_config.json` and this device's choice of target
/// into secure storage, then tells the coordinator to pick the change up.
class SyncRuleEditorSheet extends ConsumerStatefulWidget {
  final MountedContainer vault;

  /// The folder inside the vault, relative to its root.
  final String folderPath;
  final String folderName;

  const SyncRuleEditorSheet({
    super.key,
    required this.vault,
    required this.folderPath,
    required this.folderName,
  });

  static Future<void> show(
    BuildContext context, {
    required MountedContainer vault,
    required String folderPath,
    required String folderName,
  }) {
    return Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SyncRuleEditorSheet(
          vault: vault,
          folderPath: folderPath,
          folderName: folderName,
        ),
      ),
    );
  }

  @override
  ConsumerState<SyncRuleEditorSheet> createState() => _SyncRuleEditorSheetState();
}

class _SyncRuleEditorSheetState extends ConsumerState<SyncRuleEditorSheet> {
  static const _conflictOrder = [
    ConflictStrategy.renameConflict,
    ConflictStrategy.keepNewer,
    ConflictStrategy.vaultWins,
    ConflictStrategy.targetWins,
  ];

  final TextEditingController _ignore = TextEditingController(
    text: SyncRule.defaultIgnorePatterns.join('\n'),
  );

  bool _loading = true;
  bool _configBroken = false;
  bool _saving = false;

  SyncConfig? _config;
  SyncRule? _existing;
  SyncRunReport? _report;
  SyncRuleProblem? _problem;

  // What this device syncs with (from the rule's binding, or the config's
  // portable default, or a fresh pick).
  String _targetUri = '';
  String _targetSub = '';
  String _targetName = '';
  IconData _targetIcon = Icons.folder_open_rounded;
  bool _targetNotSetHere = false;

  SyncDirection _direction = SyncDirection.twoWay;
  ConflictStrategy _conflict = ConflictStrategy.renameConflict;
  bool _onUnlock = true;
  bool _live = false;
  bool _deletes = false;

  String _initialTargetUri = '';
  String _initialTargetSub = '';
  SyncDirection _initialDirection = SyncDirection.twoWay;
  ConflictStrategy _initialConflict = ConflictStrategy.renameConflict;
  bool _initialOnUnlock = true;
  bool _initialLive = false;
  bool _initialDeletes = false;
  String _initialIgnore = '';

  bool get _readOnly => widget.vault.readOnly;
  bool get _canSave => !_readOnly && !_saving;

  bool get _isDirty {
    if (_existing == null) {
      return _targetUri.isNotEmpty ||
          _direction != _initialDirection ||
          _conflict != _initialConflict ||
          _onUnlock != _initialOnUnlock ||
          _live != _initialLive ||
          _deletes != _initialDeletes ||
          _ignore.text.trim() != _initialIgnore.trim();
    }
    return _targetUri != _initialTargetUri ||
        _targetSub != _initialTargetSub ||
        _direction != _initialDirection ||
        _conflict != _initialConflict ||
        _onUnlock != _initialOnUnlock ||
        _live != _initialLive ||
        _deletes != _initialDeletes ||
        _ignore.text.trim() != _initialIgnore.trim();
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _ignore.addListener(_onFieldChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    _ignore.removeListener(_onFieldChanged);
    _ignore.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    SyncConfig config;
    try {
      config = await ref.read(syncConfigStoreProvider).loadOrCreate(widget.vault);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _configBroken = true;
      });
      return;
    }

    final folder = normalizeSyncPath(widget.folderPath);
    final existing = config.rules.where((r) => r.vaultRelativePath == folder).firstOrNull;
    SyncTargetBinding? binding;
    if (existing != null) {
      binding = await ref
          .read(syncTargetBindingStoreProvider)
          .read(config.vaultSyncId, existing.id);
    }
    final report = existing == null
        ? null
        : ref.read(syncCoordinatorServiceProvider).lastReportFor(widget.vault, existing.id);
    if (!mounted) return;

    setState(() {
      _config = config;
      _existing = existing;
      _report = report;
      if (existing != null) {
        _targetUri = binding?.uri ?? existing.targetEndpointUri;
        _targetSub = binding != null
            ? normalizeSyncPath(binding.subPath)
            : existing.targetRelativePath;
        _targetName = (binding?.displayName.isNotEmpty ?? false)
            ? binding!.displayName
            : existing.targetDisplayName;
        _targetNotSetHere =
            binding == null && existing.targetEndpointUri.startsWith('content://');
        _direction = existing.direction;
        _conflict = existing.conflictStrategy;
        _onUnlock = existing.autoSyncOnUnlock;
        _live = existing.liveWatch;
        _deletes = existing.deleteOrphans;
        _ignore.text = existing.ignorePatterns.join('\n');
      }
      _initialTargetUri = _targetUri;
      _initialTargetSub = _targetSub;
      _initialDirection = _direction;
      _initialConflict = _conflict;
      _initialOnUnlock = _onUnlock;
      _initialLive = _live;
      _initialDeletes = _deletes;
      _initialIgnore = _ignore.text;
      _loading = false;
    });
  }

  String get _targetLabel {
    if (_targetName.isNotEmpty) return _targetName;
    final tail = _targetUri.split('/').where((s) => s.isNotEmpty).lastOrNull;
    return tail ?? _targetUri;
  }

  Future<void> _pickTarget() async {
    final containers = ref.read(vaultDashboardControllerProvider).mounted;
    final sideLabel = context.l10n.autoSyncPickerSideLabel;
    final side = await Navigator.push<VaultSyncSide>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultSyncLocationPickerSheet(
          mountedContainers: containers,
          sideLabel: sideLabel,
          isLeft: false,
        ),
      ),
    );
    if (side == null || !mounted) return;

    final sub = normalizeSyncPath(side.relativePath);
    setState(() {
      _targetUri = side.container.uri;
      _targetSub = sub;
      _targetName = sub.isEmpty ? side.container.displayName : sub.split('/').last;
      _targetIcon = side.kind.icon;
      _targetNotSetHere = false;
      _problem = null;
    });
  }

  List<String> get _patterns => _ignore.text
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<void> _save({required bool syncAfter}) async {
    final config = _config;
    if (config == null || !_canSave) return;
    final l10n = context.l10n;
    final existing = _existing;
    final id = existing?.id ?? generateSyncId();

    // What this device will actually sync with -- what gets validated.
    final effective = SyncRule(
      id: id,
      vaultInternalPath: normalizeSyncPath(widget.folderPath),
      targetEndpointUri: _targetUri,
      targetSubPath: _targetSub,
      targetDisplayName: _targetName,
      direction: _direction,
      conflictStrategy: _conflict,
      autoSyncOnUnlock: _onUnlock,
      liveWatch: _live,
      deleteOrphans: _deletes,
      ignorePatterns: _patterns,
      lastSyncedAt: existing?.lastSyncedAt,
    );
    final problem = validateSyncRule(
      candidate: effective,
      vaultUri: widget.vault.uri,
      others: config.rules,
    );
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    setState(() {
      _problem = null;
      _saving = true;
    });

    // The config is shared by every device that opens this vault, so the
    // target written into it is only the default set when the rule is
    // created; picking a different folder later changes only this device's
    // binding.
    final stored = existing == null
        ? effective
        : effective.copyWith(
            targetEndpointUri: existing.targetEndpointUri,
            targetSubPath: existing.targetSubPath,
            targetDisplayName: existing.targetDisplayName,
          );
    final rules = existing == null
        ? [...config.rules, stored]
        : [for (final r in config.rules) r.id == id ? stored : r];

    final ok = await ref
        .read(syncConfigStoreProvider)
        .save(widget.vault, config.copyWith(rules: rules));
    if (ok) {
      try {
        await ref
            .read(syncTargetBindingStoreProvider)
            .write(
              config.vaultSyncId,
              id,
              SyncTargetBinding(
                uri: _targetUri,
                displayName: _targetName,
                subPath: _targetSub,
              ),
            );
      } catch (_) {
        // Without a binding the rule falls back to the config's default
        // target, which for a new rule is this same pick.
      }
      await ref.read(syncCoordinatorServiceProvider).reloadConfig(widget.vault);
      final syncedPaths = rules
          .where((r) => r.autoSyncOnUnlock || r.liveWatch)
          .map((r) => r.vaultRelativePath)
          .toSet();
      ref
          .read(vaultSyncedFolderPathsProvider(widget.vault).notifier)
          .update(syncedPaths);
    }
    if (!mounted) return;

    if (!ok) {
      setState(() => _saving = false);
      showAppSnackBar(
        context,
        message: l10n.autoSyncSaveFailed,
        tone: AppBannerTone.error,
      );
      return;
    }

    var message = l10n.autoSyncSaved;
    var tone = AppBannerTone.success;
    if (syncAfter) {
      final started = ref.read(syncCoordinatorServiceProvider).syncNow(widget.vault, id);
      message = started ? l10n.autoSyncStarted : l10n.autoSyncUnavailable;
      if (!started) tone = AppBannerTone.warning;
    }
    showAppSnackBar(context, message: message, tone: tone);
    Navigator.of(context).pop();
  }

  Future<void> _remove() async {
    final config = _config;
    final existing = _existing;
    if (config == null || existing == null || _readOnly || _saving) return;
    final l10n = context.l10n;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.autoSyncRemoveTitle),
        content: Text(l10n.autoSyncRemoveMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.remove),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    final remainingRules = [
      for (final r in config.rules)
        if (r.id != existing.id) r
    ];
    final ok = await ref.read(syncConfigStoreProvider).save(
      widget.vault,
      config.copyWith(rules: remainingRules),
    );
    if (ok) {
      try {
        await ref.read(syncTargetBindingStoreProvider).delete(config.vaultSyncId, existing.id);
      } catch (_) {}
      await ref.read(syncCoordinatorServiceProvider).reloadConfig(widget.vault);
      final syncedPaths = remainingRules
          .where((r) => r.autoSyncOnUnlock || r.liveWatch)
          .map((r) => r.vaultRelativePath)
          .toSet();
      ref
          .read(vaultSyncedFolderPathsProvider(widget.vault).notifier)
          .update(syncedPaths);
    }
    if (!mounted) return;

    if (!ok) {
      setState(() => _saving = false);
      showAppSnackBar(
        context,
        message: l10n.autoSyncSaveFailed,
        tone: AppBannerTone.error,
      );
      return;
    }
    showAppSnackBar(context, message: l10n.autoSyncRemoved);
    Navigator.of(context).pop();
  }

  String _problemText(SyncRuleProblem problem) {
    final l10n = context.l10n;
    return switch (problem) {
      SyncRuleProblem.noTarget => l10n.autoSyncProblemNoTarget,
      SyncRuleProblem.overlapsTarget => l10n.autoSyncProblemOverlapsTarget,
      SyncRuleProblem.overlapsOtherRule => l10n.autoSyncProblemOverlapsOtherRule,
    };
  }

  // ── build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            l10n.autoSyncSheetTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: const Center(child: CircularProgressIndicator(strokeWidth: 2.5)),
      );
    }
    if (_configBroken) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text(
            l10n.autoSyncSheetTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: InlineBanner(l10n.autoSyncConfigUnreadable, tone: AppBannerTone.error),
        ),
      );
    }

    final isDirty = _isDirty;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.autoSyncSheetTitle,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (widget.folderName.isNotEmpty)
              Text(
                widget.folderName,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: _canSave ? () => _save(syncAfter: true) : null,
                icon: const Icon(Icons.sync_rounded, size: 18),
                label: Text(l10n.autoSyncSyncNow),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, isDirty ? 96 : 24),
                  children: [
                    Text(
                      l10n.autoSyncSheetIntro,
                      style: textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (_readOnly) ...[
                      const SizedBox(height: 12),
                      InlineBanner(l10n.autoSyncReadOnlyNotice, tone: AppBannerTone.warning),
                    ],
                    const SizedBox(height: 12),

                    // Target Folder Selection
                    SectionHeader(l10n.autoSyncTargetSection),
                    SectionCard(
                      children: [
                        ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: cs.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(_targetIcon, color: cs.primary, size: 22),
                          ),
                          title: Text(
                            _targetUri.isEmpty ? l10n.autoSyncChooseFolder : _targetLabel,
                            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: (_targetUri.isEmpty || _targetSub.isEmpty)
                              ? null
                              : Text(
                                  _targetSub,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          onTap: _saving ? null : _pickTarget,
                        ),
                        if (_targetNotSetHere)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                            child: Text(
                              l10n.autoSyncTargetNotSetHere,
                              style: textTheme.bodySmall?.copyWith(color: cs.error),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Direction & Conflicts (Unified into OptionPickerTiles)
                    SectionHeader(l10n.autoSyncDirectionSection),
                    SectionCard(
                      children: [
                        OptionPickerTile<SyncDirection>(
                          label: l10n.autoSyncDirectionSection,
                          value: _direction,
                          subtitle: _direction.label(l10n),
                          options: SyncDirection.values.map((d) {
                            return SelectOption(
                              value: d,
                              label: d.label(l10n),
                              subtitle: d.hint(l10n),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _direction = v),
                        ),
                        OptionPickerTile<ConflictStrategy>(
                          label: l10n.autoSyncConflictSection,
                          value: _conflict,
                          subtitle: _conflict.label(l10n),
                          options: _conflictOrder.map((c) {
                            return SelectOption(
                              value: c,
                              label: c.label(l10n),
                              subtitle: c.hint(l10n),
                            );
                          }).toList(),
                          onChanged: (v) => setState(() => _conflict = v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Sync Options & Rules
                    SectionHeader(l10n.autoSyncOptionsSection),
                    SectionCard(
                      children: [
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            l10n.autoSyncOnUnlockTitle,
                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          value: _onUnlock,
                          onChanged: (v) => setState(() => _onUnlock = v),
                        ),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            l10n.autoSyncLiveTitle,
                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            l10n.autoSyncLiveSubtitle,
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          value: _live,
                          onChanged: (v) => setState(() => _live = v),
                        ),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                          title: Text(
                            l10n.autoSyncDeleteTitle,
                            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            l10n.autoSyncDeleteSubtitle,
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          value: _deletes,
                          onChanged: (v) => setState(() => _deletes = v),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: TextField(
                            controller: _ignore,
                            minLines: 2,
                            maxLines: 6,
                            keyboardType: TextInputType.multiline,
                            autocorrect: false,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: cs.surfaceContainerHighest,
                              labelText: l10n.autoSyncIgnoreLabel,
                              helperText: l10n.autoSyncIgnoreHelper,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    if (_existing != null) ...[
                      const SizedBox(height: 16),
                      SectionCard(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: _lastRun(textTheme, cs),
                          ),
                        ],
                      ),
                    ],

                    if (_problem != null) ...[
                      const SizedBox(height: 12),
                      InlineBanner(_problemText(_problem!), tone: AppBannerTone.error),
                    ],

                    if (_existing != null) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.center,
                        child: TextButton.icon(
                          style: TextButton.styleFrom(foregroundColor: cs.error),
                          onPressed: (_readOnly || _saving) ? null : _remove,
                          icon: const Icon(Icons.sync_disabled_rounded),
                          label: Text(l10n.autoSyncRemove),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // Floating Overlay Save Button (Appears when changes are made)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
              left: 16,
              right: 16,
              bottom: isDirty ? 16 : -80,
              child: IgnorePointer(
                ignoring: !isDirty,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Material(
                      elevation: 4,
                      shadowColor: Colors.black26,
                      borderRadius: BorderRadius.circular(28),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                        onPressed: _canSave
                            ? () {
                                final isInitialSync = _existing == null ||
                                    _existing?.lastSyncedAt == null ||
                                    _existing?.targetEndpointUri.isEmpty == true ||
                                    _targetUri != _initialTargetUri ||
                                    _targetSub != _initialTargetSub;
                                _save(syncAfter: isInitialSync);
                              }
                            : null,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded),
                        label: Text(
                          l10n.save,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// When it last synced, and what the latest run this session found.
  Widget _lastRun(TextTheme text, ColorScheme cs) {
    final l10n = context.l10n;
    final at = _existing?.lastSyncedAt;
    final report = _report;
    final muted = text.bodySmall?.copyWith(color: cs.onSurfaceVariant);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          at == null
              ? l10n.autoSyncNeverSynced
              : l10n.autoSyncLastSynced(formatEntryDate(at.millisecondsSinceEpoch ~/ 1000)),
          style: muted,
        ),
        if (report != null) ...[
          const SizedBox(height: 4),
          Text(
            l10n.autoSyncReportSummary(
              report.copied,
              report.deleted,
              report.conflictsKeptBoth,
            ),
            style: muted,
          ),
          if (report.failed > 0)
            Text(
              l10n.autoSyncReportFailed(report.failed),
              style: text.bodySmall?.copyWith(color: cs.error),
            ),
          if (report.deletionsBlocked)
            Text(
              l10n.autoSyncReportDeletionsPaused,
              style: text.bodySmall?.copyWith(color: cs.error),
            ),
          if (report.incompleteScan)
            Text(
              l10n.autoSyncReportIncomplete,
              style: text.bodySmall?.copyWith(color: cs.error),
            ),
        ],
      ],
    );
  }
}
