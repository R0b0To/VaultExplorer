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
    final state = ref.watch(compositeContainerProvider);
    final ctrl = ref.read(compositeContainerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Composite Container'),
      ),
      body: state.isOperating
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(state.statusMessage ?? 'Processing…'),
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
                SectionHeader('Carrier Files (${state.pickedCarriers.length})'),
                SectionCard(
                  children: [
                    ListTile(
                      leading: Icon(Icons.add_photo_alternate_rounded, color: cs.primary),
                      title: const Text('Add Carrier Files'),
                      subtitle: const Text('Pick images, videos, audio, or documents'),
                      trailing: ElevatedButton.icon(
                        onPressed: ctrl.pickCarriers,
                        icon: const Icon(Icons.folder_open),
                        label: const Text('Browse'),
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
                                ? '${budget.detectedFormat.toUpperCase()} • Allocatable: ${formatBytes(budget.allocatableBytes)}'
                                : 'Analyzing…',
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
                  const SectionHeader('Total Usable Capacity'),
                  SectionCard(
                    children: [
                      ListTile(
                        leading: Icon(Icons.storage_rounded, color: cs.secondary),
                        title: Text(
                          formatBytes(state.profile!.totalAllocatableBytes),
                          style: context.typography.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          'Distributed across ${state.profile!.carriers.length} files (aligned to 512B sectors)',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],

                // ── Password & Credentials ─────────────────────────────────
                SectionHeader(context.l10n.securityCredentialsSectionHeader),
                SectionCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: context.l10n.passwordFieldLabel,
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
                          labelText: context.l10n.confirmPasswordFieldLabelTitleCase,
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
                        decoration: const InputDecoration(
                          labelText: 'PIM (Personal Iteration Multiplier)',
                          helperText: 'Leave empty or 0 for standard default iterations',
                          prefixIcon: Icon(Icons.speed_rounded),
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
                      title: const Text('Remember this container'),
                      subtitle: const Text(
                        'Pin it on the dashboard so you don\'t have to re-pick these '
                        'files next time. Stores which files are linked together, '
                        'encrypted, on this device.',
                      ),
                      secondary: Icon(Icons.push_pin_outlined, color: cs.primary, size: 22),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Cryptographic Algorithms & Filesystem ─────────────────
                const SectionHeader('Encryption & Filesystem'),
                SectionCard(
                  children: [
                    ListTile(
                      title: const Text('Encryption Algorithm'),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: state.cipherId,
                          items: CipherAlgo.dropdownItems(includeAuto: false),
                          onChanged: (val) => val != null ? ctrl.setCipherId(val) : null,
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('Hash Algorithm (KDF)'),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: state.hashId,
                          items: HashAlgo.dropdownItems(includeAuto: false),
                          onChanged: (val) => val != null ? ctrl.setHashId(val) : null,
                        ),
                      ),
                    ),
                    ListTile(
                      title: const Text('Filesystem Type'),
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
                      title: const Text('Quick Format'),
                      subtitle: const Text('Skips zero-filling carrier allocated space'),
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
                              const SnackBar(
                                content: Text('Composite Container Created Successfully!'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                            Navigator.of(context).pop();
                          }
                        },
                  icon: const Icon(Icons.build_rounded),
                  label: const Text('Create Container'),
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
                              initialName: 'Composite Container (${carriers.length} files)',
                              onMounted: (container, {record}) {},
                            ),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.lock_open_rounded, size: 18),
                    label: const Text('Already have a composite container? Unlock & Mount'),
                  ),
                ),
              ],
            ),
    );
  }
}
