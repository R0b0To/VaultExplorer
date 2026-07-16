import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/vaultexplorer_api.dart';
import '../../models/mounted_container.dart';
import '../../models/vault_item.dart';
import '../../services/vault_items_service.dart';
import '../../utils/file_type_utils.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';
import 'vault_item_edit_screen.dart';

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


  @override
  void initState() {
    super.initState();
    _item = widget.item;
    _currentFilePath = widget.filePath;
  }

  Future<void> _delete() async {

    final confirm = await showAppConfirmDialog(
      context,
      title: 'Delete item?',
      message: '"${_item.title}" will be permanently deleted from the vault.',
      confirmLabel: 'Delete',
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
      message: '$label copied to clipboard',
      tone: AppBannerTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final fields = _item.vaultFields.where((f) => f.value.isNotEmpty).toList();

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
              tooltip: _item.favourite ? 'Remove from favourites' : 'Add to favourites',
            ),
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              onPressed: _edit,
              tooltip: 'Edit',
            ),
            PopupMenuButton<String>(
              onSelected: (v) { if (v == 'delete') _delete(); },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline_rounded, color: cs.error, size: AppIconSize.standard),
                    const SizedBox(width: 12),
                    Text('Delete', style: TextStyle(color: cs.error)),
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
                    'No fields filled in.\nTap Edit to add details.',
                    style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              const SectionLabel('Details'),
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
            const SectionLabel('Info'),
            AppCard.rows(
              dividerIndent: 16,
              children: [
                _MetaRow(label: 'Type', value: _item.type.label),
                _MetaRow(label: 'Created', value: _formatDate(_item.createdAt)),
                _MetaRow(label: 'Modified', value: _formatDate(_item.updatedAt)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
    // Delegates to the shared helpers; type.name matches the extension key
    // (VaultItemType.password.name == 'password', etc.).
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
                        item.type.label,
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

// ── Field row ─────────────────────────────────────────────────────────────────

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
                // FIX: previously a bespoke IconButton pair — now routed
                // through the shared PasswordVisibilityToggle so the
                // reveal/hide glyph pair can never diverge from the other
                // secret-reveal controls in the app (vault_item_edit_screen,
                // password fields, etc).
                if (isSecret)
                  PasswordVisibilityToggle(
                    obscured: !revealed,
                    onToggle: onReveal,
                  ),
                IconButton(
                  icon: Icon(Icons.copy_rounded, size: AppIconSize.small, color: cs.onSurfaceVariant),
                  onPressed: onCopy,
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Copy ${field.label}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Meta row ──────────────────────────────────────────────────────────────────

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