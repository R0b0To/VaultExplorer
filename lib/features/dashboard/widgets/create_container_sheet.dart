import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'container_format_selector.dart';

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

  List<DropdownMenuItem<int>> get _cipherItems => _cipherChoices
      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.label)))
      .toList();

  List<DropdownMenuItem<int>> get _hashItems => _hashChoices
      .map((h) => DropdownMenuItem(value: h.id, child: Text(h.label)))
      .toList();

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
      setState(() => _error = e.message ?? context.l10n.unknownErrorOccurred);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildVaultKindSelector() {
    return SegmentedButton<bool>(
      segments: [
        ButtonSegment(
          value: false,
          label: Text(context.l10n.vaultKindContainerFile),
          icon: const Icon(Icons.folder_zip_rounded),
        ),
        ButtonSegment(
          value: true,
          label: Text(context.l10n.vaultKindFolderVault),
          icon: const Icon(Icons.folder_shared_rounded),
        ),
      ],
      selected: {_isFolderVault},
      onSelectionChanged: _loading
          ? null
          : (sel) => _onVaultKindChanged(sel.first),
    );
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

  Widget _buildAdvancedTile(BuildContext context) {
    return AdvancedParamsPanel(
      pimController: _pimCtrl,
      cipherId: _cipherId,
      hashId: _hashId,
      includeAuto: false,
      cipherItems: _cipherItems,
      hashItems: _hashItems,
      onCipherChanged: (val) => setState(() => _cipherId = val),
      onHashChanged: (val) => setState(() => _hashId = val),
      extraFields: [
        OptionPickerTile<String>(
          label: context.l10n.formatFileSystemLabel,
          value: _fileSystem,
          prefixIcon: Icons.dns_rounded,
          options: _availableFileSystems
              .map((fs) => SelectOption(value: fs, label: fs))
              .toList(),
          onChanged: (val) => setState(() => _fileSystem = val),
        ),
      ],
    );
  }

  Widget _buildMainVolumeSection(ColorScheme cs, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.standardVolumeHeader),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.containerFormatLabel,
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  ContainerFormatSelector(
                    selected: _format,
                    busy: _loading,
                    onChanged: _onFormatChanged,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: context.l10n.fileNameLabel,
                  prefixIcon: const Icon(Icons.drive_file_rename_outline_rounded,
                      size: 20),
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
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                        labelText: context.l10n.containerSizeLabel,
                        prefixIcon: const Icon(Icons.sd_card_outlined, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OptionPickerTile<String>(
                      label: context.l10n.unitLabel,
                      value: _sizeUnit,
                      options: [
                        SelectOption(value: 'MB', label: context.l10n.unitMbShort),
                        SelectOption(value: 'GB', label: context.l10n.unitGbShort),
                      ],
                      onChanged: (val) => setState(() => _sizeUnit = val),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: context.l10n.passwordFieldLabel,
                  prefixIcon:
                      Icon(Icons.key_rounded, size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _confirmPasswordCtrl,
                obscureText: _confirmObscure,
                onChanged: (_) => setState(() {}),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: context.l10n.confirmPasswordFieldLabelTitleCase,
                  prefixIcon: Icon(Icons.check_circle_outline_rounded,
                      size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _confirmObscure,
                    onToggle: () =>
                        setState(() => _confirmObscure = !_confirmObscure),
                  ),
                ),
              ),
            ),
            _buildKeyfilesPicker(),
            _buildAdvancedTile(context),
          ],
        ),
      ],
    );
  }

  Widget _buildHiddenVolumeSection(ColorScheme cs, TextTheme textTheme) {
    final bool isEnabled =
        _passwordCtrl.text.isNotEmpty || keyfiles.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.hiddenVolumeHeader),
        SectionCard(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: isEnabled && _enableHiddenVolume,
              onChanged: isEnabled
                  ? (val) => setState(() => _enableHiddenVolume = val)
                  : null,
              title: Text(context.l10n.createHiddenVolumeToggleTitle,
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(
                isEnabled
                    ? context.l10n.createInvisibleSecondaryVolume
                    : context.l10n.setOuterPasswordFirstToEnable,
                style: textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              secondary: Icon(
                Icons.visibility_off_outlined,
                color: isEnabled
                    ? cs.primary
                    : cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
            if (isEnabled && _enableHiddenVolume) ...[
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _hiddenPasswordCtrl,
                  obscureText: _hiddenObscure,
                  onChanged: (_) => setState(() {}),
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: context.l10n.hiddenPasswordLabel,
                    prefixIcon:
                        Icon(Icons.key_rounded, size: 20, color: cs.primary),
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _hiddenObscure,
                      onToggle: () =>
                          setState(() => _hiddenObscure = !_hiddenObscure),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _hiddenConfirmPasswordCtrl,
                  obscureText: _hiddenConfirmObscure,
                  onChanged: (_) => setState(() {}),
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: context.l10n.confirmHiddenPasswordLabel,
                    prefixIcon: Icon(Icons.check_circle_outline_rounded,
                        size: 20, color: cs.primary),
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _hiddenConfirmObscure,
                      onToggle: () => setState(
                          () => _hiddenConfirmObscure = !_hiddenConfirmObscure),
                    ),
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
                        controller: _hiddenSizeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: context.l10n.hiddenSizeLabel,
                          prefixIcon: const Icon(Icons.sd_card_outlined, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OptionPickerTile<String>(
                        label: context.l10n.unitLabel,
                        value: _hiddenSizeUnit,
                        options: [
                          SelectOption(value: 'MB', label: context.l10n.unitMbMegabytes),
                          SelectOption(value: 'GB', label: context.l10n.unitGbGigabytes),
                        ],
                        onChanged: (val) =>
                            setState(() => _hiddenSizeUnit = val),
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
              AdvancedParamsPanel(
                pimController: _hiddenPimCtrl,
                cipherId: _hiddenCipherId,
                hashId: _hiddenHashId,
                includeAuto: false,
                cipherItems: _cipherItems,
                hashItems: _hashItems,
                onCipherChanged: (val) => setState(() => _hiddenCipherId = val),
                onHashChanged: (val) => setState(() => _hiddenHashId = val),
                extraFields: [
                  OptionPickerTile<String>(
                    label: context.l10n.hiddenFileSystemLabel,
                    value: _hiddenFileSystem,
                    prefixIcon: Icons.dns_rounded,
                    options: _availableFileSystems
                        .map((fs) => SelectOption(value: fs, label: fs))
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _hiddenFileSystem = val),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildFolderVaultFormatSelector() {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'cryptomator',
          label: Text('Cryptomator'),
          icon: Icon(Icons.folder_shared_rounded),
        ),
        ButtonSegment(
          value: 'gocryptfs',
          label: Text('Gocryptfs'),
          icon: Icon(Icons.enhanced_encryption_rounded),
        ),
        ButtonSegment(
          value: 'cryfs',
          label: Text('CryFS'),
          icon: Icon(Icons.enhanced_encryption_rounded),
        ),
      ],
      selected: {_folderVaultFormat},
      onSelectionChanged: _loading
          ? null
          : (sel) => _onFolderVaultFormatChanged(sel.first),
    );
  }

  Widget _buildFolderVaultPickerCard(ColorScheme cs, TextTheme textTheme) {
    final hasSelection = _folderVaultUri != null;
    final busy = _loading || _pickingFolderVault;
    return GestureDetector(
      onTap: busy ? null : _pickFolderVaultLocation,
      child: Card(
        elevation: 0,
        color: hasSelection
            ? cs.primaryContainer.withValues(alpha: 0.15)
            : cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: hasSelection
                ? cs.primary
                : cs.outlineVariant.withValues(alpha: 0.35),
            width: hasSelection ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: hasSelection
                      ? cs.primaryContainer
                      : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _folderVaultFormat == 'gocryptfs' ||
                          _folderVaultFormat == 'cryfs'
                      ? Icons.folder_zip
                      : Icons.folder_zip,
                  size: 26,
                  color: hasSelection
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
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
                      _folderVaultDisplayName ??
                          context.l10n.tapToChooseVaultLocation,
                      style: textTheme.bodyLarge?.copyWith(
                        color:
                            hasSelection ? cs.onSurface : cs.onSurfaceVariant,
                        fontWeight:
                            hasSelection ? FontWeight.bold : FontWeight.normal,
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

  Widget _buildFolderVaultSection(ColorScheme cs, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.vaultKindFolderVault),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.vaultFormatLabel,
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildFolderVaultFormatSelector(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: _buildFolderVaultPickerCard(cs, textTheme),
            ),
            if (_folderVaultFormat == 'gocryptfs')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OptionPickerTile<String>(
                      label: context.l10n.gocryptfsCipherLabel,
                      value: _gocryptfsCipher,
                      prefixIcon: Icons.enhanced_encryption_rounded,
                      options: const [
                        SelectOption(
                          value: 'aes-256-gcm',
                          label: 'AES-256-GCM',
                        ),
                        SelectOption(
                          value: 'xchacha20-poly1305',
                          label: 'XChaCha20-Poly1305',
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _gocryptfsCipher = val),
                    ),
                  ],
                ),
              ),
            if (_folderVaultFormat == 'cryfs')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OptionPickerTile<String>(
                      label: context.l10n.cryfsCipherLabel,
                      value: _cryfsCipher,
                      prefixIcon: Icons.enhanced_encryption_rounded,
                      options: const [
                        SelectOption(
                          value: 'xchacha20-poly1305',
                          label: 'XChaCha20-Poly1305',
                        ),
                        SelectOption(
                          value: 'aes-256-gcm',
                          label: 'AES-256-GCM',
                        ),
                      ],
                      onChanged: (val) =>
                          setState(() => _cryfsCipher = val),
                    ),
                    const SizedBox(height: 8),
                    OptionPickerTile<int>(
                      label: context.l10n.cryfsBlockSizeLabel,
                      value: _cryfsBlockSize,
                      prefixIcon: Icons.grid_view_rounded,
                      options: const [
                        SelectOption(value: 4 * 1024, label: '4 KiB'),
                        SelectOption(value: 8 * 1024, label: '8 KiB'),
                        SelectOption(value: 16 * 1024, label: '16 KiB'),
                        SelectOption(
                            value: 32 * 1024, label: '32 KiB (default)'),
                        SelectOption(value: 64 * 1024, label: '64 KiB'),
                        SelectOption(value: 128 * 1024, label: '128 KiB'),
                        SelectOption(value: 512 * 1024, label: '512 KiB'),
                        SelectOption(value: 1024 * 1024, label: '1 MiB'),
                        SelectOption(value: 4 * 1024 * 1024, label: '4 MiB'),
                      ],
                      onChanged: (val) =>
                          setState(() => _cryfsBlockSize = val),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _folderVaultPasswordCtrl,
                obscureText: _folderVaultObscure,
                onChanged: (_) => setState(() {}),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: context.l10n.passwordFieldLabel,
                  prefixIcon:
                      Icon(Icons.key_rounded, size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _folderVaultObscure,
                    onToggle: () => setState(
                        () => _folderVaultObscure = !_folderVaultObscure),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _folderVaultConfirmCtrl,
                obscureText: _folderVaultConfirmObscure,
                onChanged: (_) => setState(() {}),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: context.l10n.confirmPasswordFieldLabelTitleCase,
                  prefixIcon: Icon(Icons.check_circle_outline_rounded,
                      size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _folderVaultConfirmObscure,
                    onToggle: () => setState(() => _folderVaultConfirmObscure =
                        !_folderVaultConfirmObscure),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.folderVaultLimitationsNote,
                      style: textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
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
    final errorAndSubmit = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null) ...[
          InlineErrorBanner(_error!),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: _loading ? null : _create,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: const StadiumBorder(),
          ),
          child: _loading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                  ),
                )
              : Text(
                  _isFolderVault ? context.l10n.createVaultButton : context.l10n.createContainerButton,
                  style:
                      const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
      ],
    );
    final primarySection = _isFolderVault
        ? _buildFolderVaultSection(cs, textTheme)
        : _buildMainVolumeSection(cs, textTheme);
    final showHiddenVolumeSection =
        !_isFolderVault && _format == CreateFormat.veracrypt;
    return PopScope(
      canPop: !_loading,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _loading) {
          showAppSnackBar(
            context,
            message: _isFolderVault
                ? context.l10n.vaultCreationInProgressWait
                : context.l10n.containerCreationInProgressWait,
            tone: AppBannerTone.warning,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _isFolderVault
                ? context.l10n.createEncryptedVaultTitle
                : context.l10n.createEncryptedContainerTitle,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: _loading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearProgressIndicator(
                    color: cs.primary,
                    backgroundColor: cs.primaryContainer,
                  ),
                )
              : null,
        ),
        body: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: inputDecorationTheme,
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildVaultKindSelector(),
                    const SizedBox(height: 12),
                    isLandscape
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: primarySection,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showHiddenVolumeSection) ...[
                                      _buildHiddenVolumeSection(
                                          cs, textTheme),
                                      const SizedBox(height: 16),
                                    ],
                                    errorAndSubmit,
                                  ],
                                ),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              primarySection,
                              const SizedBox(height: 16),
                              if (showHiddenVolumeSection) ...[
                                _buildHiddenVolumeSection(cs, textTheme),
                                const SizedBox(height: 16),
                              ],
                              errorAndSubmit,
                            ],
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}