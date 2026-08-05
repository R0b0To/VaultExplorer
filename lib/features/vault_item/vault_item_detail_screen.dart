import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/vault_items_service.dart';
import 'package:vaultexplorer/core/utils/file_type_utils.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/features/vault_item/vault_item_edit_screen.dart';

class VaultItemDetailScreen extends StatefulWidget {
  final MountedContainer container;
  final VaultItem item;
  final String filePath;
  const VaultItemDetailScreen({
    super.key,
    required this.container,
    required this.item,
    required this.filePath,
  });
  @override
  State<VaultItemDetailScreen> createState() => _VaultItemDetailScreenState();
}

class _VaultItemDetailScreenState extends State<VaultItemDetailScreen> {
  late VaultItem _item;
  late String _currentFilePath;
  final Map<String, bool> _revealed = {};
  bool _isContainerLocked = false;

  void _onContainerLockedEvent(int volId) {
    if (volId == widget.container.volId && mounted) {
      setState(() => _isContainerLocked = true);
    }
  }

  @override
  void initState() {
    super.initState();
    VaultExplorerApi.addContainerLockedListener(_onContainerLockedEvent);
    _item = widget.item;
    _currentFilePath = widget.filePath;
  }

  @override
  void dispose() {
    VaultExplorerApi.removeContainerLockedListener(_onContainerLockedEvent);
    super.dispose();
  }

  Future<void> _delete() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: context.l10n.deleteItemTitle,
      message: context.l10n.deleteItemMessage(_item.title),
      confirmLabel: context.l10n.delete,
      isDestructive: true,
    );
    if (!confirm || !mounted) return;
    await vaultExplorerApi.deleteFile(widget.container, _currentFilePath);
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _edit() async {
    final resultPath = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => VaultItemEditScreen(
          container: widget.container,
          type: _item.type,
          existing: _item,
          filePath: _currentFilePath,
          currentDirPath: '',
        ),
      ),
    );
    if (resultPath != null && mounted) {
      final updated = await VaultItemsService.instance.loadItem(widget.container, resultPath);
      if (updated != null) {
        setState(() {
          _item = updated;
          _currentFilePath = resultPath;
        });
      }
    }
  }

  Future<void> _toggleFavourite() async {
    final updated = _item.copyWithFavourite(!_item.favourite);
    await VaultItemsService.instance.saveItem(widget.container, _currentFilePath, updated);
    setState(() { _item = updated; });
  }

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    showAppSnackBar(
      context,
      message: context.l10n.labelCopiedToClipboard(label),
      tone: AppBannerTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isContainerLocked) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: SizedBox.expand(),
      );
    }
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fields = _item.vaultFields(context.l10n).where((f) => f.value.isNotEmpty).toList();
    return PopScope(
      canPop: true,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_item.title),
          actions: [
            IconButton(
              icon: Icon(
                _item.favourite ? Icons.star_rounded : Icons.star_outline_rounded,
                color: _item.favourite ? context.semanticColors.favourite : null,
              ),
              onPressed: _toggleFavourite,
              tooltip: _item.favourite ? context.l10n.removeFromFavourites : context.l10n.addToFavourites,
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: _edit,
              tooltip: context.l10n.edit,
            ),
            PopupMenuButton<String>(
              onSelected: (v) { if (v == 'delete') _delete(); },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded, color: cs.error, size: AppIconSize.standard),
                    const SizedBox(width: 12),
                    Text(context.l10n.delete, style: TextStyle(color: cs.error)),
                  ]),
                ),
              ],
            ),
          ],
        ),
        body: ListView(
          padding: AppSpacing.pagePadding,
          children: [
            _HeaderCard(item: _item),
            const SizedBox(height: 20),
            if (fields.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    context.l10n.noFieldsFilledIn,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              SectionLabel(context.l10n.sectionLabelDetails),
              AppCard.rows(
                dividerIndent: 16,
                children: fields
                    .map(
                      (f) => _FieldRow(
                        field: f,
                        revealed: _revealed[f.key] ?? false,
                        onReveal: () => setState(() =>
                            _revealed[f.key] = !(_revealed[f.key] ?? false)),
                        onCopy: () => _copy(f.label, f.value),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            SectionLabel(context.l10n.sectionLabelInfo),
            AppCard.rows(
              dividerIndent: 16,
              children: [
                _MetaRow(label: context.l10n.metaLabelType, value: _item.type.label(context.l10n)),
                _MetaRow(label: context.l10n.metaLabelCreated, value: _formatDate(_item.createdAt)),
                _MetaRow(label: context.l10n.metaLabelModified, value: _formatDate(_item.updatedAt)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return DateFormat('MMM d, y  HH:mm', context.l10n.localeName).format(dt);
  }
}

// ── Header card ───────────────────────────────────────────────────────────────
class _HeaderCard extends StatelessWidget {
  final VaultItem item;
  const _HeaderCard({required this.item});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final icon  = vaultIconForExt(item.type.name)  ?? Icons.lock_rounded;
    final color = vaultColorForExt(item.type.name) ?? cs.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Icon(icon, size: 26, color: color),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        item.type.label(context.l10n),
                        style: textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (item.favourite) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.star_rounded,
                        size: AppIconSize.inline,
                        color: context.semanticColors.favourite,
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final VaultField field;
  final bool revealed;
  final VoidCallback onReveal;
  final VoidCallback onCopy;
  const _FieldRow({
    required this.field,
    required this.revealed,
    required this.onReveal,
    required this.onCopy,
  });
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isSecret = field.type == FieldType.secret;
    final displayValue = isSecret && !revealed
        ? '•' * (field.value.length.clamp(6, 16))
        : field.value;
    return InkWell(
      onLongPress: onCopy,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    field.label,
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    displayValue,
                    style: textTheme.bodyMedium?.copyWith(
                      fontFamily: isSecret && !revealed ? 'monospace' : null,
                      letterSpacing: isSecret && !revealed ? 2 : null,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isSecret)
                  PasswordVisibilityToggle(
                    obscured: !revealed,
                    onToggle: onReveal,
                  ),
                IconButton(
                  icon: Icon(Icons.copy_rounded, size: AppIconSize.small, color: cs.onSurfaceVariant),
                  onPressed: onCopy,
                  visualDensity: VisualDensity.compact,
                  tooltip: context.l10n.copyFieldTooltip(field.label),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetaRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(label, style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const Spacer(),
          Text(value, style: textTheme.bodySmall),
        ],
      ),
    );
  }
}