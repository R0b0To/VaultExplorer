import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_scaffold.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_selection_card.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_summary_row.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/features/dashboard/widgets/create_container_controller.dart';
import 'package:vaultexplorer/features/dashboard/widgets/quick_password_generator_sheet.dart';

enum _WizStep { type, basicInfo, security, advanced, review }

class CreateContainerSheet extends ConsumerStatefulWidget {
  const CreateContainerSheet({super.key});

  @override
  ConsumerState<CreateContainerSheet> createState() => _CreateContainerSheetState();
}

class _CreateContainerSheetState extends ConsumerState<CreateContainerSheet> {
  final _nameCtrl = TextEditingController(text: 'vault');
  final _sizeCtrl = TextEditingController(text: '100');
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();

  final _hiddenPasswordCtrl = TextEditingController();
  final _hiddenConfirmPasswordCtrl = TextEditingController();
  final _hiddenPimCtrl = TextEditingController();
  final _hiddenSizeCtrl = TextEditingController(text: '10');

  final _folderVaultPasswordCtrl = TextEditingController();
  final _folderVaultConfirmCtrl = TextEditingController();

  bool _obscure = true;
  bool _confirmObscure = true;
  bool _hiddenObscure = true;
  bool _hiddenConfirmObscure = true;
  bool _folderVaultObscure = true;
  bool _folderVaultConfirmObscure = true;

