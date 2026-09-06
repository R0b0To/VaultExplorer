import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/features/tools/widgets/composite_container_controller.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';

/// Standalone screen for creating a new distributed composite VeraCrypt volume
/// across multiple carrier files.
class CompositeCreateSheet extends ConsumerStatefulWidget {
  const CompositeCreateSheet({super.key});

  @override
  ConsumerState<CompositeCreateSheet> createState() => _CompositeCreateSheetState();
}

class _CompositeCreateSheetState extends ConsumerState<CompositeCreateSheet> {
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pimController = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        ref.read(compositeContainerProvider.notifier).setMode(true);
      }
    });
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _pimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final l10n = context.l10n;
    final state = ref.watch(compositeContainerProvider);
    final ctrl = ref.read(compositeContainerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.compositeCreateScreenTitle),
      ),
      body: state.isOperating
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(state.statusMessage ?? l10n.compositeProcessingStatus),
                ],
              ),
            )
          : ListView(
              padding: AppSpacing.pagePadding,
              children: [
                if (state.error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cs.errorContainer,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Text(state.error!, style: TextStyle(color: cs.onErrorContainer)),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                // ── Carrier File Selection ────────────────────────────────
                SectionHeader(l10n.compositeCarrierFilesCountHeader(state.pickedCarriers.length)),
                SectionCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.add_photo_alternate_rounded, color: cs.primary),
                      title: Text(l10n.compositeAddCarrierFilesTitle),
                      subtitle: Text(l10n.compositeAddCarrierFilesSubtitle),
                      trailing: ElevatedButton.icon(
                        onPressed: ctrl.pickCarriers,
                        icon: const Icon(Icons.folder_open),
                        label: Text(l10n.compositeBrowseButtonLabel),
                      ),
                    ),
                    if (state.pickedCarriers.isNotEmpty) ...[
                      const Divider(),
                      ...List.generate(state.pickedCarriers.length, (index) {
                        final carrier = state.pickedCarriers[index];
                        final budget = state.profile != null &&
                                state.profile!.carriers.length == state.pickedCarriers.length
                            ? state.profile!.carriers[index]
                            : null;

                        return ListTile(
                          dense: true,
                          leading: Icon(
                            budget?.tier.id == 0
                                ? Icons.verified_user_rounded
                                : Icons.insert_drive_file_rounded,
                            size: 20,
                            color: budget?.tier.id == 0 ? cs.primary : cs.outline,
                          ),
                          title: Text(
                            carrier.displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            budget != null
                                ? l10n.compositeCarrierAllocatableSubtitle(
                                    budget.detectedFormat.toUpperCase(),
                                    formatBytes(budget.allocatableBytes),
                                  )
                                : l10n.compositeCarrierAnalyzingStatus,
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () => ctrl.removeCarrier(index),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Capacity Summary ──────────────────────────────────────
                if (state.profile != null) ...[
                  SectionHeader(l10n.compositeTotalUsableCapacityHeader),
                  SectionCard(
                    children: [
                      ListTile(
                        leading: Icon(Icons.storage_rounded, color: cs.secondary),
                        title: Text(
                          formatBytes(state.profile!.totalAllocatableBytes),
                          style: context.typography.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          l10n.compositeCapacityDistributedSubtitle(state.profile!.carriers.length),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // ── Password & Credentials ─────────────────────────────────
                SectionHeader(l10n.securityCredentialsSectionHeader),
                SectionCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: l10n.passwordFieldLabel,
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: PasswordVisibilityToggle(
                            obscured: _obscurePassword,
                            onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirmPassword,
                        decoration: InputDecoration(
                          labelText: l10n.confirmPasswordFieldLabelTitleCase,
                          prefixIcon: const Icon(Icons.lock_outline_rounded),
                          suffixIcon: PasswordVisibilityToggle(
                            obscured: _obscureConfirmPassword,
                            onToggle: () =>
                                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        controller: _pimController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: l10n.compositePimFieldLabel,
                          helperText: l10n.compositePimFieldHelper,
                          prefixIcon: const Icon(Icons.speed_rounded),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val.trim()) ?? 0;
                          ctrl.setPim(parsed);
                        },
                      ),
                    ),
                    KeyfilesPicker(
                      keyfiles: state.keyfiles,
                      picking: state.pickingKeyfiles,
                      onPick: ctrl.pickKeyfiles,
                      onRemove: ctrl.removeKeyfile,
                      enabled: !state.isOperating,
                    ),
                    SwitchListTile(
                      value: state.remember,
                      onChanged: ctrl.setRemember,
                      title: Text(l10n.compositeRememberContainerTitle),
                      subtitle: Text(l10n.compositeRememberContainerSubtitle),
                      secondary: Icon(Icons.push_pin_outlined, color: cs.primary, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Cryptographic Algorithms & Filesystem ─────────────────
                SectionHeader(l10n.compositeEncryptionAndFilesystemHeader),
                SectionCard(
                  children: [
                    ListTile(
                      title: Text(l10n.compositeEncryptionAlgorithmLabel),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: state.cipherId,
                          items: CipherAlgo.dropdownItems(includeAuto: false),
                          onChanged: (val) => val != null ? ctrl.setCipherId(val) : null,
                        ),
                      ),
                    ),
                    ListTile(
                      title: Text(l10n.compositeHashAlgorithmLabel),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: state.hashId,
                          items: HashAlgo.dropdownItems(includeAuto: false),
                          onChanged: (val) => val != null ? ctrl.setHashId(val) : null,
                        ),
                      ),
                    ),
                    ListTile(
                      title: Text(l10n.compositeFilesystemTypeLabel),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: state.fileSystem,
                          items: const [
                            DropdownMenuItem(value: 'FAT', child: Text('FAT32 / exFAT')),
                            DropdownMenuItem(value: 'ext4', child: Text('ext4')),
                            DropdownMenuItem(value: 'NTFS', child: Text('NTFS')),
                          ],
                          onChanged: (val) => val != null ? ctrl.setFileSystem(val) : null,
                        ),
                      ),
                    ),
                    SwitchListTile(
                      title: Text(l10n.compositeQuickFormatTitle),
                      subtitle: Text(l10n.compositeQuickFormatSubtitle),
                      value: state.quickFormat,
                      onChanged: ctrl.setQuickFormat,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── Action Button ─────────────────────────────────────────
                FilledButton.icon(
                  onPressed: state.pickedCarriers.isEmpty
                      ? null
                      : () async {
                          final ok = await ctrl.createContainer(
                            password: _passwordController.text,
                            confirmPassword: _confirmPasswordController.text,
                          );
                          if (ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.l10n.compositeCreateSuccessMessage),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            Navigator.of(context).pop();
                          }
                        },
                  icon: const Icon(Icons.build_rounded),
                  label: Text(l10n.compositeCreateContainerButton),
                ),
                const SizedBox(height: AppSpacing.md),
                Center(
                  child: TextButton.icon(
                    onPressed: () async {
                      await ctrl.pickCarriers();
                      if (!context.mounted) return;
                      final carriers = ref.read(compositeContainerProvider).pickedCarriers;
                      if (carriers.isNotEmpty && context.mounted) {
                        Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) => UnlockSheet(
                              initialCompositeCarriers: carriers.map((c) => c.uri).toList(),
                              initialName: context.l10n.compositeDefaultContainerName(carriers.length),
                              onMounted: (container, {record}) {},
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.lock_open_rounded, size: 18),
                    label: Text(l10n.compositeAlreadyHaveUnlockPrompt),
                  ),
                ),
              ],
            ),
    );
  }
}