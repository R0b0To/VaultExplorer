import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/format_utils.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/container_format_icon.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_scaffold.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_selection_card.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_summary_row.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

enum _WizStep { type, basicInfo, security, advanced, review }

class CreateContainerSheet extends StatefulWidget {
  const CreateContainerSheet({super.key});
  @override
  State<CreateContainerSheet> createState() => _CreateContainerSheetState();
}

class _CreateContainerSheetState extends State<CreateContainerSheet> with KeyfilePickerMixin {
  final _nameCtrl = TextEditingController(text: 'vault');
  final _sizeCtrl = TextEditingController(text: '100');
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();
  static const _veraCryptFileSystems = ['FAT', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4'];
  static const _luksFileSystems = ['FAT', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4'];
  String _sizeUnit = 'MB';
  CreateFormat _format = CreateFormat.veracrypt;
  String _fileSystem = 'FAT';
  int _cipherId = 0;
  int _hashId = 0;
  bool _quickFormat = true;
  bool _obscure = true;
  bool _confirmObscure = true;
  bool _loading = false;
  String? _error;
  bool _enableHiddenVolume = false;
  final _hiddenPasswordCtrl = TextEditingController();
  final _hiddenConfirmPasswordCtrl = TextEditingController();
  final _hiddenPimCtrl = TextEditingController();
  bool _hiddenObscure = true;
  bool _hiddenConfirmObscure = true;
  String _hiddenSizeUnit = 'MB';
  final _hiddenSizeCtrl = TextEditingController(text: '10');
  late final _hiddenKeyfilesController = KeyfilePickerController(
    notify: () { if (mounted) setState(() {}); },
    onError: (msg) { if (mounted) setState(() => _error = msg ?? context.l10n.couldNotPickKeyfiles); },
  );
  String _hiddenFileSystem = 'FAT';
  int _hiddenCipherId = 0;
  int _hiddenHashId = 0;

  int _currentStep = 0;

  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);

  bool _isFolderVault = false;
  String _folderVaultFormat = 'cryptomator';
  String _gocryptfsCipher = 'aes-256-gcm';
  String _cryfsCipher = 'xchacha20-poly1305';
  int _cryfsBlockSize = 32 * 1024;
  String? _folderVaultUri;
  String? _folderVaultDisplayName;
  bool _pickingFolderVault = false;
  final _folderVaultPasswordCtrl = TextEditingController();
  final _folderVaultConfirmCtrl = TextEditingController();
  bool _folderVaultObscure = true;
  bool _folderVaultConfirmObscure = true;

  List<String> get _availableFileSystems =>
      _format == CreateFormat.veracrypt ? _veraCryptFileSystems : _luksFileSystems;

  List<CipherAlgo> get _cipherChoices => switch (_format) {
        CreateFormat.veracrypt => CipherAlgo.concrete,
        CreateFormat.luks1 => CipherAlgo.luks1Choices,
        CreateFormat.luks2 => CipherAlgo.luks2Choices,
      };

  List<HashAlgo> get _hashChoices => switch (_format) {
        CreateFormat.veracrypt => HashAlgo.concrete,
        CreateFormat.luks1 => HashAlgo.luks1Choices,
        CreateFormat.luks2 => HashAlgo.luks2Choices,
      };

  String get _folderVaultFormatDisplayLabel => switch (_folderVaultFormat) {
        'cryptomator' => 'Cryptomator',
        'gocryptfs' => 'Gocryptfs',
        'cryfs' => 'CryFS',
        _ => _folderVaultFormat,
      };

  // Display labels for the folder-vault cipher/block-size choices, so the
  // Review step can show what was actually picked — mirrors the label
  // text in the SelectOption lists on the Advanced step.
  String get _gocryptfsCipherDisplayLabel => switch (_gocryptfsCipher) {
        'aes-256-gcm' => 'AES-256-GCM',
        'xchacha20-poly1305' => 'XChaCha20-Poly1305',
        _ => _gocryptfsCipher,
      };

  String get _cryfsCipherDisplayLabel => switch (_cryfsCipher) {
        'xchacha20-poly1305' => 'XChaCha20-Poly1305',
        'aes-256-gcm' => 'AES-256-GCM',
        _ => _cryfsCipher,
      };

String get _cryfsBlockSizeDisplayLabel => switch (_cryfsBlockSize) {
      const (4 * 1024) => '4 KiB',
      const (8 * 1024) => '8 KiB',
      const (16 * 1024) => '16 KiB',
      const (32 * 1024) => '32 KiB (default)',
      const (64 * 1024) => '64 KiB',
      const (128 * 1024) => '128 KiB',
      const (512 * 1024) => '512 KiB',
      const (1024 * 1024) => '1 MiB',
      const (4 * 1024 * 1024) => '4 MiB',
      _ => '$_cryfsBlockSize B',
    };

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

  void _onFormatChanged(CreateFormat format) {
    setState(() {
      _format = format;
      if (format == CreateFormat.luks1 || format == CreateFormat.luks2) {
        _fileSystem = 'ext4';
      } else {
        _fileSystem = 'FAT';
      }
      if (!_cipherChoices.any((c) => c.id == _cipherId)) {
        _cipherId = _cipherChoices.first.id;
      }
      if (!_hashChoices.any((h) => h.id == _hashId)) {
        _hashId = _hashChoices.first.id;
      }
      _hiddenFileSystem = 'FAT';
    });
  }

  void _onVaultKindChanged(bool folderVault) {
    setState(() {
      _isFolderVault = folderVault;
      _error = null;
    });
  }

  void _onFolderVaultFormatChanged(String format) {
    setState(() {
      _folderVaultFormat = format;
      _folderVaultUri = null;
      _folderVaultDisplayName = null;
      _error = null;
    });
  }

  Future<void> _pickFolderVaultLocation() async {
    setState(() {
      _pickingFolderVault = true;
      _error = null;
    });
    try {
      final result = _folderVaultFormat == 'cryptomator'
          ? await vaultExplorerApi.pickCryptomatorVault()
          : _folderVaultFormat == 'gocryptfs'
              ? await vaultExplorerApi.pickGocryptfsVault()
              : await vaultExplorerApi.pickCryfsVault();
      if (result != null && mounted) {
        setState(() {
          _folderVaultUri = result.uri;
          _folderVaultDisplayName = result.displayName;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = context.l10n.folderPickerFailed('$e'));
    } finally {
      if (mounted) setState(() => _pickingFolderVault = false);
    }
  }

  Future<void> _create() {
    return _isFolderVault ? _createFolderVault() : _createContainerFile();
  }

  Future<void> _createFolderVault() async {
    if (_folderVaultUri == null) {
      setState(() => _error = context.l10n.selectEmptyDestinationFolderFirst);
      return;
    }
    final password = _folderVaultPasswordCtrl.text;
    if (password.isEmpty) {
      setState(() => _error = context.l10n.passwordRequired);
      return;
    }
    if (password != _folderVaultConfirmCtrl.text) {
      setState(() => _error = context.l10n.passwordsDoNotMatch);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final success = _folderVaultFormat == 'cryptomator'
          ? await vaultExplorerApi.createCryptomatorVault(_folderVaultUri!, password)
          : _folderVaultFormat == 'gocryptfs'
              ? await vaultExplorerApi.createGocryptfsVault(
                  _folderVaultUri!,
                  password,
                  cipher: _gocryptfsCipher,
                )
              : await vaultExplorerApi.createCryfsVault(
                  _folderVaultUri!,
                  password,
                  cipher: _cryfsCipher,
                  blockSize: _cryfsBlockSize,
                );
      if (success) {
        if (mounted) {
          Navigator.pop(context);
          showAppSnackBar(
            context,
            message: context.l10n.vaultCreatedSuccessfully,
            tone: AppBannerTone.success,
          );
        }
      } else {
        setState(() => _error = context.l10n.vaultCreationFailedEmptyFolder);
      }
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? context.l10n.unknownErrorOccurred);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createContainerFile() async {
    if (_nameCtrl.text.isEmpty) {
      setState(() => _error = context.l10n.containerNameRequired);
      return;
    }
    final sizeVal = double.tryParse(_sizeCtrl.text);
    if (sizeVal == null || sizeVal <= 0) {
      setState(() => _error = context.l10n.enterValidSizeGreaterThanZero);
      return;
    }
    if (_passwordCtrl.text.isEmpty && keyfiles.isEmpty) {
      setState(() => _error = context.l10n.passwordOrKeyfileRequired);
      return;
    }
    if (_passwordCtrl.text.isNotEmpty &&
        _passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() => _error = context.l10n.standardVolumePasswordsDoNotMatch);
      return;
    }
    if (_enableHiddenVolume && _format == CreateFormat.veracrypt) {
      if (_hiddenPasswordCtrl.text.isNotEmpty &&
          _hiddenPasswordCtrl.text != _hiddenConfirmPasswordCtrl.text) {
        setState(() => _error = context.l10n.hiddenVolumePasswordsDoNotMatch);
        return;
      }
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final multiplier = _sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
      final sizeBytes = (sizeVal * multiplier).round();
      int hiddenSizeBytes = 0;
      if (_enableHiddenVolume && _format == CreateFormat.veracrypt) {
        final outerPimClamped = clampPim(
          _pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0,
        );
        final hiddenPimClamped = clampPim(
          _hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0,
        );
        final validation = validateHiddenVolume(
          hiddenSizeText: _hiddenSizeCtrl.text,
          hiddenSizeUnit: _hiddenSizeUnit,
          outerSizeBytes: sizeBytes,
          outerPimClamped: outerPimClamped,
          hiddenPimClamped: hiddenPimClamped,
          outerPassword: _passwordCtrl.text,
          hiddenPassword: _hiddenPasswordCtrl.text,
          hasHiddenKeyfiles: _hiddenKeyfilesController.keyfiles.isNotEmpty,
          outerKeyfileUris: keyfiles.map((k) => k.uri).toSet(),
          hiddenKeyfileUris: _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toSet(),
          l10n: context.l10n,
        );
        if (!validation.isValid) {
          setState(() => _error = validation.error);
          return;
        }
        hiddenSizeBytes = validation.hiddenSizeBytes!;
      }
      final pim = clampPim(
        _pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0,
      );
      final success = await vaultExplorerApi.createContainer(
        displayName: _nameCtrl.text,
        sizeBytes: sizeBytes,
        password: _passwordCtrl.text,
        pim: pim,
        fileSystem: _fileSystem.toLowerCase(),
        containerFormat: _format.id,
        cipherId: _cipherId,
        hashId: _hashId,
        keyfilePaths: keyfiles.map((k) => k.uri).toList(),
        quickFormat: _quickFormat,
        createHiddenVolume: _enableHiddenVolume && _format == CreateFormat.veracrypt,
        hiddenPassword: _hiddenPasswordCtrl.text,
        hiddenFileSystem: _hiddenFileSystem.toLowerCase(),
        hiddenSizeBytes: hiddenSizeBytes,
        hiddenKeyfilePaths: _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toList(),
        hiddenPim: _enableHiddenVolume ? clampPim(_hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0) : 0,
        hiddenCipherId: _enableHiddenVolume ? _hiddenCipherId : 255,
        hiddenHashId: _enableHiddenVolume ? _hiddenHashId : 255,
      );
      if (success) {
        if (mounted) {
          Navigator.pop(context);
          showAppSnackBar(
            context,
            message: context.l10n.containerFileCreatedSuccessfully,
            tone: AppBannerTone.success,
          );
        }
      } else {
        setState(() => _error = context.l10n.containerCreationCancelledOrFailed);
      }
    } on PlatformException catch (e) {
      if (e.code == 'INSUFFICIENT_SPACE') {
        final details = e.details;
        final needed = details is Map ? details['neededBytes'] as int? : null;
        final available = details is Map ? details['availableBytes'] as int? : null;
        setState(() => _error = (needed != null && available != null)
            ? context.l10n.insufficientSpaceForContainer(
                formatBytes(needed), formatBytes(available))
            : e.message ?? context.l10n.unknownErrorOccurred);
      } else {
        setState(() => _error = e.message ?? context.l10n.unknownErrorOccurred);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------
  // Password Generator Integration (Directly fills & un-obscures fields)
  // ---------------------------------------------------------------------

  Future<void> _openPasswordGenerator({required bool isFolderVault}) async {
    final password = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
      ),
      builder: (ctx) => const _QuickPasswordGeneratorSheet(),
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
      await SensitiveClipboard.copy(password);
    }
  }

  // ---------------------------------------------------------------------
  // Wizard Navigation & Validity
  // ---------------------------------------------------------------------

  bool get _showAdvancedStep => !_isFolderVault || _folderVaultFormat != 'cryptomator';
  bool get _showHiddenVolumeSection => !_isFolderVault && _format == CreateFormat.veracrypt;

  List<_WizStep> get _stepKinds => [
        _WizStep.type,
        _WizStep.basicInfo,
        _WizStep.security,
        if (_showAdvancedStep) _WizStep.advanced,
        _WizStep.review,
      ];

  bool get _canProceedBasicInfo => _isFolderVault
      ? _folderVaultUri != null
      : (_nameCtrl.text.trim().isNotEmpty &&
          (double.tryParse(_sizeCtrl.text) ?? 0) > 0);

  bool get _canProceedSecurity => _isFolderVault
      ? (_folderVaultPasswordCtrl.text.isNotEmpty &&
          _folderVaultPasswordCtrl.text == _folderVaultConfirmCtrl.text)
      : ((_passwordCtrl.text.isNotEmpty || keyfiles.isNotEmpty) &&
          (_passwordCtrl.text.isEmpty ||
              _passwordCtrl.text == _confirmPasswordCtrl.text));

  HiddenVolumeValidation? get _hiddenVolumeValidationResult {
    if (!_enableHiddenVolume || !_showHiddenVolumeSection) return null;
    final sizeVal = double.tryParse(_sizeCtrl.text);
    if (sizeVal == null || sizeVal <= 0) return null;
    final multiplier = _sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
    final outerSizeBytes = (sizeVal * multiplier).round();
    final outerPim = clampPim(
      _pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0,
    );
    final hiddenPim = clampPim(
      _hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0,
    );
    return validateHiddenVolume(
      hiddenSizeText: _hiddenSizeCtrl.text,
      hiddenSizeUnit: _hiddenSizeUnit,
      outerSizeBytes: outerSizeBytes,
      outerPimClamped: outerPim,
      hiddenPimClamped: hiddenPim,
      outerPassword: _passwordCtrl.text,
      hiddenPassword: _hiddenPasswordCtrl.text,
      hasHiddenKeyfiles: _hiddenKeyfilesController.keyfiles.isNotEmpty,
      outerKeyfileUris: keyfiles.map((k) => k.uri).toSet(),
      hiddenKeyfileUris: _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toSet(),
      l10n: context.l10n,
    );
  }

  bool get _canProceedAdvanced {
    if (!_enableHiddenVolume || !_showHiddenVolumeSection) return true;
    final validation = _hiddenVolumeValidationResult;
    return validation == null || validation.isValid;
  }

  bool _canProceedFor(_WizStep kind) => switch (kind) {
        _WizStep.type => true,
        _WizStep.basicInfo => _canProceedBasicInfo,
        _WizStep.security => _canProceedSecurity,
        _WizStep.advanced => _canProceedAdvanced,
        _WizStep.review => true,
      };

  String _stepTitle(_WizStep kind) => switch (kind) {
        _WizStep.type => context.l10n.wizardStepTypeTitle,
        _WizStep.basicInfo => context.l10n.wizardStepBasicInfoTitle,
        _WizStep.security => context.l10n.securityCredentialsSectionHeader,
        _WizStep.advanced => context.l10n.wizardStepAdvancedTitle,
        _WizStep.review => context.l10n.wizardStepReviewTitle,
      };

  Widget _stepContent(_WizStep kind, ColorScheme cs, TextTheme textTheme) => switch (kind) {
        _WizStep.type => _buildTypeStep(cs, textTheme),
        _WizStep.basicInfo => _buildBasicInfoStep(cs, textTheme),
        _WizStep.security => _buildSecurityStep(cs, textTheme),
        _WizStep.advanced => _buildAdvancedStep(cs, textTheme),
        _WizStep.review => _buildReviewStep(cs, textTheme),
      };

  void _goNext() {
    final kinds = _stepKinds;
    final safe = _currentStep.clamp(0, kinds.length - 1);
    if (safe == kinds.length - 1) {
      _create();
    } else {
      setState(() => _currentStep = safe + 1);
    }
  }

  void _goBackOrExit() {
    if (_currentStep > 0) {
      setState(() => _currentStep -= 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  // ---------------------------------------------------------------------
  // Step 0: Category/Type Selection.
  // ---------------------------------------------------------------------

  Widget _buildTypeStep(ColorScheme cs, TextTheme textTheme) {
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
                selected: !_isFolderVault,
                enabled: !_loading,
                onTap: () => _onVaultKindChanged(false),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: WizardSelectionCard(
                icon: Icons.folder_shared_rounded,
                title: l10n.vaultKindFolderVault,
                selected: _isFolderVault,
                enabled: !_loading,
                onTap: () => _onVaultKindChanged(true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          _isFolderVault ? l10n.vaultFormatLabel : l10n.containerFormatLabel,
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        _isFolderVault ? _buildFolderVaultFormatCards() : _buildContainerFormatCards(),
      ],
    );
  }

  Widget _buildContainerFormatCards() {
    return Row(
      children: [
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.veracrypt,
            title: CreateFormat.veracrypt.label,
            selected: _format == CreateFormat.veracrypt,
            enabled: !_loading,
            onTap: () => _onFormatChanged(CreateFormat.veracrypt),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.luks1,
            title: CreateFormat.luks1.label,
            selected: _format == CreateFormat.luks1,
            enabled: !_loading,
            onTap: () => _onFormatChanged(CreateFormat.luks1),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.luks2,
            title: CreateFormat.luks2.label,
            selected: _format == CreateFormat.luks2,
            enabled: !_loading,
            onTap: () => _onFormatChanged(CreateFormat.luks2),
          ),
        ),
      ],
    );
  }

  Widget _buildFolderVaultFormatCards() {
    return Row(
      children: [
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.cryptomator,
            title: 'Cryptomator',
            selected: _folderVaultFormat == 'cryptomator',
            enabled: !_loading,
            onTap: () => _onFolderVaultFormatChanged('cryptomator'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.gocryptfs,
            title: 'Gocryptfs',
            selected: _folderVaultFormat == 'gocryptfs',
            enabled: !_loading,
            onTap: () => _onFolderVaultFormatChanged('gocryptfs'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: WizardSelectionCard(
            format: ContainerFormat.cryfs,
            title: 'CryFS',
            selected: _folderVaultFormat == 'cryfs',
            enabled: !_loading,
            onTap: () => _onFolderVaultFormatChanged('cryfs'),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Step 1: Basic Configuration.
  // ---------------------------------------------------------------------

  Widget _buildBasicInfoStep(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    if (_isFolderVault) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildFolderVaultPickerCard(cs, textTheme),
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
                  value: _sizeUnit,
                  options: [
                    SelectOption(value: 'MB', label: l10n.unitMbShort),
                    SelectOption(value: 'GB', label: l10n.unitGbShort),
                  ],
                  onChanged: (val) => setState(() => _sizeUnit = val),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFolderVaultPickerCard(ColorScheme cs, TextTheme textTheme) {
    final hasSelection = _folderVaultUri != null;
    final busy = _loading || _pickingFolderVault;
    final format = ContainerFormat.fromWire(_folderVaultFormat);

    return GestureDetector(
      onTap: busy ? null : _pickFolderVaultLocation,
      child: Card(
        elevation: 0,
        color: hasSelection
            ? cs.primaryContainer.withValues(alpha: 0.15)
            : cs.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: hasSelection
                      ? cs.primaryContainer
                      : cs.surfaceContainerHighest,
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
                      hasSelection ? context.l10n.destinationFolderLabel : context.l10n.selectEmptyFolderLabel,
                      style: textTheme.labelMedium?.copyWith(
                        color: hasSelection ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _folderVaultDisplayName ?? context.l10n.tapToChooseVaultLocation,
                      style: textTheme.bodyLarge?.copyWith(
                        color: hasSelection ? cs.onSurface : cs.onSurfaceVariant,
                        fontWeight: hasSelection ? FontWeight.bold : FontWeight.normal,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (_pickingFolderVault)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (hasSelection)
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _loading
                      ? null
                      : () => setState(() {
                            _folderVaultUri = null;
                            _folderVaultDisplayName = null;
                          }),
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
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Step 2: Security & Credentials.
  // ---------------------------------------------------------------------

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
            prefixIcon: Icon(Icons.check_circle_outline_rounded,
                size: 20, color: cs.primary),
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
            prefixIcon: Icon(Icons.check_circle_outline_rounded,
                size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _folderVaultConfirmObscure,
              onToggle: () => setState(() => _folderVaultConfirmObscure = !_folderVaultConfirmObscure),
            ),
          ),
        ),
      ),
    ];
  }

  Widget _buildKeyfilesPicker() {
    return KeyfilesPicker(
      keyfiles: keyfiles,
      picking: pickingKeyfiles,
      onPick: pickKeyfiles,
      onRemove: removeKeyfile,
      enabled: !_loading,
    );
  }

  Widget _buildSecurityStep(ColorScheme cs, TextTheme textTheme) {
    return SectionCard(
      children: _isFolderVault
          ? _buildFolderVaultPasswordFields(cs)
          : [..._buildPasswordFields(cs), _buildKeyfilesPicker()],
    );
  }

  // ---------------------------------------------------------------------
  // Step 3: Advanced/Optional Features (Direct Selection, No Sub-Sheets).
  // ---------------------------------------------------------------------

  Widget _buildAdvancedStep(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;

    if (_isFolderVault) {
      if (_folderVaultFormat == 'gocryptfs') {
        return SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(1),
              child: OptionPickerTile<String>(
                label: l10n.gocryptfsCipherLabel,
                value: _gocryptfsCipher,
                prefixIcon: Icons.enhanced_encryption_rounded,
                options: const [
                  SelectOption(value: 'aes-256-gcm', label: 'AES-256-GCM'),
                  SelectOption(value: 'xchacha20-poly1305', label: 'XChaCha20-Poly1305'),
                ],
                onChanged: (val) => setState(() => _gocryptfsCipher = val),
              ),
            ),
          ],
        );
      }
      if (_folderVaultFormat == 'cryfs') {
        return SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(1),
              child: OptionPickerTile<String>(
                label: l10n.cryfsCipherLabel,
                value: _cryfsCipher,
                prefixIcon: Icons.enhanced_encryption_rounded,
                options: const [
                  SelectOption(value: 'xchacha20-poly1305', label: 'XChaCha20-Poly1305'),
                  SelectOption(value: 'aes-256-gcm', label: 'AES-256-GCM'),
                ],
                onChanged: (val) => setState(() => _cryfsCipher = val),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(1),
              child: OptionPickerTile<int>(
                label: l10n.cryfsBlockSizeLabel,
                value: _cryfsBlockSize,
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
                onChanged: (val) => setState(() => _cryfsBlockSize = val),
              ),
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionCard(
          children: [
            OptionPickerTile<int>(
              label: l10n.encryptionAlgorithmLabel,
              value: _cipherId,
              prefixIcon: Icons.security_rounded,
              options: _cipherChoices
                  .map((c) => SelectOption(value: c.id, label: c.label))
                  .toList(),
              onChanged: (val) => setState(() => _cipherId = val),
            ),
            OptionPickerTile<int>(
              label: l10n.hashAlgorithmLabel,
              value: _hashId,
              prefixIcon: Icons.tag_rounded,
              options: _hashChoices
                  .map((h) => SelectOption(value: h.id, label: h.label))
                  .toList(),
              onChanged: (val) => setState(() => _hashId = val),
            ),
            OptionPickerTile<String>(
              label: l10n.formatFileSystemLabel,
              value: _fileSystem,
              prefixIcon: Icons.dns_rounded,
              options: _availableFileSystems
                  .map((fs) => SelectOption(value: fs, label: fs))
                  .toList(),
              onChanged: (val) => setState(() => _fileSystem = val),
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
              value: _quickFormat,
              onChanged: _loading ? null : (val) => setState(() => _quickFormat = val),
            ),
          ],
        ),
        if (_showHiddenVolumeSection) ...[
          const SizedBox(height: 16),
          _buildHiddenVolumeCard(cs, textTheme),
        ],
      ],
    );
  }

  Widget _buildHiddenVolumeCard(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final bool outerReady = _passwordCtrl.text.isNotEmpty || keyfiles.isNotEmpty;
    final validation = _hiddenVolumeValidationResult;

    return SectionCard(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: outerReady && _enableHiddenVolume,
          onChanged: outerReady
              ? (val) => setState(() => _enableHiddenVolume = val)
              : null,
          title: Text(l10n.createHiddenVolumeToggleTitle,
              style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          subtitle: Text(
            outerReady
                ? l10n.createInvisibleSecondaryVolume
                : l10n.setOuterPasswordFirstToEnable,
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
          secondary: Icon(
            Icons.visibility_off_outlined,
            color: outerReady
                ? cs.primary
                : cs.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
        if (outerReady && _enableHiddenVolume) ...[
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
                    value: _hiddenSizeUnit,
                    options: [
                      SelectOption(value: 'MB', label: l10n.unitMbMegabytes),
                      SelectOption(value: 'GB', label: l10n.unitGbGigabytes),
                    ],
                    onChanged: (val) => setState(() => _hiddenSizeUnit = val),
                  ),
                ),
              ],
            ),
          ),
          KeyfilesPicker(
            keyfiles: _hiddenKeyfilesController.keyfiles,
            picking: _hiddenKeyfilesController.picking,
            onPick: _hiddenKeyfilesController.pick,
            onRemove: _hiddenKeyfilesController.remove,
            enabled: !_loading,
          ),
          OptionPickerTile<int>(
            label: l10n.encryptionAlgorithmLabel,
            value: _hiddenCipherId,
            prefixIcon: Icons.security_rounded,
            options: _cipherChoices
                .map((c) => SelectOption(value: c.id, label: c.label))
                .toList(),
            onChanged: (val) => setState(() => _hiddenCipherId = val),
          ),
          OptionPickerTile<int>(
            label: l10n.hashAlgorithmLabel,
            value: _hiddenHashId,
            prefixIcon: Icons.tag_rounded,
            options: _hashChoices
                .map((h) => SelectOption(value: h.id, label: h.label))
                .toList(),
            onChanged: (val) => setState(() => _hiddenHashId = val),
          ),
          OptionPickerTile<String>(
            label: l10n.hiddenFileSystemLabel,
            value: _hiddenFileSystem,
            prefixIcon: Icons.dns_rounded,
            options: _availableFileSystems
                .map((fs) => SelectOption(value: fs, label: fs))
                .toList(),
            onChanged: (val) => setState(() => _hiddenFileSystem = val),
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

  // ---------------------------------------------------------------------
  // Step 4: Review & Confirm.
  // ---------------------------------------------------------------------

  Widget _buildReviewStep(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final rows = <Widget>[
      WizardSummaryRow(
        icon: Icons.category_rounded,
        label: l10n.metaLabelType,
        value: _isFolderVault ? l10n.vaultKindFolderVault : l10n.vaultKindContainerFile,
      ),
    ];
    if (_isFolderVault) {
      rows.addAll([
        WizardSummaryRow(
          icon: Icons.enhanced_encryption_rounded,
          label: l10n.vaultFormatLabel,
          value: _folderVaultFormatDisplayLabel,
        ),
        WizardSummaryRow(
          icon: Icons.folder_rounded,
          label: l10n.vaultInfoLocationLabel,
          value: _folderVaultDisplayName ?? '—',
        ),
        // Cryptomator has no cipher choice of its own; gocryptfs and CryFS
        // do, so show what was picked once there's actually a choice to show.
        if (_folderVaultFormat == 'gocryptfs')
          WizardSummaryRow(
            icon: Icons.security_rounded,
            label: l10n.encryptionAlgorithmLabel,
            value: _gocryptfsCipherDisplayLabel,
          )
        else if (_folderVaultFormat == 'cryfs') ...[
          WizardSummaryRow(
            icon: Icons.security_rounded,
            label: l10n.encryptionAlgorithmLabel,
            value: _cryfsCipherDisplayLabel,
          ),
          WizardSummaryRow(
            icon: Icons.grid_view_rounded,
            label: l10n.cryfsBlockSizeLabel,
            value: _cryfsBlockSizeDisplayLabel,
          ),
        ],
      ]);
    } else {
      rows.addAll([
        WizardSummaryRow(
          icon: Icons.enhanced_encryption_rounded,
          label: l10n.containerFormatLabel,
          value: _format.label,
        ),
        WizardSummaryRow(
          icon: Icons.drive_file_rename_outline_rounded,
          label: l10n.fileNameLabel,
          value: _nameCtrl.text.isEmpty ? '—' : _nameCtrl.text,
        ),
        WizardSummaryRow(
          icon: Icons.sd_card_rounded,
          label: l10n.containerSizeLabel,
          value: '${_sizeCtrl.text} $_sizeUnit',
        ),
        WizardSummaryRow(
          icon: Icons.dns_rounded,
          label: l10n.formatFileSystemLabel,
          value: _fileSystem,
        ),
        WizardSummaryRow(
          icon: Icons.security_rounded,
          label: l10n.encryptionAlgorithmLabel,
          value: CipherAlgo.nameFor(_cipherId),
        ),
        WizardSummaryRow(
          icon: Icons.tag_rounded,
          label: l10n.hashAlgorithmLabel,
          value: HashAlgo.nameFor(_hashId),
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
          value: _quickFormat ? l10n.vaultInfoYesValue : l10n.vaultInfoNoValue,
        ),
      ]);
    }
    rows.add(WizardSummaryRow(
      icon: Icons.key_rounded,
      label: l10n.wizardSummaryPasswordLabel,
      value: (_isFolderVault ? _folderVaultPasswordCtrl : _passwordCtrl).text.isNotEmpty
          ? l10n.wizardPasswordSetValue
          : l10n.wizardPasswordNotSetValue,
    ));
    if (!_isFolderVault) {
      rows.addAll([
        WizardSummaryRow(
          icon: Icons.insert_drive_file_outlined,
          label: l10n.wizardSummaryKeyfilesLabel,
          value: keyfiles.isEmpty ? l10n.noKeyfilesAttached : '${keyfiles.length}',
        ),
        WizardSummaryRow(
          icon: Icons.visibility_off_outlined,
          label: l10n.hiddenVolumeHeader,
          value: (_showHiddenVolumeSection && _enableHiddenVolume)
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final l10n = context.l10n;
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

    final kinds = _stepKinds;
    final safeStep = _currentStep.clamp(0, kinds.length - 1);
    final currentKind = kinds[safeStep];
    final isLastStep = safeStep == kinds.length - 1;

    return Theme(
      data: Theme.of(context).copyWith(inputDecorationTheme: inputDecorationTheme),
      child: WizardScaffold(
        appBarTitle: _isFolderVault
            ? l10n.createEncryptedVaultTitle
            : l10n.createEncryptedContainerTitle,
        currentStep: safeStep,
        totalSteps: kinds.length,
        stepTitle: _stepTitle(currentKind),
        stepContent: _stepContent(currentKind, cs, textTheme),
        busy: _loading,
        busyMessage: _isFolderVault
            ? l10n.vaultCreationInProgressWait
            : l10n.containerCreationInProgressWait,
        canProceed: _canProceedFor(currentKind),
        isLastStep: isLastStep,
        nextLabel: isLastStep
            ? (_isFolderVault ? l10n.createVaultButton : l10n.createContainerButton)
            : l10n.wizardNextButton,
        onNext: _goNext,
        onBackOrExit: _goBackOrExit,
        errorMessage: _error,
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Quick Password Generator Modal Sheet
// -----------------------------------------------------------------------------

class _QuickPasswordGeneratorSheet extends StatefulWidget {
  const _QuickPasswordGeneratorSheet();

  @override
  State<_QuickPasswordGeneratorSheet> createState() => _QuickPasswordGeneratorSheetState();
}

class _QuickPasswordGeneratorSheetState extends State<_QuickPasswordGeneratorSheet> {
  String _preset = 'dice5';
  String _generated = '';

  @override
  void initState() {
    super.initState();
    _regenerate();
  }

  Future<void> _regenerate() async {
    String pwd = '';
    if (_preset == 'dice5') {
      final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
        wordCount: 5,
        separator: '-',
        casing: PasswordCasing.lowercase,
        includeNumber: true,
      );
      pwd = res.passphrase;
    } else if (_preset == 'dice6') {
      final res = await KeyfilePassphraseGeneratorService.generateDicewarePassphrase(
        wordCount: 6,
        separator: '-',
        casing: PasswordCasing.lowercase,
        includeNumber: true,
      );
      pwd = res.passphrase;
    } else if (_preset == 'char24') {
      final res = KeyfilePassphraseGeneratorService.generateCustomPassword(
        length: 24,
        useUppercase: true,
        useLowercase: true,
        useNumbers: true,
        useSymbols: true,
      );
      pwd = res.password;
    } else {
      final res = KeyfilePassphraseGeneratorService.generateCustomPassword(
        length: 32,
        useUppercase: true,
        useLowercase: true,
        useNumbers: true,
        useSymbols: true,
      );
      pwd = res.password;
    }
    if (mounted) setState(() => _generated = pwd);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.password_rounded, size: 22, color: cs.primary),
              const SizedBox(width: 10),
              Text(
                'Password Generator',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Generate new',
                onPressed: _regenerate,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: SelectableText(
              _generated,
              style: textTheme.titleMedium?.copyWith(
                fontFamily: 'monospace',
                fontWeight: FontWeight.bold,
                color: cs.primary,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildPresetChip('dice5', '5 Words (Diceware)'),
                const SizedBox(width: 8),
                _buildPresetChip('dice6', '6 Words (Diceware)'),
                const SizedBox(width: 8),
                _buildPresetChip('char24', '24 Chars (Alphanumeric)'),
                const SizedBox(width: 8),
                _buildPresetChip('char32', '32 Chars (Complex)'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Use This Password'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            onPressed: _generated.isEmpty ? null : () => Navigator.of(context).pop(_generated),
          ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(String key, String label) {
    final selected = _preset == key;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      showCheckmark: false,
      onSelected: (sel) {
        if (sel) {
          setState(() => _preset = key);
          _regenerate();
        }
      },
    );
  }
}