  static const _veraCryptFileSystems = ['FAT', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4'];
  static const _luksFileSystems = ['FAT', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _sizeCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _pimCtrl.dispose();
    _hiddenPasswordCtrl.dispose();
    _hiddenConfirmPasswordCtrl.dispose();
    _hiddenPimCtrl.dispose();
    _hiddenSizeCtrl.dispose();
    _folderVaultPasswordCtrl.dispose();
    _folderVaultConfirmCtrl.dispose();
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

  String _folderVaultFormatDisplayLabel(String format) => switch (format) {
        'cryptomator' => 'Cryptomator',
        'gocryptfs' => 'Gocryptfs',
        'cryfs' => 'CryFS',
        _ => format,
      };

  String _gocryptfsCipherDisplayLabel(String cipher) => switch (cipher) {
        'aes-256-gcm' => 'AES-256-GCM',
        'xchacha20-poly1305' => 'XChaCha20-Poly1305',
        _ => cipher,
      };

  String _cryfsCipherDisplayLabel(String cipher) => switch (cipher) {
        'xchacha20-poly1305' => 'XChaCha20-Poly1305',
        'aes-256-gcm' => 'AES-256-GCM',
        _ => cipher,
      };

  String _cryfsBlockSizeDisplayLabel(int blockSize) => switch (blockSize) {
        const (4 * 1024) => '4 KiB',
        const (8 * 1024) => '8 KiB',
        const (16 * 1024) => '16 KiB',
        const (32 * 1024) => '32 KiB (default)',
        const (64 * 1024) => '64 KiB',
        const (128 * 1024) => '128 KiB',
        const (512 * 1024) => '512 KiB',
        const (1024 * 1024) => '1 MiB',
        const (4 * 1024 * 1024) => '4 MiB',
        _ => '$blockSize B',
      };

  Future<void> _create(CreateContainerState state) async {
    final l10n = context.l10n;
    final ok = state.isFolderVault
        ? await ref.read(createContainerProvider.notifier).createFolderVault(
              password: _folderVaultPasswordCtrl.text,
              confirmPassword: _folderVaultConfirmCtrl.text,
              l10n: l10n,
            )
        : await ref.read(createContainerProvider.notifier).createContainerFile(
              nameText: _nameCtrl.text,
              sizeText: _sizeCtrl.text,
              passwordText: _passwordCtrl.text,
              confirmPasswordText: _confirmPasswordCtrl.text,
              pimText: _pimCtrl.text,
              hiddenPasswordText: _hiddenPasswordCtrl.text,
              hiddenConfirmPasswordText: _hiddenConfirmPasswordCtrl.text,
              hiddenPimText: _hiddenPimCtrl.text,
              hiddenSizeText: _hiddenSizeCtrl.text,
              l10n: l10n,
            );

    if (ok && mounted) {
      Navigator.pop(context);
      showAppSnackBar(
        context,
        message: state.isFolderVault
            ? l10n.vaultCreatedSuccessfully
            : l10n.containerFileCreatedSuccessfully,
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _openPasswordGenerator({required bool isFolderVault}) async {
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
        if (isFolderVault) {
          _folderVaultPasswordCtrl.text = password;
          _folderVaultConfirmCtrl.text = password;
          _folderVaultObscure = false;
          _folderVaultConfirmObscure = false;
        } else {
          _passwordCtrl.text = password;
          _confirmPasswordCtrl.text = password;
          _obscure = false;
          _confirmObscure = false;
        }
      });
      await ref.read(sensitiveClipboardProvider).copy(password);
    }
  }

  List<_WizStep> _stepKinds(CreateContainerState state) => [
        _WizStep.type,
        _WizStep.basicInfo,
        _WizStep.security,
        if (!state.isFolderVault || state.folderVaultFormat != 'cryptomator') _WizStep.advanced,
        _WizStep.review,
      ];

  bool _canProceedBasicInfo(CreateContainerState state) => state.isFolderVault
      ? state.folderVaultUri != null
      : (_nameCtrl.text.trim().isNotEmpty && (double.tryParse(_sizeCtrl.text) ?? 0) > 0);

  bool _canProceedSecurity(CreateContainerState state) => state.isFolderVault
      ? (_folderVaultPasswordCtrl.text.isNotEmpty &&
          _folderVaultPasswordCtrl.text == _folderVaultConfirmCtrl.text)
      : ((_passwordCtrl.text.isNotEmpty || state.outerKeyfiles.isNotEmpty) &&
          (_passwordCtrl.text.isEmpty ||
              _passwordCtrl.text == _confirmPasswordCtrl.text));

  HiddenVolumeValidation? _hiddenVolumeValidationResult(CreateContainerState state) {
    if (!state.enableHiddenVolume || state.isFolderVault || state.format != CreateFormat.veracrypt) {
      return null;
    }
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

  bool _canProceedAdvanced(CreateContainerState state) {
    if (!state.enableHiddenVolume || state.isFolderVault || state.format != CreateFormat.veracrypt) {
      return true;
    }
    final validation = _hiddenVolumeValidationResult(state);
    return validation == null || validation.isValid;
  }

  bool _canProceedFor(_WizStep kind, CreateContainerState state) => switch (kind) {
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

  void _goNext(CreateContainerState state, List<_WizStep> kinds) {
    final safe = state.currentStep.clamp(0, kinds.length - 1);
    if (safe == kinds.length - 1) {
      _create(state);
    } else {
      ref.read(createContainerProvider.notifier).setCurrentStep(safe + 1);
    }
  }

  void _goBackOrExit(CreateContainerState state) {
    if (state.currentStep > 0) {
      ref.read(createContainerProvider.notifier).setCurrentStep(state.currentStep - 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(createContainerProvider);
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;

    final kinds = _stepKinds(state);
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
        appBarTitle: state.isFolderVault
            ? l10n.createEncryptedVaultTitle
            : l10n.createEncryptedContainerTitle,
        currentStep: safeStep,
        totalSteps: kinds.length,
        stepTitle: _stepTitle(currentKind),
        stepContent: _stepContent(currentKind, state, cs, textTheme),
        busy: state.loading,
        busyMessage: state.isFolderVault
            ? l10n.vaultCreationInProgressWait
            : l10n.containerCreationInProgressWait,
        canProceed: _canProceedFor(currentKind, state),
        isLastStep: isLastStep,
        nextLabel: isLastStep
            ? (state.isFolderVault ? l10n.createVaultButton : l10n.createContainerButton)
            : l10n.wizardNextButton,
        onNext: () => _goNext(state, kinds),
        onBackOrExit: () => _goBackOrExit(state),
        errorMessage: state.error,
      ),
    );
  }

  Widget _stepContent(
    _WizStep kind,
    CreateContainerState state,
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

  Widget _buildTypeStep(CreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.wizardCreateTypePrompt,
          style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: WizardSelectionCard(
                icon: Icons.folder_zip_rounded,
                title: l10n.vaultKindContainerFile,
                selected: !state.isFolderVault,
                enabled: !state.loading,
                onTap: () => ref.read(createContainerProvider.notifier).setVaultKind(false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: WizardSelectionCard(
                icon: Icons.folder_shared_rounded,
                title: l10n.vaultKindFolderVault,
                selected: state.isFolderVault,
                enabled: !state.loading,
                onTap: () => ref.read(createContainerProvider.notifier).setVaultKind(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          state.isFolderVault ? l10n.vaultFormatLabel : l10n.containerFormatLabel,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        state.isFolderVault
            ? _buildFolderVaultFormatCards(state)
            : _buildContainerFormatCards(state),
      ],
    );
  }

  Widget _buildContainerFormatCards(CreateContainerState state) {
    return Row(
      children: [
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.veracrypt,
            title: CreateFormat.veracrypt.label,
            selected: state.format == CreateFormat.veracrypt,
            enabled: !state.loading,
            onTap: () =>
                ref.read(createContainerProvider.notifier).setFormat(CreateFormat.veracrypt),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.luks1,
            title: CreateFormat.luks1.label,
            selected: state.format == CreateFormat.luks1,
            enabled: !state.loading,
            onTap: () => ref.read(createContainerProvider.notifier).setFormat(CreateFormat.luks1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.luks2,
            title: CreateFormat.luks2.label,
            selected: state.format == CreateFormat.luks2,
            enabled: !state.loading,
            onTap: () => ref.read(createContainerProvider.notifier).setFormat(CreateFormat.luks2),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderVaultFormatCards(CreateContainerState state) {
    return Row(
      children: [
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.cryptomator,
            title: 'Cryptomator',
            selected: state.folderVaultFormat == 'cryptomator',
            enabled: !state.loading,
            onTap: () =>
                ref.read(createContainerProvider.notifier).setFolderVaultFormat('cryptomator'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.gocryptfs,
            title: 'Gocryptfs',
            selected: state.folderVaultFormat == 'gocryptfs',
            enabled: !state.loading,
            onTap: () =>
                ref.read(createContainerProvider.notifier).setFolderVaultFormat('gocryptfs'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.cryfs,
            title: 'CryFS',
            selected: state.folderVaultFormat == 'cryfs',
            enabled: !state.loading,
            onTap: () =>
                ref.read(createContainerProvider.notifier).setFolderVaultFormat('cryfs'),
          ),
        ),
      ],
    );
  }

  Widget _buildBasicInfoStep(CreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    if (state.isFolderVault) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFolderVaultPickerCard(state, cs, textTheme),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.folderVaultLimitationsNote,
                  style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                ),
              ),
            ],
          ),
        ],
      );
    }
    return SectionCard(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _nameCtrl,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.fileNameLabel,
              prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded, size: 20),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _sizeCtrl,
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
                    SelectOption(value: 'MB', label: l10n.unitMbShort),
                    SelectOption(value: 'GB', label: l10n.unitGbShort),
                  ],
                  onChanged: (val) =>
                      ref.read(createContainerProvider.notifier).setSizeUnit(val),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFolderVaultPickerCard(
    CreateContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final hasSelection = state.folderVaultUri != null;
    final busy = state.loading || state.pickingFolderVault;
    final format = ContainerFormat.fromWire(state.folderVaultFormat);

    return GestureDetector(
      onTap: busy
          ? null
          : () => ref
              .read(createContainerProvider.notifier)
              .pickFolderVaultLocation(context.l10n),
      child: Card(
        elevation: 0,
        color: hasSelection ? cs.primaryContainer.withValues(alpha: 0.15) : cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasSelection ? cs.primaryContainer : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: ContainerFormatIcon(
                  format: format,
                  color: hasSelection ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSelection
                          ? context.l10n.destinationFolderLabel
                          : context.l10n.selectEmptyFolderLabel,
                      style: textTheme.labelMedium?.copyWith(
                        color: hasSelection ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.folderVaultDisplayName ?? context.l10n.tapToChooseVaultLocation,
                      style: textTheme.bodyLarge?.copyWith(
                        color: hasSelection ? cs.onSurface : cs.onSurfaceVariant,
                        fontWeight: hasSelection ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (state.pickingFolderVault)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (hasSelection)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: state.loading
                      ? null
                      : () => ref
                          .read(createContainerProvider.notifier)
                          .clearFolderVaultLocation(),
                  style: IconButton.styleFrom(
                    backgroundColor: cs.surfaceContainerHigh,
                    padding: EdgeInsets.zero,
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant, size: 18),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecurityStep(CreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    return SectionCard(
      children: state.isFolderVault
          ? _buildFolderVaultPasswordFields(cs)
          : [..._buildPasswordFields(cs), _buildKeyfilesPicker(state)],
    );
  }

  List<Widget> _buildPasswordFields(ColorScheme cs) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          onChanged: (_) => setState(() {}),
          autofillHints: null,
          decoration: InputDecoration(
            labelText: context.l10n.passwordFieldLabel,
            prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
                  tooltip: 'Generate strong password',
                  onPressed: () => _openPasswordGenerator(isFolderVault: false),
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
          obscureText: _confirmObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: null,
          decoration: InputDecoration(
            labelText: context.l10n.confirmPasswordFieldLabelTitleCase,
            prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _confirmObscure,
              onToggle: () => setState(() => _confirmObscure = !_confirmObscure),
            ),
          ),
        ),
      ),
    ];
  }

  List<Widget> _buildFolderVaultPasswordFields(ColorScheme cs) {
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _folderVaultPasswordCtrl,
          obscureText: _folderVaultObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: null,
          decoration: InputDecoration(
            labelText: context.l10n.passwordFieldLabel,
            prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.auto_awesome_rounded, size: 20, color: cs.primary),
                  tooltip: 'Generate strong password',
                  onPressed: () => _openPasswordGenerator(isFolderVault: true),
                ),
                PasswordVisibilityToggle(
                  obscured: _folderVaultObscure,
                  onToggle: () => setState(() => _folderVaultObscure = !_folderVaultObscure),
                ),
              ],
            ),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: TextField(
          controller: _folderVaultConfirmCtrl,
          obscureText: _folderVaultConfirmObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: null,
          decoration: InputDecoration(
            labelText: context.l10n.confirmPasswordFieldLabelTitleCase,
            prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _folderVaultConfirmObscure,
              onToggle: () => setState(() => _folderVaultConfirmObscure = !_folderVaultConfirmObscure),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildKeyfilesPicker(CreateContainerState state) {
    return KeyfilesPicker(
      keyfiles: state.outerKeyfiles,
      picking: state.pickingOuterKeyfiles,
      onPick: () => ref.read(createContainerProvider.notifier).pickOuterKeyfiles(),
      onRemove: (k) => ref.read(createContainerProvider.notifier).removeOuterKeyfile(k),
      enabled: !state.loading,
    );
  }

  Widget _buildAdvancedStep(CreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;

    if (state.isFolderVault) {
      if (state.folderVaultFormat == 'gocryptfs') {
        return SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(1),
              child: OptionPickerTile<String>(
                label: l10n.gocryptfsCipherLabel,
                value: state.gocryptfsCipher,
                prefixIcon: Icons.enhanced_encryption_rounded,
                options: const [
                  SelectOption(value: 'aes-256-gcm', label: 'AES-256-GCM'),
                  SelectOption(value: 'xchacha20-poly1305', label: 'XChaCha20-Poly1305'),
                ],
                onChanged: (val) =>
                    ref.read(createContainerProvider.notifier).setGocryptfsCipher(val),
              ),
            ),
          ],
        );
      }
      if (state.folderVaultFormat == 'cryfs') {
        return SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(1),
              child: OptionPickerTile<String>(
                label: l10n.cryfsCipherLabel,
                value: state.cryfsCipher,
                prefixIcon: Icons.enhanced_encryption_rounded,
                options: const [
                  SelectOption(value: 'xchacha20-poly1305', label: 'XChaCha20-Poly1305'),
                  SelectOption(value: 'aes-256-gcm', label: 'AES-256-GCM'),
                ],
                onChanged: (val) =>
                    ref.read(createContainerProvider.notifier).setCryfsCipher(val),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(1),
              child: OptionPickerTile<int>(
                label: l10n.cryfsBlockSizeLabel,
                value: state.cryfsBlockSize,
                prefixIcon: Icons.grid_view_rounded,
                options: const [
                  SelectOption(value: 4 * 1024, label: '4 KiB'),
                  SelectOption(value: 8 * 1024, label: '8 KiB'),
                  SelectOption(value: 16 * 1024, label: '16 KiB'),
                  SelectOption(value: 32 * 1024, label: '32 KiB (default)'),
                  SelectOption(value: 64 * 1024, label: '64 KiB'),
                  SelectOption(value: 128 * 1024, label: '128 KiB'),
                  SelectOption(value: 512 * 1024, label: '512 KiB'),
                  SelectOption(value: 1024 * 1024, label: '1 MiB'),
                  SelectOption(value: 4 * 1024 * 1024, label: '4 MiB'),
                ],
                onChanged: (val) =>
                    ref.read(createContainerProvider.notifier).setCryfsBlockSize(val),
              ),
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    }

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
              options: cipherChoices
                  .map((c) => SelectOption(value: c.id, label: c.label))
                  .toList(),
              onChanged: (val) =>
                  ref.read(createContainerProvider.notifier).setCipherId(val),
            ),
            OptionPickerTile<int>(
              label: l10n.hashAlgorithmLabel,
              value: state.hashId,
              prefixIcon: Icons.tag_rounded,
              options:
                  hashChoices.map((h) => SelectOption(value: h.id, label: h.label)).toList(),
              onChanged: (val) =>
                  ref.read(createContainerProvider.notifier).setHashId(val),
            ),
            OptionPickerTile<String>(
              label: l10n.formatFileSystemLabel,
              value: state.fileSystem,
              prefixIcon: Icons.dns_rounded,
              options: fileSystems.map((fs) => SelectOption(value: fs, label: fs)).toList(),
              onChanged: (val) =>
                  ref.read(createContainerProvider.notifier).setFileSystem(val),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: TextField(
                controller: _pimCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.pimOptionalLabel,
                  prefixIcon: const Icon(Icons.password_outlined, size: 20),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text(
                l10n.quickFormatTitle,
                style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                l10n.quickFormatDescription,
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: state.quickFormat,
              onChanged: state.loading
                  ? null
                  : (val) =>
                      ref.read(createContainerProvider.notifier).setQuickFormat(val),
            ),
          ],
        ),
        if (!state.isFolderVault && state.format == CreateFormat.veracrypt) ...[
          const SizedBox(height: 16),
          _buildHiddenVolumeCard(state, cs, textTheme),
        ],
      ],
    );
  }

  Widget _buildHiddenVolumeCard(
    CreateContainerState state,
    ColorScheme cs,
    TextTheme textTheme,
  ) {
    final l10n = context.l10n;
    final bool outerReady = _passwordCtrl.text.isNotEmpty || state.outerKeyfiles.isNotEmpty;
    final validation = _hiddenVolumeValidationResult(state);
    final cipherChoices = _cipherChoices(state.format);
    final hashChoices = _hashChoices(state.format);
    final fileSystems = _availableFileSystems(state.format);

    return SectionCard(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: outerReady && state.enableHiddenVolume,
          onChanged: outerReady
              ? (val) => ref.read(createContainerProvider.notifier).setEnableHiddenVolume(val)
              : null,
          title: Text(
            l10n.createHiddenVolumeToggleTitle,
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
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
                    onChanged: (val) =>
                        ref.read(createContainerProvider.notifier).setHiddenSizeUnit(val),
                  ),
                ),
              ],
            ),
          ),
          KeyfilesPicker(
            keyfiles: state.hiddenKeyfiles,
            picking: state.pickingHiddenKeyfiles,
            onPick: () => ref.read(createContainerProvider.notifier).pickHiddenKeyfiles(),
            onRemove: (k) => ref.read(createContainerProvider.notifier).removeHiddenKeyfile(k),
            enabled: !state.loading,
          ),
          OptionPickerTile<int>(
            label: l10n.encryptionAlgorithmLabel,
            value: state.hiddenCipherId,
            prefixIcon: Icons.security_rounded,
            options: cipherChoices
                .map((c) => SelectOption(value: c.id, label: c.label))
                .toList(),
            onChanged: (val) =>
                ref.read(createContainerProvider.notifier).setHiddenCipherId(val),
          ),
          OptionPickerTile<int>(
            label: l10n.hashAlgorithmLabel,
            value: state.hiddenHashId,
            prefixIcon: Icons.tag_rounded,
            options:
                hashChoices.map((h) => SelectOption(value: h.id, label: h.label)).toList(),
            onChanged: (val) =>
                ref.read(createContainerProvider.notifier).setHiddenHashId(val),
          ),
          OptionPickerTile<String>(
            label: l10n.hiddenFileSystemLabel,
            value: state.hiddenFileSystem,
            prefixIcon: Icons.dns_rounded,
            options: fileSystems.map((fs) => SelectOption(value: fs, label: fs)).toList(),
            onChanged: (val) =>
                ref.read(createContainerProvider.notifier).setHiddenFileSystem(val),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _hiddenPimCtrl,
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

  Widget _buildReviewStep(CreateContainerState state, ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final rows = <Widget>[
      WizardSummaryRow(
        icon: Icons.category_rounded,
        label: l10n.metaLabelType,
        value: state.isFolderVault ? l10n.vaultKindFolderVault : l10n.vaultKindContainerFile,
      ),
    ];

    if (state.isFolderVault) {
      rows.addAll([
        WizardSummaryRow(
          icon: Icons.enhanced_encryption_rounded,
          label: l10n.vaultFormatLabel,
          value: _folderVaultFormatDisplayLabel(state.folderVaultFormat),
        ),
        WizardSummaryRow(
          icon: Icons.folder_rounded,
          label: l10n.vaultInfoLocationLabel,
          value: state.folderVaultDisplayName ?? '—',
        ),
        if (state.folderVaultFormat == 'gocryptfs')
          WizardSummaryRow(
            icon: Icons.security_rounded,
            label: l10n.encryptionAlgorithmLabel,
            value: _gocryptfsCipherDisplayLabel(state.gocryptfsCipher),
          )
        else if (state.folderVaultFormat == 'cryfs') ...[
          WizardSummaryRow(
            icon: Icons.security_rounded,
            label: l10n.encryptionAlgorithmLabel,
            value: _cryfsCipherDisplayLabel(state.cryfsCipher),
          ),
          WizardSummaryRow(
            icon: Icons.grid_view_rounded,
            label: l10n.cryfsBlockSizeLabel,
            value: _cryfsBlockSizeDisplayLabel(state.cryfsBlockSize),
          ),
        ],
      ]);
    } else {
      rows.addAll([
        WizardSummaryRow(
          icon: Icons.enhanced_encryption_rounded,
          label: l10n.containerFormatLabel,
          value: state.format.label,
        ),
        WizardSummaryRow(
          icon: Icons.drive_file_rename_outline_rounded,
          label: l10n.fileNameLabel,
          value: _nameCtrl.text.isEmpty ? '—' : _nameCtrl.text,
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
      ]);
    }

    rows.add(WizardSummaryRow(
      icon: Icons.key_rounded,
      label: l10n.wizardSummaryPasswordLabel,
      value: (state.isFolderVault ? _folderVaultPasswordCtrl : _passwordCtrl).text.isNotEmpty
          ? l10n.wizardPasswordSetValue
          : l10n.wizardPasswordNotSetValue,
    ));

    if (!state.isFolderVault) {
      rows.addAll([
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
          value: (!state.isFolderVault && state.format == CreateFormat.veracrypt && state.enableHiddenVolume)
              ? l10n.vaultInfoYesValue
              : l10n.vaultInfoNoValue,
        ),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(l10n.wizardSummaryTitle),
        SectionCard(children: rows),
      ],
    );
  }
}
