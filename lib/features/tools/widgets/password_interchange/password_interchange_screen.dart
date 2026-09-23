import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/layout/section_card.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_registry.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_interchange_service.dart';
import 'package:vaultexplorer/features/tools/models/tool_models.dart';
import 'package:vaultexplorer/features/tools/widgets/password_interchange/password_interchange_controller.dart';
import 'package:vaultexplorer/features/tools/widgets/vault_folder_picker_sheet.dart';

IconData _iconForType(VaultItemType type) => switch (type) {
      VaultItemType.password => Icons.key_rounded,
      VaultItemType.paymentCard => Icons.credit_card_rounded,
      VaultItemType.identity => Icons.badge_rounded,
      VaultItemType.secureNote => Icons.note_rounded,
      VaultItemType.bankAccount => Icons.account_balance_rounded,
      VaultItemType.softwareLicense => Icons.computer_rounded,
    };

/// Tools -> Import / Export Passwords: converts between the Item Vault and
/// KDBX/Bitwarden-JSON/CSV files, so a vault's logins, cards, identities,
/// notes, bank accounts and software licenses can move to or from another
/// password manager. See docs/password-interchange.md for the exact field
/// mapping each format uses and its limitations.
class PasswordInterchangeScreen extends ConsumerWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  const PasswordInterchangeScreen({super.key, required this.mountedContainers});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(passwordInterchangeProvider);
    final notifier = ref.read(passwordInterchangeProvider.notifier);
    final cs = context.colors;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.l10n.toolPasswordInterchangeTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SegmentedButton<PasswordInterchangeMode>(
                multiSelectionEnabled: false,
                emptySelectionAllowed: false,
                segments: [
                  ButtonSegment(
                    value: PasswordInterchangeMode.export,
                    label: Text(context.l10n.passwordInterchangeExportTab),
                    icon: const Icon(Icons.upload_rounded, size: 18),
                  ),
                  ButtonSegment(
                    value: PasswordInterchangeMode.import,
                    label: Text(context.l10n.passwordInterchangeImportTab),
                    icon: const Icon(Icons.download_rounded, size: 18),
                  ),
                ],
                selected: {state.mode},
                onSelectionChanged: (s) => notifier.setMode(s.first),
              ),
            ),
            if (state.error != null) _ErrorBanner(message: state.error!),
            if (state.busy) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: state.mode == PasswordInterchangeMode.export
                  ? _ExportBody(mountedContainers: mountedContainers)
                  : _ImportBody(mountedContainers: mountedContainers),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: cs.onErrorContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: cs.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class _FormatPicker extends StatelessWidget {
  final List<PasswordFormatCodec> formats;
  final PasswordFormatCodec selected;
  final ValueChanged<PasswordFormatCodec> onChanged;
  const _FormatPicker({required this.formats, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<PasswordFormatCodec>(
          initialValue: formats.contains(selected) ? selected : formats.first,
          decoration: InputDecoration(
            labelText: context.l10n.passwordInterchangeFormatLabel,
            border: const OutlineInputBorder(),
          ),
          items: [
            for (final f in formats) DropdownMenuItem(value: f, child: Text(f.displayName)),
          ],
          onChanged: (f) {
            if (f != null) onChanged(f);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, left: 4, right: 4),
          child: Text(
            selected.description,
            style: context.typography.bodySmall?.copyWith(color: context.colors.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

// ── EXPORT ──────────────────────────────────────────────────────────────────

class _ExportBody extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  const _ExportBody({required this.mountedContainers});

  @override
  ConsumerState<_ExportBody> createState() => _ExportBodyState();
}

class _ExportBodyState extends ConsumerState<_ExportBody> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _pickSource() async {
    final containers = widget.mountedContainers.value;
    if (containers.isEmpty) return;
    final result = await Navigator.of(context).push<CryptoDestination>(
      MaterialPageRoute(builder: (_) => VaultFolderPickerSheet(mountedContainers: containers)),
    );
    if (result == null || !mounted) return;
    ref.read(passwordInterchangeProvider.notifier).setExportSource(
          container: result.container!,
          folderPath: result.relativePath!,
        );
  }

  Future<void> _saveAs() async {
    final notifier = ref.read(passwordInterchangeProvider.notifier);
    final format = ref.read(passwordInterchangeProvider).exportFormat;
    final folder = await ref.read(vaultLifecycleApiProvider).pickExtractFolder();
    if (folder == null || !mounted) return;
    final containerName = ref.read(passwordInterchangeProvider).exportContainer?.displayName ?? 'vault';
    await notifier.saveExportedFile(
      destinationPath: folder.path,
      destinationTreeUri: folder.treeUri,
      fileName: '$containerName-passwords.${format.id == 'bitwarden_json' ? 'json' : format.id}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(passwordInterchangeProvider);
    final notifier = ref.read(passwordInterchangeProvider.notifier);
    final needsPassword = state.exportFormat.isEncrypted;
    final passwordsMatch = !needsPassword || _passwordController.text == _confirmController.text;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SectionHeader(context.l10n.passwordInterchangeSourceHeader),
        SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: Text(
                state.exportContainer == null
                    ? context.l10n.passwordInterchangeChooseFolder
                    : '${state.exportContainer!.displayName} / ${state.exportFolderPath.isEmpty ? context.l10n.vaultFolderPickerRootLabel : state.exportFolderPath}',
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: _pickSource,
            ),
            SwitchListTile(
              title: Text(context.l10n.passwordInterchangeIncludeSubfolders),
              value: state.exportRecursive,
              onChanged: (v) => notifier.setExportRecursive(v),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SectionHeader(context.l10n.passwordInterchangeFormatHeader),
        _FormatPicker(
          formats: kExportablePasswordFormats,
          selected: state.exportFormat,
          onChanged: notifier.setExportFormat,
        ),
        if (needsPassword) ...[
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: context.l10n.passwordInterchangeMasterPassword,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmController,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: context.l10n.passwordInterchangeConfirmPassword,
              border: const OutlineInputBorder(),
              errorText: _confirmController.text.isNotEmpty && !passwordsMatch
                  ? context.l10n.passwordInterchangePasswordsDontMatch
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        FilledButton.icon(
          icon: const Icon(Icons.upload_rounded),
          label: Text(context.l10n.passwordInterchangeRunExport),
          onPressed: state.busy || state.exportContainer == null || (needsPassword && (!passwordsMatch || _passwordController.text.isEmpty))
              ? null
              : () => notifier.runExport(password: needsPassword ? _passwordController.text : null),
        ),
        if (state.exportedBytes != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionCard(
            children: [
              ListTile(
                leading: Icon(Icons.check_circle_rounded, color: context.colors.primary),
                title: Text(
                  context.l10n.passwordInterchangeExportReady(state.exportCollected?.length ?? 0),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.save_alt_rounded),
                title: Text(context.l10n.passwordInterchangeSaveToDevice),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: state.busy ? null : _saveAs,
              ),
            ],
          ),
          if (state.exportSaved)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                context.l10n.passwordInterchangeSaved,
                style: TextStyle(color: context.colors.primary),
              ),
            ),
        ],
      ],
    );
  }
}

// ── IMPORT ──────────────────────────────────────────────────────────────────

class _ImportBody extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  const _ImportBody({required this.mountedContainers});

  @override
  ConsumerState<_ImportBody> createState() => _ImportBodyState();
}

class _ImportBodyState extends ConsumerState<_ImportBody> {
  final _passwordController = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickDestination() async {
    final containers = widget.mountedContainers.value;
    if (containers.isEmpty) return;
    final result = await Navigator.of(context).push<CryptoDestination>(
      MaterialPageRoute(builder: (_) => VaultFolderPickerSheet(mountedContainers: containers)),
    );
    if (result == null || !mounted) return;
    ref.read(passwordInterchangeProvider.notifier).setImportDestination(
          container: result.container!,
          folderPath: result.relativePath!,
        );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(passwordInterchangeProvider);
    final notifier = ref.read(passwordInterchangeProvider.notifier);
    final l10n = context.l10n;

    if (state.importResult != null) {
      return _ImportResultView(result: state.importResult!, onDone: notifier.reset);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SectionHeader(l10n.passwordInterchangeFileHeader),
        SectionCard(
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(state.importFileName ?? l10n.passwordInterchangeChooseFile),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: state.busy ? null : notifier.pickImportFile,
            ),
          ],
        ),
        if (state.importBytes != null) ...[
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(l10n.passwordInterchangeFormatHeader),
          _FormatPicker(
            formats: kImportablePasswordFormats,
            selected: state.importFormat,
            onChanged: notifier.setImportFormat,
          ),
          if (state.importFormat.isEncrypted && state.decoded == null) ...[
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: l10n.passwordInterchangeMasterPassword,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_rounded : Icons.visibility_off_rounded),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => notifier.decodeImportFile(password: _passwordController.text),
            ),
            const SizedBox(height: 8),
          ],
          if (state.decoded == null)
            FilledButton.icon(
              icon: const Icon(Icons.search_rounded),
              label: Text(l10n.passwordInterchangeReadFile),
              onPressed: state.busy
                  ? null
                  : () => notifier.decodeImportFile(
                        password: state.importFormat.isEncrypted ? _passwordController.text : null,
                      ),
            ),
        ],
        if (state.decoded != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.passwordInterchangeFoundItems(state.decoded!.length),
                  style: context.typography.titleSmall,
                ),
              ),
              TextButton(onPressed: notifier.selectAll, child: Text(l10n.passwordInterchangeSelectAll)),
              TextButton(onPressed: notifier.selectNone, child: Text(l10n.passwordInterchangeSelectNone)),
            ],
          ),
          if (state.decodeWarnings.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.passwordInterchangeWarningsCount(state.decodeWarnings.length),
                style: TextStyle(color: context.colors.error),
              ),
            ),
          ...List.generate(state.decoded!.length, (i) {
            final r = state.decoded![i];
            return CheckboxListTile(
              value: state.selected.contains(i),
              onChanged: (_) => notifier.toggleSelected(i),
              secondary: Icon(_iconForType(r.type)),
              title: Text(r.title.isEmpty ? '(untitled)' : r.title),
              subtitle: r.previewSubtitle.isEmpty ? null : Text(r.previewSubtitle),
              dense: true,
            );
          }),
          const SizedBox(height: AppSpacing.lg),
          SectionHeader(l10n.passwordInterchangeDestinationHeader),
          SectionCard(
            children: [
              ListTile(
                leading: const Icon(Icons.folder_rounded),
                title: Text(
                  state.importContainer == null
                      ? l10n.passwordInterchangeChooseFolder
                      : '${state.importContainer!.displayName} / ${state.importFolderPath.isEmpty ? l10n.vaultFolderPickerRootLabel : state.importFolderPath}',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: _pickDestination,
              ),
              SwitchListTile(
                title: Text(l10n.passwordInterchangeMirrorFolders),
                value: state.importMirrorFolders,
                onChanged: notifier.setImportMirrorFolders,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            icon: const Icon(Icons.download_rounded),
            label: Text(l10n.passwordInterchangeRunImport(state.selectedCount)),
            onPressed: state.busy || state.importContainer == null || state.selectedCount == 0 ? null : notifier.runImport,
          ),
        ],
      ],
    );
  }
}

class _ImportResultView extends StatelessWidget {
  final PasswordImportOutcome result;
  final VoidCallback onDone;
  const _ImportResultView({required this.result, required this.onDone});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: [
        Icon(Icons.check_circle_rounded, color: cs.primary, size: 48),
        const SizedBox(height: 12),
        Text(
          l10n.passwordInterchangeImportedCount(result.imported),
          style: context.typography.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (result.skipped > 0)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.passwordInterchangeSkippedCount(result.skipped),
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.error),
            ),
          ),
        for (final e in result.errors.take(10))
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('• $e', style: context.typography.bodySmall),
          ),
        const SizedBox(height: AppSpacing.lg),
        FilledButton(onPressed: onDone, child: Text(l10n.close)),
      ],
    );
  }
}
