import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_scaffold.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_selection_card.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_summary_row.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/features/dashboard/widgets/quick_password_generator_sheet.dart';
import 'package:vaultexplorer/features/dashboard/widgets/usb_create_container_controller.dart';

enum _WizStep { type, basicInfo, security, advanced, review }

class UsbCreateContainerSheet extends ConsumerStatefulWidget {
  const UsbCreateContainerSheet({super.key});

  @override
  ConsumerState<UsbCreateContainerSheet> createState() =>
      _UsbCreateContainerSheetState();
}

class _UsbCreateContainerSheetState extends ConsumerState<UsbCreateContainerSheet> {
  final _sizeCtrl = TextEditingController(text: '1024');
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();

  final _hiddenPasswordCtrl = TextEditingController();
  final _hiddenConfirmPasswordCtrl = TextEditingController();
  final _hiddenPimCtrl = TextEditingController();
  final _hiddenSizeCtrl = TextEditingController(text: '10');

  bool _obscure = true;
  bool _confirmObscure = true;
  bool _hiddenObscure = true;
  bool _hiddenConfirmObscure = true;

  static const _veraCryptFileSystems = [
    'FAT',
    'exFAT',
    'NTFS',
    'ext2',
    'ext3',
    'ext4'
  ];
  static const _luksFileSystems = [
    'FAT',
    'exFAT',
    'NTFS',
    'ext2',
    'ext3',
    'ext4'
  ];

  @override
  void dispose() {
    _sizeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _pimCtrl.dispose();
    _hiddenPasswordCtrl.dispose();
    _hiddenConfirmPasswordCtrl.dispose();
    _hiddenPimCtrl.dispose();
    _hiddenSizeCtrl.dispose();
    super.dispose();
  }

  List<String> _availableFileSystems(CreateFormat format) =>
      format == CreateFormat.veracrypt ? _veraCryptFileSystems : _luksFileSystems;

  List<CipherAlgo> _cipherChoices(CreateFormat format) => switch (format) {
        CreateFormat.veracrypt => CipherAlgo.concrete,
        CreateFormat.luks1 => CipherAlgo.luks1Choices,
        CreateFormat.luks2 => CipherAlgo.luks2Choices,
      };

  List<HashAlgo> _hashChoices(CreateFormat format) => switch (format) {
        CreateFormat.veracrypt => HashAlgo.concrete,
        CreateFormat.luks1 => HashAlgo.luks1Choices,
        CreateFormat.luks2 => HashAlgo.luks2Choices,
      };

