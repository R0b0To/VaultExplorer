import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/sensitive_clipboard.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_scaffold.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_selection_card.dart';
import 'package:vaultexplorer/core/widgets/wizard/wizard_summary_row.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/features/tools/services/keyfile_passphrase_generator_service.dart';

enum _WizStep { type, basicInfo, security, advanced, review }

class UsbCreateContainerSheet extends StatefulWidget {
  const UsbCreateContainerSheet({super.key});
  @override
  State<UsbCreateContainerSheet> createState() =>
      _UsbCreateContainerSheetState();
}

class _UsbCreateContainerSheetState extends State<UsbCreateContainerSheet>
    with KeyfilePickerMixin {
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
  final _sizeCtrl = TextEditingController(text: '1024');
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();
  List<UsbDeviceInfo> _devices = [];
  UsbDeviceInfo? _selected;
  bool _loadingDevices = true;
  bool _requestingPermission = false;
  bool _obscure = true;
  bool _confirmObscure = true;
  bool _creating = false;
  String? _error;
  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);
  String _sizeUnit = 'MB';
  String _fileSystem = 'exFAT';
  int _cipherId = 0;
  int _hashId = 0;
  bool _quickFormat = true;
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
  int? _usableCapacityBytes;
  bool _fetchingCapacity = false;
  CreateFormat _format = CreateFormat.veracrypt;

  int _currentStep = 0;

  List<String> get _availableFileSystems => _format == CreateFormat.veracrypt
      ? _veraCryptFileSystems
      : _luksFileSystems;

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

  void _onFormatChanged(CreateFormat format) {
    setState(() {
      _format = format;
      if (format == CreateFormat.luks1 || format == CreateFormat.luks2) {
        _fileSystem = 'ext4';
      } else {
        _fileSystem = 'exFAT';
      }
      if (!_cipherChoices.any((c) => c.id == _cipherId)) {
        _cipherId = _cipherChoices.first.id;
      }
      if (!_hashChoices.any((h) => h.id == _hashId)) {
        _hashId = _hashChoices.first.id;
      }
      if (format != CreateFormat.veracrypt) {
        _enableHiddenVolume = false;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

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

  Future<void> _loadDevices() async {
    setState(() => _loadingDevices = true);
    try {
      final devices = await vaultExplorerApi.listUsbDevices();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _loadingDevices = false;
      });
      if (devices.length == 1) {
        await _selectDevice(devices.first);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingDevices = false;
          _error = context.l10n.failedToListUsbDevices('$e');
        });
      }
    }
  }

  Future<void> _ensurePermission(UsbDeviceInfo device) async {
    if (device.hasPermission) return;
    setState(() => _requestingPermission = true);
    final granted =
        await vaultExplorerApi.requestUsbPermission(device.deviceName);
    if (mounted) {
      setState(() {
        _requestingPermission = false;
        if (!granted) _error = context.l10n.usbPermissionDenied;
      });
    }
    if (granted) await _loadDevices();
  }

  Future<void> _selectDevice(UsbDeviceInfo device) async {
    setState(() => _selected = device);
    if (!device.hasPermission) {
      await _ensurePermission(device);
    }
    final refreshed = _devices.firstWhere(
      (d) => d.deviceName == device.deviceName,
      orElse: () => device,
    );
    if (!refreshed.hasPermission || !mounted) return;
    setState(() => _fetchingCapacity = true);
    final usable =
        await vaultExplorerApi.getUsbDeviceCapacity(device.deviceName);
    if (!mounted) return;
    setState(() {
      _fetchingCapacity = false;
      _usableCapacityBytes = usable;
      if (usable != null && usable > 0) {
        if (usable >= 1024 * 1024 * 1024) {
          _sizeUnit = 'GB';
          _sizeCtrl.text = (usable / (1024 * 1024 * 1024)).toStringAsFixed(2);
        } else {
          _sizeUnit = 'MB';
          _sizeCtrl.text = (usable / (1024 * 1024)).floor().toString();
        }
      } else {
        _error = context.l10n.couldNotReadDriveCapacity;
      }
    });
  }

  Future<void> _create() async {
    final device = _selected;
    if (device == null) {
      setState(() => _error = context.l10n.selectUsbDriveFirst);
      return;
    }
    final sizeVal = double.tryParse(_sizeCtrl.text);
    if (sizeVal == null || sizeVal <= 0) {
      setState(() => _error = context.l10n.enterValidSizeGreaterThanZero);
      return;
    }
    if (_passwordCtrl.text.isEmpty && keyfiles.isEmpty) {
      setState(
          () => _error = context.l10n.passwordOrKeyfileRequired);
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
    final confirmed = await showAppConfirmDialog(
      context,
      title: context.l10n.eraseDeviceTitle(device.productName),
      message: context.l10n.eraseDeviceMessage,
      confirmLabel: context.l10n.eraseAndCreateButton,
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      if (!device.hasPermission) {
        await _ensurePermission(device);
        final refreshed = _devices.firstWhere(
          (d) => d.deviceName == device.deviceName,
          orElse: () => device,
        );
        if (!refreshed.hasPermission) {
          setState(() => _error = context.l10n.usbPermissionRequiredToContinue);
          return;
        }
      }
      final multiplier = _sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
      final sizeBytes = (sizeVal * multiplier).round();
      final pim = clampPim(
        _pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0,
      );
      int hiddenSizeBytes = 0;
      if (_enableHiddenVolume && _format == CreateFormat.veracrypt) {
        final hiddenPimClamped = clampPim(
          _hiddenPimCtrl.text.isEmpty
              ? 0
              : int.tryParse(_hiddenPimCtrl.text) ?? 0,
        );
        final validation = validateHiddenVolume(
          hiddenSizeText: _hiddenSizeCtrl.text,
          hiddenSizeUnit: _hiddenSizeUnit,
          outerSizeBytes: sizeBytes,
          outerPimClamped: pim,
          hiddenPimClamped: hiddenPimClamped,
          outerPassword: _passwordCtrl.text,
          hiddenPassword: _hiddenPasswordCtrl.text,
          hasHiddenKeyfiles: _hiddenKeyfilesController.keyfiles.isNotEmpty,
          outerKeyfileUris: keyfiles.map((k) => k.uri).toSet(),
          hiddenKeyfileUris:
              _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toSet(),
          l10n: context.l10n,
        );
        if (!validation.isValid) {
          setState(() => _error = validation.error);
          return;
        }
        hiddenSizeBytes = validation.hiddenSizeBytes!;
      }
      final success = await vaultExplorerApi.createUsbContainer(
        deviceName: device.deviceName,
        sizeBytes: sizeBytes,
        password: _passwordCtrl.text,
        pim: pim,
        fileSystem: _fileSystem.toLowerCase(),
        containerFormat: _format.id,
        cipherId: _cipherId,
        hashId: _hashId,
        keyfilePaths: keyfiles.map((k) => k.uri).toList(),
        quickFormat: _quickFormat,
        createHiddenVolume:
            _enableHiddenVolume && _format == CreateFormat.veracrypt,
        hiddenPassword: _hiddenPasswordCtrl.text,
        hiddenFileSystem: _hiddenFileSystem.toLowerCase(),
        hiddenSizeBytes: hiddenSizeBytes,
        hiddenKeyfilePaths:
            _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toList(),
        hiddenPim: (_enableHiddenVolume && _format == CreateFormat.veracrypt)
            ? clampPim(
                _hiddenPimCtrl.text.isEmpty
                    ? 0
                    : int.tryParse(_hiddenPimCtrl.text) ?? 0,
              )
            : 0,
        hiddenCipherId:
            (_enableHiddenVolume && _format == CreateFormat.veracrypt)
                ? _hiddenCipherId
                : 255,
        hiddenHashId: (_enableHiddenVolume && _format == CreateFormat.veracrypt)
            ? _hiddenHashId
            : 255,
      );
      if (!mounted) return;
      if (success) {
        Navigator.pop(context);
        showAppSnackBar(
          context,
          message: context.l10n.usbContainerCreatedSnack,
          tone: AppBannerTone.success,
        );
      } else {
        setState(() => _error = context.l10n.usbContainerCreationFailed);
      }
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? context.l10n.unknownErrorOccurred);
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  // ---------------------------------------------------------------------
  // Password Generator Integration (Directly fills & un-obscures fields)
  // ---------------------------------------------------------------------

  Future<void> _openPasswordGenerator() async {
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
        _passwordCtrl.text = password;
        _confirmPasswordCtrl.text = password;
        _obscure = false;
        _confirmObscure = false;
      });
      await SensitiveClipboard.copy(password);
    }
  }

  // ---------------------------------------------------------------------
  // Wizard Navigation & Validity
  // ---------------------------------------------------------------------

  bool get _busy => _creating || _requestingPermission;
  bool get _showHiddenVolumeSection => _format == CreateFormat.veracrypt;

  List<_WizStep> get _stepKinds => const [
        _WizStep.type,
        _WizStep.basicInfo,
        _WizStep.security,
        _WizStep.advanced,
        _WizStep.review,
      ];

  bool get _canProceedBasicInfo =>
      _selected != null && (double.tryParse(_sizeCtrl.text) ?? 0) > 0;

  bool get _canProceedSecurity =>
      (_passwordCtrl.text.isNotEmpty || keyfiles.isNotEmpty) &&
      (_passwordCtrl.text.isEmpty ||
          _passwordCtrl.text == _confirmPasswordCtrl.text);

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
  // Step 0: Format Selection.
  // ---------------------------------------------------------------------

  Widget _buildTypeStep(ColorScheme cs, TextTheme textTheme) {
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
                selected: _format == CreateFormat.veracrypt,
                enabled: !_busy,
                onTap: () => _onFormatChanged(CreateFormat.veracrypt),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WizardSelectionCard(
                format: ContainerFormat.luks1,
                title: CreateFormat.luks1.label,
                selected: _format == CreateFormat.luks1,
                enabled: !_busy,
                onTap: () => _onFormatChanged(CreateFormat.luks1),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: WizardSelectionCard(
                format: ContainerFormat.luks2,
                title: CreateFormat.luks2.label,
                selected: _format == CreateFormat.luks2,
                enabled: !_busy,
                onTap: () => _onFormatChanged(CreateFormat.luks2),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Step 1: Basic Configuration (drive selection + size).
  // ---------------------------------------------------------------------

  Widget _buildBasicInfoStep(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final busy = _busy;
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
              if (_loadingDevices)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                )
              else if (_devices.isEmpty)
                Card(
                  elevation: 0,
                  color: cs.surfaceContainerHigh,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                        color: cs.outlineVariant.withValues(alpha: 0.3)),
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
                          child: Icon(Icons.usb_off_rounded,
                              size: 32, color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.noUsbStorageDetected,
                          style: textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.connectOtgDriveToFormat,
                          style: textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: busy ? null : _loadDevices,
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
                  groupValue: _selected,
                  onChanged: (v) {
                    if (!busy && v != null) _selectDevice(v);
                  },
                  child: Column(
                    children: _devices.map((d) {
                      final isSelected =
                          _selected?.deviceName == d.deviceName;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          onTap: busy ? null : () => _selectDevice(d),
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
                                    : cs.outlineVariant
                                        .withValues(alpha: 0.3),
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
                                      borderRadius:
                                          BorderRadius.circular(14),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          d.productName,
                                          style: textTheme.bodyLarge
                                              ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          d.hasPermission
                                              ? l10n.readyToFormat
                                              : l10n.permissionRequired,
                                          style: textTheme.bodySmall
                                              ?.copyWith(
                                            color: d.hasPermission
                                                ? cs.primary
                                                : cs.onSurfaceVariant,
                                            fontWeight: d.hasPermission
                                                ? FontWeight.w500
                                                : null,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Radio<UsbDeviceInfo>(
                                    value: d,
                                    activeColor: cs.primary,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
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
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
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
                        SelectOption(value: 'MB', label: l10n.unitMbMegabytes),
                        SelectOption(value: 'GB', label: l10n.unitGbGigabytes),
                      ],
                      onChanged: busy ? (v) {} : (v) => setState(() => _sizeUnit = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _fetchingCapacity
                      ? l10n.readingDriveCapacity
                      : _usableCapacityBytes != null
                          ? l10n.driveUsableCapacity((_usableCapacityBytes! / (1024 * 1024)).floor())
                          : l10n.mustNotExceedDriveCapacity,
                  style: textTheme.bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Step 2: Security & Credentials.
  // ---------------------------------------------------------------------

  Widget _buildSecurityStep(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final busy = _busy;
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
              prefixIcon: Icon(Icons.check_circle_outline_rounded,
                  size: 20, color: cs.primary),
              suffixIcon: PasswordVisibilityToggle(
                obscured: _confirmObscure,
                onToggle: () => setState(() => _confirmObscure = !_confirmObscure),
              ),
            ),
          ),
        ),
        KeyfilesPicker(
          keyfiles: keyfiles,
          picking: pickingKeyfiles,
          onPick: pickKeyfiles,
          onRemove: removeKeyfile,
          enabled: !busy,
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // Step 3: Advanced/Optional Features (Direct Selection, No Sub-Sheets).
  // ---------------------------------------------------------------------

  Widget _buildAdvancedStep(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final busy = _busy;

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
              value: _quickFormat,
              onChanged: busy ? null : (val) => setState(() => _quickFormat = val),
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
    final busy = _busy;
    final bool outerReady = _passwordCtrl.text.isNotEmpty || keyfiles.isNotEmpty;
    final validation = _hiddenVolumeValidationResult;

    return SectionCard(
      children: [
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          value: outerReady && _enableHiddenVolume,
          onChanged: (outerReady && !busy)
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
                prefixIcon: Icon(Icons.check_circle_outline_rounded,
                    size: 20, color: cs.primary),
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
                    value: _hiddenSizeUnit,
                    options: [
                      SelectOption(value: 'MB', label: l10n.unitMbMegabytes),
                      SelectOption(value: 'GB', label: l10n.unitGbGigabytes),
                    ],
                    onChanged: busy ? (val) {} : (val) => setState(() => _hiddenSizeUnit = val),
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
            enabled: !busy,
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
            options: _veraCryptFileSystems
                .map((fs) => SelectOption(value: fs, label: fs))
                .toList(),
            onChanged: busy ? (val) {} : (val) => setState(() => _hiddenFileSystem = val),
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

  // ---------------------------------------------------------------------
  // Step 4: Review & Confirm.
  // ---------------------------------------------------------------------

  Widget _buildReviewStep(ColorScheme cs, TextTheme textTheme) {
    final l10n = context.l10n;
    final rows = <Widget>[
      WizardSummaryRow(
        icon: Icons.enhanced_encryption_rounded,
        label: l10n.containerFormatLabel,
        value: _format.label,
      ),
      WizardSummaryRow(
        icon: Icons.usb_rounded,
        label: l10n.wizardSummaryDriveLabel,
        value: _selected?.productName ?? '—',
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
        value: keyfiles.isEmpty ? l10n.noKeyfilesAttached : '${keyfiles.length}',
      ),
      WizardSummaryRow(
        icon: Icons.visibility_off_outlined,
        label: l10n.hiddenVolumeHeader,
        value: (_showHiddenVolumeSection && _enableHiddenVolume)
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
        appBarTitle: l10n.formatUsbDriveScreenTitle,
        currentStep: safeStep,
        totalSteps: kinds.length,
        stepTitle: _stepTitle(currentKind),
        stepContent: _stepContent(currentKind, cs, textTheme),
        busy: _busy,
        busyMessage: l10n.usbContainerCreationInProgressWait,
        canProceed: _canProceedFor(currentKind),
        isLastStep: isLastStep,
        nextLabel: isLastStep ? l10n.eraseAndCreateContainerButton : l10n.wizardNextButton,
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