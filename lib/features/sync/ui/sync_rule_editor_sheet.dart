import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/feedback/app_feedback.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';
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
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => SyncRuleEditorSheet(
        vault: vault,
        folderPath: folderPath,
        folderName: folderName,
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

  bool get _readOnly => widget.vault.readOnly;
  // Enabled even before a folder is chosen, so that pressing Save explains
  // what is missing instead of silently doing nothing.
  bool get _canSave => !_readOnly && !_saving;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _ignore.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    SyncConfig config;
    try {
      config = await ref.read(syncConfigStoreProvider).loadOrCreate(widget.vault);
    } catch (_) {
      // Unreadable config: show that, and never offer to write a new one
      // over it.
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
        // A document-provider URI from another phone means nothing here.
        _targetNotSetHere =
            binding == null && existing.targetEndpointUri.startsWith('content://');
        _direction = existing.direction;
        _conflict = existing.conflictStrategy;
        _onUnlock = existing.autoSyncOnUnlock;
        _live = existing.liveWatch;
        _deletes = existing.deleteOrphans;
        _ignore.text = existing.ignorePatterns.join('\n');
      }
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
    final ok = await ref.read(syncConfigStoreProvider).save(
      widget.vault,
      config.copyWith(rules: [for (final r in config.rules) if (r.id != existing.id) r]),
    );
    if (ok) {
      try {
        await ref.read(syncTargetBindingStoreProvider).delete(config.vaultSyncId, existing.id);
      } catch (_) {}
      await ref.read(syncCoordinatorServiceProvider).reloadConfig(widget.vault);
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
    final cs = context.colors;
    final text = context.typography;

    if (_loading) {
      return const AppBottomSheet(
        child: SizedBox(height: 160, child: Center(child: CircularProgressIndicator())),
      );
    }
    if (_configBroken) {
      return AppBottomSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(text, cs),
            const SizedBox(height: 16),
            InlineBanner(l10n.autoSyncConfigUnreadable, tone: AppBannerTone.error),
          ],
        ),
      );
    }

    return AppBottomSheet(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(text, cs),
            const SizedBox(height: 8),
            Text(
              l10n.autoSyncSheetIntro,
              style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (_readOnly) ...[
              const SizedBox(height: 12),
              InlineBanner(l10n.autoSyncReadOnlyNotice, tone: AppBannerTone.warning),
            ],

            _section(l10n.autoSyncTargetSection),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_targetIcon, color: cs.primary),
              title: Text(
                _targetUri.isEmpty ? l10n.autoSyncChooseFolder : _targetLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: (_targetUri.isEmpty || _targetSub.isEmpty)
                  ? null
                  : Text(_targetSub, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _saving ? null : _pickTarget,
            ),
            if (_targetNotSetHere)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  l10n.autoSyncTargetNotSetHere,
                  style: text.bodySmall?.copyWith(color: cs.error),
                ),
              ),

            _section(l10n.autoSyncDirectionSection),
            RadioGroup<SyncDirection>(
              groupValue: _direction,
              onChanged: (v) {
                if (v != null) setState(() => _direction = v);
              },
              child: Column(
                children: [
                  for (final d in SyncDirection.values)
                    RadioListTile<SyncDirection>(
                      value: d,
                      contentPadding: EdgeInsets.zero,
                      title: Text(d.label(l10n)),
                      subtitle: Text(d.hint(l10n)),
                    ),
                ],
              ),
            ),

            _section(l10n.autoSyncConflictSection),
            RadioGroup<ConflictStrategy>(
              groupValue: _conflict,
              onChanged: (v) {
                if (v != null) setState(() => _conflict = v);
              },
              child: Column(
                children: [
                  for (final c in _conflictOrder)
                    RadioListTile<ConflictStrategy>(
                      value: c,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.label(l10n)),
                      subtitle: Text(c.hint(l10n)),
                    ),
                ],
              ),
            ),

            _section(l10n.autoSyncOptionsSection),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.autoSyncOnUnlockTitle),
              value: _onUnlock,
              onChanged: (v) => setState(() => _onUnlock = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.autoSyncLiveTitle),
              subtitle: Text(l10n.autoSyncLiveSubtitle),
              value: _live,
              onChanged: (v) => setState(() => _live = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.autoSyncDeleteTitle),
              subtitle: Text(l10n.autoSyncDeleteSubtitle),
              value: _deletes,
              onChanged: (v) => setState(() => _deletes = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ignore,
              minLines: 2,
              maxLines: 6,
              keyboardType: TextInputType.multiline,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: l10n.autoSyncIgnoreLabel,
                helperText: l10n.autoSyncIgnoreHelper,
                border: const OutlineInputBorder(),
              ),
            ),

            if (_existing != null) ...[
              const SizedBox(height: 16),
              _lastRun(text, cs),
            ],
            if (_problem != null) ...[
              const SizedBox(height: 12),
              InlineBanner(_problemText(_problem!), tone: AppBannerTone.error),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _canSave ? () => _save(syncAfter: true) : null,
                    icon: const Icon(Icons.sync_rounded),
                    label: Text(l10n.autoSyncSyncNow),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _canSave ? () => _save(syncAfter: false) : null,
                    child: Text(l10n.save),
                  ),
                ),
              ],
            ),
            if (_existing != null)
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
        ),
      ),
    );
  }

  Widget _header(TextTheme text, ColorScheme cs) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.primaryContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(Icons.sync_rounded, color: cs.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.autoSyncSheetTitle, style: text.titleMedium),
              Text(
                widget.folderName,
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String label) {
    final cs = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 4),
      child: Text(
        label,
        style: context.typography.labelLarge?.copyWith(color: cs.primary),
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
