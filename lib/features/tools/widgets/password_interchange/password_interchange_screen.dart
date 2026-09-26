import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/models/vault_item.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_codec.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_format_registry.dart';
import 'package:vaultexplorer/data/services/password_interchange/password_interchange_service.dart';
import 'package:vaultexplorer/data/services/session_lock_controller.dart';
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
      VaultItemType.authenticator => Icons.verified_user_rounded,
    };

/// Tools -> Import / Export Passwords: converts between the Item Vault and
/// KDBX/Bitwarden-JSON/CSV files, normalized to the standard tools design language.
class PasswordInterchangeScreen extends ConsumerWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  const PasswordInterchangeScreen({super.key, required this.mountedContainers});

  Widget _buildModeSegmentedButton(
    BuildContext context,
    PasswordInterchangeState state,
    WidgetRef ref, {
    required bool isCompact,
  }) {
    return SizedBox(
      width: isCompact ? null : double.infinity,
      child: SegmentedButton<PasswordInterchangeMode>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          side: BorderSide.none,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          textStyle: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        segments: [
          ButtonSegment(
            value: PasswordInterchangeMode.export,
            icon: const Icon(Icons.upload_rounded, size: 16),
            label: Text(
              context.l10n.passwordInterchangeExportTab,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
          ButtonSegment(
            value: PasswordInterchangeMode.import,
            icon: const Icon(Icons.download_rounded, size: 16),
            label: Text(
              context.l10n.passwordInterchangeImportTab,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
            ),
          ),
        ],
        selected: {state.mode},
        onSelectionChanged: state.busy
            ? null
            : (s) => ref.read(passwordInterchangeProvider.notifier).setMode(s.first),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(passwordInterchangeProvider);
    final cs = context.colors;
    final isLandscape = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          context.l10n.toolPasswordInterchangeTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (isLandscape) ...[
            _buildModeSegmentedButton(context, state, ref, isCompact: true),
            const SizedBox(width: 16),
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(2),
          child: state.busy
              ? const LinearProgressIndicator(minHeight: 2)
              : const SizedBox(height: 2),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: isLandscape
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 10)
              : AppSpacing.pagePadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!isLandscape) ...[
                _buildModeSegmentedButton(context, state, ref, isCompact: false),
                const SizedBox(height: AppSpacing.md),
              ],
              if (state.error != null) ...[
                InlineErrorBanner(state.error!),
                const SizedBox(height: AppSpacing.md),
              ],
              if (state.mode == PasswordInterchangeMode.export)
                _ExportBody(
                  mountedContainers: mountedContainers,
                  isLandscape: isLandscape,
                )
              else
                _ImportBody(
                  mountedContainers: mountedContainers,
                  isLandscape: isLandscape,
                ),
              const SizedBox(height: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }
}

// ── EXPORT BODY ─────────────────────────────────────────────────────────────

class _ExportBody extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  final bool isLandscape;

  const _ExportBody({
    required this.mountedContainers,
    required this.isLandscape,
  });

  @override
  ConsumerState<_ExportBody> createState() => _ExportBodyState();
}

class _ExportBodyState extends ConsumerState<_ExportBody> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _obscure = true;
  bool _confirmObscure = true;

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
    final folder = await ref.read(sessionLockControllerProvider).withLockSuppression(
      () => ref.read(vaultLifecycleApiProvider).pickExtractFolder(),
    );
    if (folder == null || !mounted) return;
    final containerName = ref.read(passwordInterchangeProvider).exportContainer?.displayName ?? 'vault';
    await notifier.saveExportedFile(
      destinationPath: folder.path,
      destinationTreeUri: folder.treeUri,
      fileName: '$containerName-passwords.${format.id == 'bitwarden_json' ? 'json' : format.id}',
    );
  }

  Widget _buildSourceFolderCard(
    BuildContext context,
    PasswordInterchangeState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    final hasSource = state.exportContainer != null;
    final sourcePath = hasSource
        ? '${state.exportContainer!.displayName} / ${state.exportFolderPath.isEmpty ? context.l10n.vaultFolderPickerRootLabel : state.exportFolderPath}'
        : context.l10n.passwordInterchangeChooseFolder;

   return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_outlined, size: AppIconSize.small, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.passwordInterchangeSourceHeader,
                        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        sourcePath,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: hasSource ? FontWeight.bold : FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: state.busy ? null : _pickSource,
                    child: Text(
                      context.l10n.chooseFolderButton,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                context.l10n.passwordInterchangeIncludeSubfolders,
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
              value: state.exportRecursive,
              onChanged: state.busy
                  ? null
                  : (v) => ref.read(passwordInterchangeProvider.notifier).setExportRecursive(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftControls(
    BuildContext context,
    PasswordInterchangeState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSourceFolderCard(context, state, cs, textTheme, isCompact: isCompact),
        const SizedBox(height: 10),
        OptionPickerTile<PasswordFormatCodec>(
          label: context.l10n.passwordInterchangeFormatLabel,
          value: state.exportFormat,
          prefixIcon: Icons.extension_rounded,
          subtitle: state.exportFormat.description,
          options: kExportablePasswordFormats
              .map((f) => SelectOption(
                    value: f,
                    label: f.displayName,
                    subtitle: f.description,
                  ))
              .toList(),
          onChanged: state.busy
              ? (_) {}
              : (f) => ref.read(passwordInterchangeProvider.notifier).setExportFormat(f),
        ),
      ],
    );
  }

  Widget _buildRightControls(
    BuildContext context,
    PasswordInterchangeState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    final notifier = ref.read(passwordInterchangeProvider.notifier);
    final needsPassword = state.exportFormat.isEncrypted;
    final passwordsMatch = !needsPassword || _passwordController.text == _confirmController.text;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (needsPassword) ...[
          TextField(
            controller: _passwordController,
            obscureText: _obscure,
            enabled: !state.busy,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: isCompact,
              labelText: context.l10n.passwordInterchangeMasterPassword,
              prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
              suffixIcon: PasswordVisibilityToggle(
                obscured: _obscure,
                onToggle: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _confirmController,
            obscureText: _confirmObscure,
            enabled: !state.busy,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: isCompact,
              labelText: context.l10n.passwordInterchangeConfirmPassword,
              prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
              errorText: _confirmController.text.isNotEmpty && !passwordsMatch
                  ? context.l10n.passwordInterchangePasswordsDontMatch
                  : null,
              suffixIcon: PasswordVisibilityToggle(
                obscured: _confirmObscure,
                onToggle: () => setState(() => _confirmObscure = !_confirmObscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        FilledButton(
          onPressed: state.busy || state.exportContainer == null || (needsPassword && (!passwordsMatch || _passwordController.text.isEmpty))
              ? null
              : () => notifier.runExport(password: needsPassword ? _passwordController.text : null),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            shape: const StadiumBorder(),
          ),
          child: state.busy
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                  ),
                )
              : Text(
                  context.l10n.passwordInterchangeRunExport,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
        ),
        if (state.exportedBytes != null) ...[
          const SizedBox(height: 12),
          InlineBanner(
            context.l10n.passwordInterchangeExportReady(state.exportCollected?.length ?? 0),
            tone: AppBannerTone.success,
            icon: Icons.check_circle_outline_rounded,
          ),
          const SizedBox(height: 10),
          if (state.exportSaved)
            InlineBanner(
              context.l10n.passwordInterchangeSaved,
              tone: AppBannerTone.success,
              icon: Icons.check_circle_rounded,
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.save_alt_rounded, size: 18),
              label: Text(
                context.l10n.passwordInterchangeSaveToDevice,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              onPressed: state.busy ? null : _saveAs,
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(passwordInterchangeProvider);
    final cs = context.colors;
    final textTheme = context.typography;

    if (widget.isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              child: _buildLeftControls(context, state, cs, textTheme, isCompact: true),
            ),
          ),
          const SizedBox(width: 16),
          const VerticalDivider(width: 1),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(
              child: _buildRightControls(context, state, cs, textTheme, isCompact: true),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildLeftControls(context, state, cs, textTheme, isCompact: false),
        const SizedBox(height: AppSpacing.md),
        _buildRightControls(context, state, cs, textTheme, isCompact: false),
      ],
    );
  }
}

// ── IMPORT BODY ─────────────────────────────────────────────────────────────

class _ImportBody extends ConsumerStatefulWidget {
  final ValueListenable<List<MountedContainer>> mountedContainers;
  final bool isLandscape;

  const _ImportBody({
    required this.mountedContainers,
    required this.isLandscape,
  });

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

  Future<void> _pickImportFile() async {
    await ref.read(sessionLockControllerProvider).withLockSuppression(
      () => ref.read(passwordInterchangeProvider.notifier).pickImportFile(),
    );
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

  Widget _buildFilePickerCard(
    BuildContext context,
    PasswordInterchangeState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    final l10n = context.l10n;
    final hasFile = state.importFileName != null;

    return Container(
      padding: EdgeInsets.all(isCompact ? 10 : 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, size: AppIconSize.small, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.passwordInterchangeFileHeader,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  state.importFileName ?? l10n.passwordInterchangeChooseFile,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: hasFile ? FontWeight.bold : FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: TextButton(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: state.busy ? null : _pickImportFile,
              child: Text(
                context.l10n.chooseFileButton,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationFolderCard(
    BuildContext context,
    PasswordInterchangeState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    final l10n = context.l10n;
    final hasDest = state.importContainer != null;
    final destPath = hasDest
        ? '${state.importContainer!.displayName} / ${state.importFolderPath.isEmpty ? l10n.vaultFolderPickerRootLabel : state.importFolderPath}'
        : l10n.passwordInterchangeChooseFolder;

   return Material(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.md),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.all(isCompact ? 10 : 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_rounded, size: AppIconSize.small, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.passwordInterchangeDestinationHeader,
                        style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      Text(
                        destPath,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: hasDest ? FontWeight.bold : FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: state.busy ? null : _pickDestination,
                    child: Text(
                      context.l10n.chooseFolderButton,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                l10n.passwordInterchangeMirrorFolders,
                style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
              ),
              value: state.importMirrorFolders,
              onChanged: state.busy
                  ? null
                  : (v) => ref.read(passwordInterchangeProvider.notifier).setImportMirrorFolders(v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDecodedItemsList(
    BuildContext context,
    PasswordInterchangeState state,
    ColorScheme cs,
    TextTheme textTheme, {
    required bool isCompact,
  }) {
    final notifier = ref.read(passwordInterchangeProvider.notifier);
    final l10n = context.l10n;
    final items = state.decoded ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.passwordInterchangeFoundItems(items.length),
                style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: state.busy ? null : notifier.selectAll,
              child: Text(l10n.passwordInterchangeSelectAll),
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: state.busy ? null : notifier.selectNone,
              child: Text(l10n.passwordInterchangeSelectNone),
            ),
          ],
        ),
        if (state.decodeWarnings.isNotEmpty) ...[
          const SizedBox(height: 4),
          InlineBanner(
            l10n.passwordInterchangeWarningsCount(state.decodeWarnings.length),
            tone: AppBannerTone.warning,
          ),
          const SizedBox(height: 6),
        ],
  ConstrainedBox(
          constraints: BoxConstraints(maxHeight: isCompact ? 200 : 280),
          child: Material(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.md),
            clipBehavior: Clip.antiAlias,
            child: Scrollbar(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 4),
                itemCount: items.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: cs.outlineVariant.withValues(alpha: 0.25),
                ),
                itemBuilder: (context, i) {
                  final r = items[i];
                  return CheckboxListTile(
                    value: state.selected.contains(i),
                    onChanged: state.busy ? null : (_) => notifier.toggleSelected(i),
                    secondary: Icon(_iconForType(r.type), color: cs.primary, size: 20),
                    title: Text(
                      r.title.isEmpty ? '(untitled)' : r.title,
                      style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    subtitle: r.previewSubtitle.isEmpty
                        ? null
                        : Text(
                            r.previewSubtitle,
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                    dense: true,
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(passwordInterchangeProvider);
    final notifier = ref.read(passwordInterchangeProvider.notifier);
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;

    if (state.importResult != null) {
      return _ImportResultCard(
        result: state.importResult!,
        onDone: notifier.reset,
      );
    }

    final isDecoded = state.decoded != null;

    final leftControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilePickerCard(context, state, cs, textTheme, isCompact: widget.isLandscape),
        const SizedBox(height: 10),
        if (state.importBytes != null) ...[
          OptionPickerTile<PasswordFormatCodec>(
            label: l10n.passwordInterchangeFormatLabel,
            value: state.importFormat,
            prefixIcon: Icons.extension_rounded,
            subtitle: state.importFormat.description,
            options: kImportablePasswordFormats
                .map((f) => SelectOption(
                      value: f,
                      label: f.displayName,
                      subtitle: f.description,
                    ))
                .toList(),
            onChanged: state.busy
                ? (_) {}
                : (f) => notifier.setImportFormat(f),
          ),
        ],
        if (isDecoded) ...[
          const SizedBox(height: 10),
          _buildDecodedItemsList(context, state, cs, textTheme, isCompact: widget.isLandscape),
        ],
      ],
    );

    final rightControls = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!isDecoded && state.importBytes != null) ...[
          if (state.importFormat.isEncrypted) ...[
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              enabled: !state.busy,
              decoration: InputDecoration(
                isDense: widget.isLandscape,
                labelText: l10n.passwordInterchangeMasterPassword,
                prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _obscure,
                  onToggle: () => setState(() => _obscure = !_obscure),
                ),
              ),
              onSubmitted: (_) => notifier.decodeImportFile(password: _passwordController.text),
            ),
            const SizedBox(height: 10),
          ],
          FilledButton.icon(
            icon: const Icon(Icons.search_rounded, size: 18),
            label: Text(
              l10n.passwordInterchangeReadFile,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            onPressed: state.busy
                ? null
                : () => notifier.decodeImportFile(
                      password: state.importFormat.isEncrypted ? _passwordController.text : null,
                    ),
          ),
        ],
        if (isDecoded) ...[
          _buildDestinationFolderCard(context, state, cs, textTheme, isCompact: widget.isLandscape),
          const SizedBox(height: 12),
          FilledButton.icon(
            icon: const Icon(Icons.download_rounded, size: 18),
            label: Text(
              l10n.passwordInterchangeRunImport(state.selectedCount),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: const StadiumBorder(),
            ),
            onPressed: state.busy || state.importContainer == null || state.selectedCount == 0
                ? null
                : notifier.runImport,
          ),
        ],
      ],
    );

    if (widget.isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: SingleChildScrollView(child: leftControls),
          ),
          const SizedBox(width: 16),
          const VerticalDivider(width: 1),
          const SizedBox(width: 16),
          Expanded(
            flex: 6,
            child: SingleChildScrollView(child: rightControls),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        leftControls,
        if (state.importBytes != null) ...[
          const SizedBox(height: AppSpacing.md),
          rightControls,
        ],
      ],
    );
  }
}

// ── IMPORT RESULT VIEW ──────────────────────────────────────────────────────

class _ImportResultCard extends StatelessWidget {
  final PasswordImportOutcome result;
  final VoidCallback onDone;

  const _ImportResultCard({
    required this.result,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                children: [
                  Icon(Icons.check_circle_rounded, color: cs.primary, size: 52),
                  const SizedBox(height: 12),
                  Text(
                    l10n.passwordInterchangeImportedCount(result.imported),
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  if (result.skipped > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      l10n.passwordInterchangeSkippedCount(result.skipped),
                      style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (result.errors.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 140),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Scrollbar(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: result.errors.length,
                            itemBuilder: (context, i) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Text(
                                '• ${result.errors[i]}',
                                style: textTheme.bodySmall?.copyWith(color: cs.error),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onDone,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              child: Text(
                l10n.close,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}