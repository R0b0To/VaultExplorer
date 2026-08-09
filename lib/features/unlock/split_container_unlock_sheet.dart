import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/advanced_params_panel.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

import '../../core/utils/validation_utils.dart';

/// Mounts a Container Splitter/Joiner (Tools tab) part sequence directly,
/// without ever running [ContainerToolService.joinContainer] first --
/// picks the `.001`/`.part1` first part exactly like the Join flow does
/// (`SplitPartResolver` locates the rest by naming convention, natively),
/// then unlocks straight from that.
///
/// Deliberately mirrors [CloudUnlockSheet]'s reduced credential surface
/// (password/PIM/cipher/hash + a read-only toggle, no hidden-volume or
/// keyfile UI, no remembered password) rather than [UnlockSheet]'s full
/// surface -- this is a less-common entry point for an already-advanced
/// workflow (splitting a container in the first place), so it isn't worth
/// duplicating that whole surface here. [VaultExplorerApi.unlockSplitContainer]
/// itself supports keyfiles/hidden-volume args already, so extending this
/// sheet later is just wiring, not a new native capability.
class SplitContainerUnlockSheet extends StatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record})
  onMounted;
  final bool documentProvider;
  final List<String> autoMountFolders;
  final List<String> mountedUris;

  const SplitContainerUnlockSheet({
    super.key,
    required this.onMounted,
    this.documentProvider = false,
    this.autoMountFolders = const [],
    this.mountedUris = const [],
  });

  @override
  State<SplitContainerUnlockSheet> createState() =>
      _SplitContainerUnlockSheetState();
}

class _SplitContainerUnlockSheetState
    extends State<SplitContainerUnlockSheet> {
  final _passwordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();

  String? _firstPartUri;
  String? _firstPartName;
  bool _obscure = true;
  bool _readOnly = false;
  bool _rememberVault = false;
  bool _unlocking = false;
  String? _error;
  int _cipherId = 255;
  int _hashId = 255;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFirstPart() async {
    final picked = await vaultExplorerApi.pickContainer();
    if (picked == null || !mounted) return;
    setState(() {
      _firstPartUri = picked.uri;
      _firstPartName = picked.displayName;
      _error = null;
    });
  }

  bool get _isAlreadyMounted =>
      _firstPartUri != null && widget.mountedUris.contains(_firstPartUri);

  Future<void> _unlock() async {
    final firstPartUri = _firstPartUri;
    if (firstPartUri == null) {
      setState(() => _error = context.l10n.noFileSelectedLabel);
      return;
    }
    if (_isAlreadyMounted) {
      setState(() => _error = context.l10n.containerAlreadyMounted);
      return;
    }
    final password = _passwordCtrl.text;
    if (password.isEmpty) {
      setState(() => _error = context.l10n.passwordFieldLabel);
      return;
    }

    setState(() {
      _unlocking = true;
      _error = null;
    });
    try {
      final result = await vaultExplorerApi.unlockSplitContainer(
        firstPartUri,
        password,
        clampPim(int.tryParse(_pimCtrl.text) ?? 0),
        displayName: _firstPartName,
        documentProvider: widget.documentProvider,
        autoMountFolders: widget.autoMountFolders,
        cipherId: _cipherId,
        hashId: _hashId,
        readOnly: _readOnly,
      );
      if (result == null) {
        if (mounted) {
          setState(() => _error = context.l10n.incorrectPasswordOrInvalidContainer);
        }
        return;
      }

      final temporaryContainer = MountedContainer(
        uri: firstPartUri,
        displayName: _firstPartName ?? firstPartUri,
        volId: result.volId,
        rootFiles: result.files,
        mountedAt: DateTime.now(),
        totalSpace: 0,
        freeSpace: 0,
        containerFormat: result.containerFormat,
        readOnly: _readOnly,
      );
      final space = await vaultExplorerApi.getSpaceInfo(temporaryContainer);
      final mountedContainer = temporaryContainer.copyWith(
        totalSpace: space != null && space.isNotEmpty ? space[0] : 0,
        freeSpace: space != null && space.length > 1 ? space[1] : 0,
      );

      ContainerRecord? record;
      if (_rememberVault) {
        record = ContainerRecord(
          uri: firstPartUri,
          label: _firstPartName ?? firstPartUri,
          documentProvider: widget.documentProvider,
          readOnly: _readOnly,
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
          containerFormat: result.containerFormat,
        );
        await ContainerRepository.instance.save(record);
      }

      widget.onMounted(mountedContainer, record: record);
      await HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? context.l10n.incorrectPasswordOrInvalidContainer);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.mountSplitContainerTitle)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.l10n.mountSplitContainerSubtitle,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              _PickerRow(
                icon: Icons.description_outlined,
                label: context.l10n.joinFirstPartLabel,
                valueLabel: _firstPartName ?? context.l10n.noFileSelectedLabel,
                buttonLabel: context.l10n.chooseFileButton,
                onTap: _unlocking ? null : _pickFirstPart,
              ),
              const SizedBox(height: AppSpacing.lg),
              SectionCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      controller: _passwordCtrl,
                      enabled: !_unlocking,
                      obscureText: _obscure,
                      keyboardType: TextInputType.visiblePassword,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) {
                        if (!_unlocking) _unlock();
                      },
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: cs.surfaceContainerHighest,
                        labelText: context.l10n.passwordFieldLabel,
                        prefixIcon: Icon(
                          Icons.lock_outline_rounded,
                          color: cs.primary,
                        ),
                        suffixIcon: IconButton(
                          onPressed: () => setState(() => _obscure = !_obscure),
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                    ),
                  ),
                  AdvancedParamsPanel(
                    pimController: _pimCtrl,
                    cipherId: _cipherId,
                    hashId: _hashId,
                    enabled: !_unlocking,
                    includeAuto: true,
                    onCipherChanged: (value) => setState(() => _cipherId = value),
                    onHashChanged: (value) => setState(() => _hashId = value),
                    onExpansionChanged: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    value: _readOnly,
                    onChanged: _unlocking
                        ? null
                        : (value) => setState(() => _readOnly = value),
                    secondary: Icon(
                      Icons.visibility_outlined,
                      color: cs.primary,
                    ),
                    title: Text(
                      context.l10n.readOnlyModeLabel,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.readOnlyModeContainerSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    value: _rememberVault,
                    onChanged: _unlocking
                        ? null
                        : (value) => setState(() => _rememberVault = value),
                    secondary: Icon(
                      Icons.bookmark_add_outlined,
                      color: cs.primary,
                    ),
                    title: Text(
                      context.l10n.rememberContainerLabel,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      context.l10n.rememberContainerSubtitle,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                InlineErrorBanner(_error!),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _unlocking ? null : _unlock,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                  shape: const StadiumBorder(),
                ),
                icon: _unlocking
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: cs.onPrimary,
                        ),
                      )
                    : const Icon(Icons.lock_open_rounded),
                label: Text(context.l10n.unlockAndMountButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Matches [ContainerSplitterSheet]'s own `_PickerRow` shape (label,
/// value readout, trailing picker button) -- duplicated locally rather
/// than shared since that one is private to its own file.
class _PickerRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String valueLabel;
  final String buttonLabel;
  final VoidCallback? onTap;

  const _PickerRow({
    required this.icon,
    required this.label,
    required this.valueLabel,
    required this.buttonLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: AppIconSize.small, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(
                  valueLabel,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onTap,
            child: Text(buttonLabel),
          ),
        ],
      ),
    );
  }
}