  Future<void> _create(UsbCreateContainerState state) async {
    final device = state.selected;
    if (device == null) return;

    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.eraseDeviceTitle(device.productName),
      message: context.l10n.eraseDeviceMessage,
      confirmLabel: context.l10n.eraseAndCreateButton,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;

    final ok = await ref.read(usbCreateContainerProvider.notifier).createUsbContainer(
          sizeText: _sizeCtrl.text,
          passwordText: _passwordCtrl.text,
          confirmPasswordText: _confirmPasswordCtrl.text,
          pimText: _pimCtrl.text,
          hiddenPasswordText: _hiddenPasswordCtrl.text,
          hiddenConfirmPasswordText: _hiddenConfirmPasswordCtrl.text,
          hiddenPimText: _hiddenPimCtrl.text,
          hiddenSizeText: _hiddenSizeCtrl.text,
          l10n: context.l10n,
        );

    if (ok && mounted) {
      Navigator.pop(context);
      showAppSnackBar(
        context,
        message: context.l10n.usbContainerCreatedSnack,
        tone: AppBannerTone.success,
      );
    }
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
        _passwordCtrl.text = password;
        _confirmPasswordCtrl.text = password;
        _obscure = false;
        _confirmObscure = false;
      });
      await ref.read(sensitiveClipboardProvider).copy(password);
    }
  }

  List<_WizStep> get _stepKinds => const [
        _WizStep.type,
        _WizStep.basicInfo,
        _WizStep.security,
        _WizStep.advanced,
        _WizStep.review,
      ];

  bool _canProceedBasicInfo(UsbCreateContainerState state) =>
      state.selected != null && (double.tryParse(_sizeCtrl.text) ?? 0) > 0;

  bool _canProceedSecurity(UsbCreateContainerState state) =>
      (_passwordCtrl.text.isNotEmpty || state.outerKeyfiles.isNotEmpty) &&
      (_passwordCtrl.text.isEmpty ||
          _passwordCtrl.text == _confirmPasswordCtrl.text);

  HiddenVolumeValidation? _hiddenVolumeValidationResult(UsbCreateContainerState state) {
    if (!state.enableHiddenVolume || state.format != CreateFormat.veracrypt) return null;
    final sizeVal = double.tryParse(_sizeCtrl.text);
    if (sizeVal == null || sizeVal <= 0) return null;
    final multiplier = state.sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
    final outerSizeBytes = (sizeVal * multiplier).round();
    final outerPim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
    final hiddenPim =
        clampPim(_hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0);

    return validateHiddenVolume(
      hiddenSizeText: _hiddenSizeCtrl.text,
      hiddenSizeUnit: state.hiddenSizeUnit,
      outerSizeBytes: outerSizeBytes,
      outerPimClamped: outerPim,
      hiddenPimClamped: hiddenPim,
      outerPassword: _passwordCtrl.text,
      hiddenPassword: _hiddenPasswordCtrl.text,
      hasHiddenKeyfiles: state.hiddenKeyfiles.isNotEmpty,
      outerKeyfileUris: state.outerKeyfiles.map((k) => k.uri).toSet(),
      hiddenKeyfileUris: state.hiddenKeyfiles.map((k) => k.uri).toSet(),
      l10n: context.l10n,
    );
  }

  bool _canProceedAdvanced(UsbCreateContainerState state) {
    if (!state.enableHiddenVolume || state.format != CreateFormat.veracrypt) return true;
    final validation = _hiddenVolumeValidationResult(state);
    return validation == null || validation.isValid;
  }

  bool _canProceedFor(_WizStep kind, UsbCreateContainerState state) => switch (kind) {
        _WizStep.type => true,
        _WizStep.basicInfo => _canProceedBasicInfo(state),
        _WizStep.security => _canProceedSecurity(state),
        _WizStep.advanced => _canProceedAdvanced(state),
        _WizStep.review => true,
      };

  String _stepTitle(_WizStep kind) => switch (kind) {
        _WizStep.type => context.l10n.wizardStepTypeTitle,
        _WizStep.basicInfo => context.l10n.wizardStepBasicInfoTitle,
        _WizStep.security => context.l10n.securityCredentialsSectionHeader,
        _WizStep.advanced => context.l10n.wizardStepAdvancedTitle,
        _WizStep.review => context.l10n.wizardStepReviewTitle,
      };

  void _goNext(UsbCreateContainerState state) {
    final kinds = _stepKinds;
    final safe = state.currentStep.clamp(0, kinds.length - 1);
    if (safe == kinds.length - 1) {
      _create(state);
    } else {
      ref.read(usbCreateContainerProvider.notifier).setCurrentStep(safe + 1);
    }
  }

  void _goBackOrExit(UsbCreateContainerState state) {
    if (state.currentStep > 0) {
      ref.read(usbCreateContainerProvider.notifier).setCurrentStep(state.currentStep - 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(usbCreateContainerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    if (state.suggestedSizeText != null && _sizeCtrl.text != state.suggestedSizeText) {
      _sizeCtrl.text = state.suggestedSizeText!;
    }

    final kinds = _stepKinds;
    final safeStep = state.currentStep.clamp(0, kinds.length - 1);
    final currentKind = kinds[safeStep];
    final isLastStep = safeStep == kinds.length - 1;

    final inputDecorationTheme = InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHighest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );

    return Theme(
      data: Theme.of(context).copyWith(inputDecorationTheme: inputDecorationTheme),
      child: WizardScaffold(
        appBarTitle: l10n.formatUsbDriveScreenTitle,
        currentStep: safeStep,
        totalSteps: kinds.length,
        stepTitle: _stepTitle(currentKind),
        stepContent: _stepContent(currentKind, state, cs, textTheme),
        busy: state.busy,
        busyMessage: l10n.usbContainerCreationInProgressWait,
        canProceed: _canProceedFor(currentKind, state),
        isLastStep: isLastStep,
        nextLabel: isLastStep ? l10n.eraseAndCreateContainerButton : l10n.wizardNextButton,
        onNext: () => _goNext(state),
        onBackOrExit: () => _goBackOrExit(state),
        errorMessage: state.error,
      ),
    );
  }

  Widget _stepContent(
    _WizStep kind,
    UsbCreateContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) =>
      switch (kind) {
        _WizStep.type => _buildTypeStep(state, cs, textTheme),
        _WizStep.basicInfo => _buildBasicInfoStep(state, cs, textTheme),
        _WizStep.security => _buildSecurityStep(state, cs, textTheme),
        _WizStep.advanced => _buildAdvancedStep(state, cs, textTheme),
        _WizStep.review => _buildReviewStep(state, cs, textTheme),
      };

  Widget _buildTypeStep(UsbCreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.wizardChooseFormatPrompt,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: WizardSelectionCard(
                format: ContainerFormat.veracrypt,
                title: CreateFormat.veracrypt.label,
                selected: state.format == CreateFormat.veracrypt,
                enabled: !state.busy,
                onTap: () =>
                    ref.read(usbCreateContainerProvider.notifier).setFormat(CreateFormat.veracrypt),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WizardSelectionCard(
                format: ContainerFormat.luks1,
                title: CreateFormat.luks1.label,
                selected: state.format == CreateFormat.luks1,
                enabled: !state.busy,
                onTap: () =>
                    ref.read(usbCreateContainerProvider.notifier).setFormat(CreateFormat.luks1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WizardSelectionCard(
                format: ContainerFormat.luks2,
                title: CreateFormat.luks2.label,
                selected: state.format == CreateFormat.luks2,
                enabled: !state.busy,
                onTap: () =>
                    ref.read(usbCreateContainerProvider.notifier).setFormat(CreateFormat.luks2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBasicInfoStep(UsbCreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final busy = state.busy;

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: InlineBanner(
            l10n.formattingErasesEverythingWarning,
            tone: AppBannerTone.warning,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.selectUsbDriveLabel,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.primary,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),
              if (state.loadingDevices)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else if (state.devices.isEmpty)
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.usb_off_rounded, size: 32, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.noUsbStorageDetected,
                          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.connectOtgDriveToFormat,
                          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: busy ? null : () => ref.read(usbCreateContainerProvider.notifier).loadDevices(),
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(l10n.refreshListButton),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                RadioGroup<UsbDeviceInfo>(
                  groupValue: state.selected,
                  onChanged: (v) {
                    if (!busy && v != null) {
                      ref.read(usbCreateContainerProvider.notifier).selectDevice(v, l10n);
                    }
                  },
                  child: Column(
                    children: state.devices.map((d) {
                      final isSelected = state.selected?.deviceName == d.deviceName;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: busy
                              ? null
                              : () => ref
                                  .read(usbCreateContainerProvider.notifier)
                                  .selectDevice(d, l10n),
                          borderRadius: BorderRadius.circular(18),
                          child: Card(
                            elevation: 0,
                            color: isSelected
                                ? cs.primaryContainer.withValues(alpha: 0.15)
                                : cs.surfaceContainerHigh,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                              side: BorderSide(
                                color: isSelected
                                    ? cs.primary
                                    : cs.outlineVariant.withValues(alpha: 0.3),
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? cs.primaryContainer
                                          : cs.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                    child: Icon(
                                      Icons.usb_rounded,
                                      size: 22,
                                      color: isSelected
                                          ? cs.onPrimaryContainer
                                          : cs.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          d.productName,
                                          style: textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          d.hasPermission ? l10n.readyToFormat : l10n.permissionRequired,
                                          style: textTheme.bodySmall?.copyWith(
                                            color: d.hasPermission ? cs.primary : cs.onSurfaceVariant,
                                            fontWeight: d.hasPermission ? FontWeight.w500 : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Radio<UsbDeviceInfo>(
                                    value: d,
                                    activeColor: cs.primary,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _sizeCtrl,
                      enabled: !busy,
                      onChanged: (_) => setState(() {}),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: l10n.containerSizeLabel,
                        prefixIcon: const Icon(Icons.sd_card_outlined, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OptionPickerTile<String>(
                      label: l10n.unitLabel,
                      value: state.sizeUnit,
                      options: [
                        SelectOption(value: 'MB', label: l10n.unitMbMegabytes),
                        SelectOption(value: 'GB', label: l10n.unitGbGigabytes),
                      ],
                      onChanged: busy
                          ? (v) {}
                          : (v) => ref.read(usbCreateContainerProvider.notifier).setSizeUnit(v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  state.fetchingCapacity
                      ? l10n.readingDriveCapacity
                      : state.usableCapacityBytes != null
                          ? l10n.driveUsableCapacity((state.usableCapacityBytes! / (1024 * 1024)).floor())
                          : l10n.mustNotExceedDriveCapacity,
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSecurityStep(UsbCreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final busy = state.busy;

    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _passwordCtrl,
            enabled: !busy,
            obscureText: _obscure,
            onChanged: (_) => setState(() {}),
            autofillHints: null,
            decoration: InputDecoration(
              labelText: l10n.passwordFieldLabel,
              prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
                    tooltip: 'Generate strong password',
                    onPressed: _openPasswordGenerator,
                  ),
                  PasswordVisibilityToggle(
                    obscured: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            controller: _confirmPasswordCtrl,
            enabled: !busy,
            obscureText: _confirmObscure,
            onChanged: (_) => setState(() {}),
            autofillHints: null,
            decoration: InputDecoration(
              labelText: l10n.confirmPasswordFieldLabelTitleCase,
              prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
              suffixIcon: PasswordVisibilityToggle(
                obscured: _confirmObscure,
                onToggle: () => setState(() => _confirmObscure = !_confirmObscure),
              ),
            ),
          ),
        ),
        KeyfilesPicker(
          keyfiles: state.outerKeyfiles,
          picking: state.pickingOuterKeyfiles,
          onPick: () => ref.read(usbCreateContainerProvider.notifier).pickOuterKeyfiles(),
          onRemove: (k) => ref.read(usbCreateContainerProvider.notifier).removeOuterKeyfile(k),
          enabled: !busy,
        ),
      ],
    );
  }

  Widget _buildAdvancedStep(UsbCreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final busy = state.busy;
    final cipherChoices = _cipherChoices(state.format);
    final hashChoices = _hashChoices(state.format);
    final fileSystems = _availableFileSystems(state.format);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          children: [
            OptionPickerTile<int>(
              label: l10n.encryptionAlgorithmLabel,
              value: state.cipherId,
              prefixIcon: Icons.security_rounded,
              options: cipherChoices.map((c) => SelectOption(value: c.id, label: c.label)).toList(),
              onChanged: (val) => ref.read(usbCreateContainerProvider.notifier).setCipherId(val),
            ),
            OptionPickerTile<int>(
              label: l10n.hashAlgorithmLabel,
              value: state.hashId,
              prefixIcon: Icons.tag_rounded,
              options: hashChoices.map((h) => SelectOption(value: h.id, label: h.label)).toList(),
              onChanged: (val) => ref.read(usbCreateContainerProvider.notifier).setHashId(val),
            ),
            OptionPickerTile<String>(
              label: l10n.formatFileSystemLabel,
              value: state.fileSystem,
              prefixIcon: Icons.dns_rounded,
              options: fileSystems.map((fs) => SelectOption(value: fs, label: fs)).toList(),
              onChanged: (val) => ref.read(usbCreateContainerProvider.notifier).setFileSystem(val),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _pimCtrl,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.pimOptionalLabel,
                  prefixIcon: const Icon(Icons.password_outlined, size: 20),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(l10n.quickFormatTitle,
                  style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(
                l10n.quickFormatDescription,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: state.quickFormat,
              onChanged: busy
                  ? null
                  : (val) => ref.read(usbCreateContainerProvider.notifier).setQuickFormat(val),
            ),
          ],
        ),
        if (state.format == CreateFormat.veracrypt) ...[
          const SizedBox(height: 16),
          _buildHiddenVolumeCard(state, cs, textTheme),
        ],
      ],
    );
  }

  Widget _buildHiddenVolumeCard(
    UsbCreateContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;
    final busy = state.busy;
    final bool outerReady = _passwordCtrl.text.isNotEmpty || state.outerKeyfiles.isNotEmpty;
    final validation = _hiddenVolumeValidationResult(state);
    final cipherChoices = _cipherChoices(state.format);
    final hashChoices = _hashChoices(state.format);

    return SectionCard(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: outerReady && state.enableHiddenVolume,
          onChanged: (outerReady && !busy)
              ? (val) => ref.read(usbCreateContainerProvider.notifier).setEnableHiddenVolume(val)
              : null,
          title: Text(l10n.createHiddenVolumeToggleTitle,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            outerReady ? l10n.createInvisibleSecondaryVolume : l10n.setOuterPasswordFirstToEnable,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          secondary: Icon(
            Icons.visibility_off_outlined,
            color: outerReady ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        if (outerReady && state.enableHiddenVolume) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _hiddenPasswordCtrl,
              enabled: !busy,
              obscureText: _hiddenObscure,
              onChanged: (_) => setState(() {}),
              autofillHints: null,
              decoration: InputDecoration(
                labelText: l10n.hiddenPasswordLabel,
                prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _hiddenObscure,
                  onToggle: () => setState(() => _hiddenObscure = !_hiddenObscure),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _hiddenConfirmPasswordCtrl,
              enabled: !busy,
              obscureText: _hiddenConfirmObscure,
              onChanged: (_) => setState(() {}),
              autofillHints: null,
              decoration: InputDecoration(
                labelText: l10n.confirmHiddenPasswordLabel,
                prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _hiddenConfirmObscure,
                  onToggle: () => setState(() => _hiddenConfirmObscure = !_hiddenConfirmObscure),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _hiddenSizeCtrl,
                    enabled: !busy,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: l10n.hiddenSizeLabel,
                      prefixIcon: const Icon(Icons.sd_card_outlined, size: 20),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OptionPickerTile<String>(
                    label: l10n.unitLabel,
                    value: state.hiddenSizeUnit,
                    options: [
                      SelectOption(value: 'MB', label: l10n.unitMbMegabytes),
                      SelectOption(value: 'GB', label: l10n.unitGbGigabytes),
                    ],
                    onChanged: busy
                        ? (val) {}
                        : (val) => ref.read(usbCreateContainerProvider.notifier).setHiddenSizeUnit(val),
                  ),
                ),
              ],
            ),
          ),
          KeyfilesPicker(
            keyfiles: state.hiddenKeyfiles,
            picking: state.pickingHiddenKeyfiles,
            onPick: () => ref.read(usbCreateContainerProvider.notifier).pickHiddenKeyfiles(),
            onRemove: (k) => ref.read(usbCreateContainerProvider.notifier).removeHiddenKeyfile(k),
            enabled: !busy,
          ),
          OptionPickerTile<int>(
            label: l10n.encryptionAlgorithmLabel,
            value: state.hiddenCipherId,
            prefixIcon: Icons.security_rounded,
            options: cipherChoices.map((c) => SelectOption(value: c.id, label: c.label)).toList(),
            onChanged: (val) => ref.read(usbCreateContainerProvider.notifier).setHiddenCipherId(val),
          ),
          OptionPickerTile<int>(
            label: l10n.hashAlgorithmLabel,
            value: state.hiddenHashId,
            prefixIcon: Icons.tag_rounded,
            options: hashChoices.map((h) => SelectOption(value: h.id, label: h.label)).toList(),
            onChanged: (val) => ref.read(usbCreateContainerProvider.notifier).setHiddenHashId(val),
          ),
          OptionPickerTile<String>(
            label: l10n.hiddenFileSystemLabel,
            value: state.hiddenFileSystem,
            prefixIcon: Icons.dns_rounded,
            options: _veraCryptFileSystems.map((fs) => SelectOption(value: fs, label: fs)).toList(),
            onChanged: busy
                ? (val) {}
                : (val) => ref.read(usbCreateContainerProvider.notifier).setHiddenFileSystem(val),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _hiddenPimCtrl,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.pimOptionalLabel,
                prefixIcon: const Icon(Icons.password_outlined, size: 20),
              ),
            ),
          ),
          if (validation != null && !validation.isValid)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: InlineBanner(validation.error!, tone: AppBannerTone.warning),
            ),
        ],
      ],
    );
  }

  Widget _buildReviewStep(UsbCreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final rows = <Widget>[
      WizardSummaryRow(
        icon: Icons.enhanced_encryption_rounded,
        label: l10n.containerFormatLabel,
        value: state.format.label,
      ),
      WizardSummaryRow(
        icon: Icons.usb_rounded,
        label: l10n.wizardSummaryDriveLabel,
        value: state.selected?.productName ?? '—',
      ),
      WizardSummaryRow(
        icon: Icons.sd_card_rounded,
        label: l10n.containerSizeLabel,
        value: '${_sizeCtrl.text} ${state.sizeUnit}',
      ),
      WizardSummaryRow(
        icon: Icons.dns_rounded,
        label: l10n.formatFileSystemLabel,
        value: state.fileSystem,
      ),
      WizardSummaryRow(
        icon: Icons.security_rounded,
        label: l10n.encryptionAlgorithmLabel,
        value: CipherAlgo.nameFor(state.cipherId),
      ),
      WizardSummaryRow(
        icon: Icons.tag_rounded,
        label: l10n.hashAlgorithmLabel,
        value: HashAlgo.nameFor(state.hashId),
      ),
      WizardSummaryRow(
        icon: Icons.password_outlined,
        label: l10n.wizardSummaryPimLabel,
        value: _pimCtrl.text.trim().isEmpty
            ? l10n.wizardSummaryPimDefaultValue
            : _pimCtrl.text.trim(),
      ),
      WizardSummaryRow(
        icon: Icons.bolt_rounded,
        label: l10n.quickFormatTitle,
        value: state.quickFormat ? l10n.vaultInfoYesValue : l10n.vaultInfoNoValue,
      ),
      WizardSummaryRow(
        icon: Icons.key_rounded,
        label: l10n.wizardSummaryPasswordLabel,
        value: _passwordCtrl.text.isNotEmpty
            ? l10n.wizardPasswordSetValue
            : l10n.wizardPasswordNotSetValue,
      ),
      WizardSummaryRow(
        icon: Icons.insert_drive_file_outlined,
        label: l10n.wizardSummaryKeyfilesLabel,
        value: state.outerKeyfiles.isEmpty
            ? l10n.noKeyfilesAttached
            : '${state.outerKeyfiles.length}',
      ),
      WizardSummaryRow(
        icon: Icons.visibility_off_outlined,
        label: l10n.hiddenVolumeHeader,
        value: (state.format == CreateFormat.veracrypt && state.enableHiddenVolume)
            ? l10n.vaultInfoYesValue
            : l10n.vaultInfoNoValue,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: InlineBanner(
            l10n.formattingErasesEverythingWarning,
            tone: AppBannerTone.warning,
          ),
        ),
        SectionHeader(l10n.wizardSummaryTitle),
        SectionCard(children: rows),
      ],
    );
  }
}
