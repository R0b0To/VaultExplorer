import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/widgets/layout/section_card.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'composite_container_controller.dart';

class CompositeContainerSheet extends ConsumerStatefulWidget {
  const CompositeContainerSheet({super.key});

  @override
  ConsumerState<CompositeContainerSheet> createState() => _CompositeContainerSheetState();
}

class _CompositeContainerSheetState extends ConsumerState<CompositeContainerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pimController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      ref.read(compositeContainerProvider.notifier).setMode(_tabController.index == 0);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
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
    final isCreating = _tabController.index == 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Composite Container (Experimental)'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Create New'),
            Tab(text: 'Unlock & Mount'),
          ],
        ),
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

                // ── 1. Carrier File Selection ────────────────────────────────
                SectionHeader('1. Carrier Files (${state.pickedCarriers.length})'),
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

                // ── 2. Capacity Summary ──────────────────────────────────────
                if (state.profile != null) ...[
                  SectionHeader('2. Total Usable Capacity'),
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

                // ── 3. Password & Credentials ─────────────────────────────────
                SectionHeader('3. Credentials & Keys'),
                SectionCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Container Password',
                          prefixIcon: const Icon(Icons.lock_rounded),
                          suffixIcon: IconButton(
                            icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                      ),
                    ),
                    if (isCreating) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: TextField(
                          controller: _confirmPasswordController,
                          obscureText: _obscurePassword,
                          decoration: const InputDecoration(
                            labelText: 'Confirm Password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                        ),
                      ),
                    ],
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
                    ListTile(
                      leading: Icon(Icons.key_rounded, color: cs.primary),
                      title: Text('Keyfiles (${state.keyfiles.length})'),
                      subtitle: const Text('Add optional keyfiles for two-factor encryption'),
                      trailing: TextButton.icon(
                        onPressed: ctrl.pickKeyfiles,
                        icon: const Icon(Icons.add),
                        label: const Text('Add Keyfile'),
                      ),
                    ),
                    if (state.keyfiles.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: state.keyfiles.map((k) {
                            return Chip(
                              label: Text(k.displayName),
                              onDeleted: () => ctrl.removeKeyfile(k),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── 4. Cryptographic Algorithms & Filesystem ─────────────────
                SectionHeader(isCreating ? '4. Encryption & Filesystem' : '4. Cryptography Options'),
                SectionCard(
                  children: [
                    // Cipher selection
                    ListTile(
                      title: const Text('Encryption Algorithm'),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: state.cipherId,
                          items: CipherAlgo.dropdownItems(includeAuto: !isCreating),
                          onChanged: (val) => val != null ? ctrl.setCipherId(val) : null,
                        ),
                      ),
                    ),
                    // Hash selection
                    ListTile(
                      title: const Text('Hash Algorithm (KDF)'),
                      trailing: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: state.hashId,
                          items: HashAlgo.dropdownItems(includeAuto: !isCreating),
                          onChanged: (val) => val != null ? ctrl.setHashId(val) : null,
                        ),
                      ),
                    ),
                    if (isCreating) ...[
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
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),

                // ── 5. Action Button ─────────────────────────────────────────
                FilledButton.icon(
                  onPressed: state.pickedCarriers.isEmpty
                      ? null
                      : () async {
                          if (isCreating) {
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
                          } else {
                            final ok = await ctrl.unlockContainer(
                              password: _passwordController.text,
                            );
                            if (ok && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Composite Container Mounted!'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              Navigator.of(context).pop();
                            }
                          }
                        },
                  icon: Icon(isCreating ? Icons.build_rounded : Icons.lock_open_rounded),
                  label: Text(isCreating ? 'Create Container' : 'Unlock & Mount'),
                ),
              ],
            ),
    );
  }
}