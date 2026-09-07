import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/features/dashboard/widgets/container_wizard_shared.dart';
import 'package:vaultexplorer/features/dashboard/widgets/quick_password_generator_sheet.dart';
import 'package:vaultexplorer/features/tools/widgets/composite_container_controller.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';

enum _CompositeWizStep { carriers, security, advanced, review }

/// Linear multi-step wizard for creating a new distributed composite VeraCrypt volume
/// across multiple carrier files.
class CompositeCreateSheet extends ConsumerStatefulWidget {
  const CompositeCreateSheet({super.key});

  @override
  ConsumerState<CompositeCreateSheet> createState() => _CompositeCreateSheetState();
}

class _CompositeCreateSheetState extends ConsumerState<CompositeCreateSheet> {
  int _currentStep = 0;

  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _pimController = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;

  static const _steps = [
    _CompositeWizStep.carriers,
    _CompositeWizStep.security,
    _CompositeWizStep.advanced,
    _CompositeWizStep.review,
  ];

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

  Future<void> _openPasswordGenerator() async {
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => const QuickPasswordGeneratorSheet(),
    );

    if (password != null && mounted) {
      setState(() {
        _passwordController.text = password;
        _confirmPasswordController.text = password;
        _obscurePassword = false;
        _obscureConfirmPassword = false;
      });
      await ref.read(sensitiveClipboardProvider).copy(password);
    }
  }

  bool _canProceedFor(_CompositeWizStep step, CompositeContainerState state) =>
      switch (step) {
        _CompositeWizStep.carriers => state.pickedCarriers.isNotEmpty,
        _CompositeWizStep.security =>
          (_passwordController.text.isNotEmpty || state.keyfiles.isNotEmpty) &&
              (_passwordController.text.isEmpty ||
                  _passwordController.text == _confirmPasswordController.text),
        _CompositeWizStep.advanced => true,
        _CompositeWizStep.review => true,
      };

  String _stepTitle(_CompositeWizStep step, CompositeContainerState state) =>
      switch (step) {
        _CompositeWizStep.carriers => state.pickedCarriers.isEmpty
            ? context.l10n.compositeAddCarrierFilesTitle
            : context.l10n.compositeCarrierFilesCountHeader(state.pickedCarriers.length),
        _CompositeWizStep.security => context.l10n.securityCredentialsSectionHeader,
        _CompositeWizStep.advanced => context.l10n.compositeEncryptionAndFilesystemHeader,
        _CompositeWizStep.review => context.l10n.wizardStepReviewTitle,
      };

  void _goNext(CompositeContainerState state) {
    if (_currentStep == _steps.length - 1) {
      _create();
    } else {
      setState(() => _currentStep++);
    }
  }

  void _goBackOrExit() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _create() async {
    final ctrl = ref.read(compositeContainerProvider.notifier);
    final ok = await ctrl.createContainer(
      password: _passwordController.text,
      confirmPassword: _confirmPasswordController.text,
    );
    if (ok && mounted) {
      Navigator.of(context).pop();
      showAppSnackBar(
        context,
        message: context.l10n.compositeCreateSuccessMessage,
        tone: AppBannerTone.success,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(compositeContainerProvider);
    final cs = context.colors;
    final textTheme = context.typography;
    final l10n = context.l10n;
    final isShortScreen = MediaQuery.sizeOf(context).height < 520;

    final safeStep = _currentStep.clamp(0, _steps.length - 1);
    final currentKind = _steps[safeStep];
    final isLastStep = safeStep == _steps.length - 1;

    final inputDecorationTheme = InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      contentPadding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: isShortScreen ? 11 : 16,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );

    return Theme(
      data: Theme.of(context).copyWith(inputDecorationTheme: inputDecorationTheme),
      child: WizardScaffold(
        appBarTitle: l10n.compositeCreateScreenTitle,
        currentStep: safeStep,
        totalSteps: _steps.length,
        stepTitle: _stepTitle(currentKind, state),
        stepContent: _stepContent(currentKind, state, cs, textTheme, isShortScreen),
        busy: state.isOperating,
        busyMessage: state.statusMessage ?? l10n.compositeProcessingStatus,
        canProceed: _canProceedFor(currentKind, state),
        isLastStep: isLastStep,
        nextLabel: isLastStep
            ? l10n.compositeCreateContainerButton
            : l10n.wizardNextButton,
        onNext: () => _goNext(state),
        onBackOrExit: _goBackOrExit,
        errorMessage: state.error,
      ),
    );
  }

  Widget _stepContent(
    _CompositeWizStep kind,
    CompositeContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isShortScreen,
  ) =>
      switch (kind) {
        _CompositeWizStep.carriers => _buildCarriersStep(state, cs, textTheme),
        _CompositeWizStep.security =>
          _buildSecurityStep(state, cs, textTheme, isShortScreen),
        _CompositeWizStep.advanced => _buildAdvancedStep(state, cs, textTheme),
        _CompositeWizStep.review => _buildReviewStep(state, cs, textTheme),
      };

// ── Step 1: Carriers & Usable Capacity ────────────────────────────────────
  Widget _buildCarriersStep(
    CompositeContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;
    final ctrl = ref.read(compositeContainerProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InlineBanner(
          l10n.compositeAddCarrierFilesSubtitle,
          tone: AppBannerTone.info,
          icon: Icons.info_outline_rounded,
        ),
        const SizedBox(height: 14),
        SectionHeader(l10n.compositeCarrierFilesCountHeader(state.pickedCarriers.length)),
        SectionCard(
          children: [
            InkWell(
              onTap: state.isOperating ? null : ctrl.pickCarriers,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Icon(Icons.add_photo_alternate_rounded, color: cs.primary, size: 24),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            l10n.compositeAddCarrierFilesTitle,
                            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.compositeAddCarrierFilesSubtitle,
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.tonalIcon(
                      onPressed: state.isOperating ? null : ctrl.pickCarriers,
                      style: FilledButton.styleFrom(
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                      ),
                      icon: const Icon(Icons.folder_open_rounded, size: 18),
                      label: Text(l10n.compositeBrowseButtonLabel),
                    ),
                  ],
                ),
              ),
            ),
            if (state.pickedCarriers.isNotEmpty) ...[
              const Divider(height: 1),
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
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: state.isOperating ? null : () => ctrl.removeCarrier(index),
                  ),
                );
              }),
            ],
          ],
        ),
        if (state.profile != null) ...[
          const SizedBox(height: 16),
          SectionHeader(l10n.compositeTotalUsableCapacityHeader),
          SectionCard(
            children: [
              ListTile(
                leading: Icon(Icons.storage_rounded, color: cs.secondary),
                title: Text(
                  formatBytes(state.profile!.totalAllocatableBytes),
                  style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  l10n.compositeCapacityDistributedSubtitle(state.profile!.carriers.length),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: state.isOperating
                ? null
                : () async {
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
    );
  }
  // ── Step 2: Security & Credentials ─────────────────────────────────────────
  Widget _buildSecurityStep(
    CompositeContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
    bool isShortScreen,
  ) {
    final l10n = context.l10n;
    final ctrl = ref.read(compositeContainerProvider.notifier);
    final vPad = isShortScreen ? 4.0 : 8.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.securityCredentialsSectionHeader),
        SectionCard(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16, isShortScreen ? 10 : 16, 16, vPad),
              child: TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.passwordFieldLabel,
                  prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
                        tooltip: l10n.generateStrongPasswordTooltip,
                        onPressed: _openPasswordGenerator,
                      ),
                      PasswordVisibilityToggle(
                        obscured: _obscurePassword,
                        onToggle: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, vPad, 16, isShortScreen ? 8 : 12),
              child: TextField(
                controller: _confirmPasswordController,
                obscureText: _obscureConfirmPassword,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: l10n.confirmPasswordFieldLabelTitleCase,
                  prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _obscureConfirmPassword,
                    onToggle: () => setState(
                      () => _obscureConfirmPassword = !_obscureConfirmPassword,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _pimController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.compositePimFieldLabel,
                  prefixIcon: const Icon(Icons.speed_rounded, size: 20),
                ),
                onChanged: (val) {
                  final parsed = int.tryParse(val.trim()) ?? 0;
                  ctrl.setPim(parsed);
                  setState(() {});
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
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: state.remember,
              onChanged: state.isOperating ? null : ctrl.setRemember,
              title: Text(l10n.compositeRememberContainerTitle),
              subtitle: Text(
                l10n.compositeRememberContainerSubtitle,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              secondary: Icon(Icons.push_pin_outlined, color: cs.primary, size: 22),
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 3: Encryption & Filesystem ───────────────────────────────────────
  Widget _buildAdvancedStep(
    CompositeContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;
    final ctrl = ref.read(compositeContainerProvider.notifier);
    final cipherChoices = cipherChoicesForFormat(CreateFormat.veracrypt);
    final hashChoices = hashChoicesForFormat(CreateFormat.veracrypt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.compositeEncryptionAndFilesystemHeader),
        SectionCard(
          children: [
            OptionPickerTile<int>(
              label: l10n.compositeEncryptionAlgorithmLabel,
              value: state.cipherId,
              prefixIcon: Icons.security_rounded,
              options: cipherChoices
                  .map((c) => SelectOption(value: c.id, label: c.label))
                  .toList(),
              onChanged: (val) => ctrl.setCipherId(val),
            ),
            OptionPickerTile<int>(
              label: l10n.compositeHashAlgorithmLabel,
              value: state.hashId,
              prefixIcon: Icons.tag_rounded,
              options: hashChoices
                  .map((h) => SelectOption(value: h.id, label: h.label))
                  .toList(),
              onChanged: (val) => ctrl.setHashId(val),
            ),
            OptionPickerTile<String>(
              label: l10n.compositeFilesystemTypeLabel,
              value: state.fileSystem,
              prefixIcon: Icons.dns_rounded,
              options: const [
                SelectOption(value: 'FAT', label: 'FAT32 / exFAT'),
                SelectOption(value: 'ext4', label: 'ext4'),
                SelectOption(value: 'NTFS', label: 'NTFS'),
              ],
              onChanged: (val) => ctrl.setFileSystem(val),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                l10n.compositeQuickFormatTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                l10n.compositeQuickFormatSubtitle,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: state.quickFormat,
              onChanged: state.isOperating ? null : ctrl.setQuickFormat,
            ),
          ],
        ),
      ],
    );
  }

  // ── Step 4: Review Summary ────────────────────────────────────────────────
  Widget _buildReviewStep(
    CompositeContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;
    final rows = <Widget>[
      WizardSummaryRow(
        icon: Icons.category_rounded,
        label: l10n.metaLabelType,
        value: 'VeraCrypt Composite',
      ),
      WizardSummaryRow(
        icon: Icons.folder_shared_rounded,
        label: l10n.compositeCarrierFilesCountHeader(state.pickedCarriers.length),
        value: '${state.pickedCarriers.length}',
      ),
    ];

    if (state.profile != null) {
      rows.add(
        WizardSummaryRow(
          icon: Icons.storage_rounded,
          label: l10n.compositeTotalUsableCapacityHeader,
          value: formatBytes(state.profile!.totalAllocatableBytes),
        ),
      );
    }

    rows.addAll([
      WizardSummaryRow(
        icon: Icons.security_rounded,
        label: l10n.compositeEncryptionAlgorithmLabel,
        value: CipherAlgo.nameFor(state.cipherId),
      ),
      WizardSummaryRow(
        icon: Icons.tag_rounded,
        label: l10n.compositeHashAlgorithmLabel,
        value: HashAlgo.nameFor(state.hashId),
      ),
      WizardSummaryRow(
        icon: Icons.dns_rounded,
        label: l10n.compositeFilesystemTypeLabel,
        value: state.fileSystem,
      ),
      WizardSummaryRow(
        icon: Icons.speed_rounded,
        label: l10n.wizardSummaryPimLabel,
        value: _pimController.text.trim().isEmpty
            ? l10n.wizardSummaryPimDefaultValue
            : _pimController.text.trim(),
      ),
      WizardSummaryRow(
        icon: Icons.bolt_rounded,
        label: l10n.compositeQuickFormatTitle,
        value: state.quickFormat ? l10n.vaultInfoYesValue : l10n.vaultInfoNoValue,
      ),
      WizardSummaryRow(
        icon: Icons.key_rounded,
        label: l10n.wizardSummaryPasswordLabel,
        value: _passwordController.text.isNotEmpty
            ? l10n.wizardPasswordSetValue
            : l10n.wizardPasswordNotSetValue,
      ),
      WizardSummaryRow(
        icon: Icons.insert_drive_file_outlined,
        label: l10n.wizardSummaryKeyfilesLabel,
        value: state.keyfiles.isEmpty
            ? l10n.noKeyfilesAttached
            : '${state.keyfiles.length}',
      ),
      WizardSummaryRow(
        icon: Icons.push_pin_outlined,
        label: l10n.compositeRememberContainerTitle,
        value: state.remember ? l10n.vaultInfoYesValue : l10n.vaultInfoNoValue,
      ),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.wizardSummaryTitle),
        SectionCard(children: rows),
      ],
    );
  }
}