import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

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
  static const _luksFileSystems = ['ext2', 'ext3', 'ext4'];

  String _sizeUnit = 'MB';
  CreateFormat _format = CreateFormat.veracrypt;
  String _fileSystem = 'FAT';
  int _cipherId = 0; // AES
  int _hashId = 0; // SHA-512
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
    onError: (msg) { if (mounted) setState(() => _error = msg); },
  );
  String _hiddenFileSystem = 'FAT';
  int _hiddenCipherId = 0; // AES
  int _hiddenHashId = 0; // SHA-512

  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);

  // ── Folder vault (Cryptomator / Gocryptfs) state ──────────────────────────
  bool _isFolderVault = false;

  String _folderVaultFormat = 'cryptomator';
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
      _fileSystem = _format == CreateFormat.veracrypt ? 'FAT' : 'ext4';
      
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
      if (mounted) setState(() => _error = 'Folder picker failed: $e');
    } finally {
      if (mounted) setState(() => _pickingFolderVault = false);
    }
  }


  // ── Top-level dispatch ─────────────────────────────────────────────────────

  Future<void> _create() {
    return _isFolderVault ? _createFolderVault() : _createContainerFile();
  }

  Future<void> _createFolderVault() async {
    if (_folderVaultUri == null) {
      setState(() => _error = 'Select an empty destination folder first');
      return;
    }
    final password = _folderVaultPasswordCtrl.text;
    if (password.isEmpty) {
      setState(() => _error = 'A password is required');
      return;
    }
    if (password != _folderVaultConfirmCtrl.text) {
      setState(() => _error = 'Passwords do not match');
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
              ? await vaultExplorerApi.createGocryptfsVault(_folderVaultUri!, password)
              : await vaultExplorerApi.createCryfsVault(_folderVaultUri!, password);

      if (success) {
        if (mounted) {
          Navigator.pop(context);
          showAppSnackBar(
            context,
            message: 'Vault created successfully.',
            tone: AppBannerTone.success,
          );
        }
      } else {
        setState(() => _error =
            'Vault creation failed — make sure the selected folder is empty.');
      }
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? 'Unknown error occurred');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createContainerFile() async {
    if (_nameCtrl.text.isEmpty) {
      setState(() => _error = 'Container name is required');
      return;
    }
    final sizeVal = double.tryParse(_sizeCtrl.text);
    if (sizeVal == null || sizeVal <= 0) {
      setState(() => _error = 'Enter a valid size greater than 0');
      return;
    }
    if (_passwordCtrl.text.isEmpty && keyfiles.isEmpty) {
      setState(() => _error = 'A password or at least one keyfile is required');
      return;
    }
    if (_passwordCtrl.text.isNotEmpty &&
        _passwordCtrl.text != _confirmPasswordCtrl.text) {
      setState(() => _error = 'Standard volume passwords do not match');
      return;
    }

    if (_enableHiddenVolume && _format == CreateFormat.veracrypt) {
      if (_hiddenPasswordCtrl.text.isNotEmpty &&
          _hiddenPasswordCtrl.text != _hiddenConfirmPasswordCtrl.text) {
        setState(() => _error = 'Hidden volume passwords do not match');
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
            message: 'Container file created successfully.',
            tone: AppBannerTone.success,
          );
        }
      } else {
        setState(() => _error = 'Container creation cancelled or failed.');
      }
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? 'Unknown error occurred');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Vault-kind selector (Container File vs Folder Vault) ──────────────────

  Widget _buildVaultKindSelector() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
          value: false,
          label: Text('Container File'),
          icon: Icon(Icons.folder_zip_rounded),
        ),
        ButtonSegment(
          value: true,
          label: Text('Folder Vault'),
          icon: Icon(Icons.folder_shared_rounded),
        ),
      ],
      selected: {_isFolderVault},
      onSelectionChanged: _loading
          ? null
          : (sel) => _onVaultKindChanged(sel.first),
    );
  }

  Widget _buildFormatSelector() {
    return SegmentedButton<CreateFormat>(
      segments: const [
        ButtonSegment(
          value: CreateFormat.veracrypt,
          label: Text('VeraCrypt'),
          icon: Icon(Icons.lock_rounded),
        ),
        ButtonSegment(
          value: CreateFormat.luks1,
          label: Text('LUKS1'),
          icon: Icon(Icons.security_rounded),
        ),
        ButtonSegment(
          value: CreateFormat.luks2,
          label: Text('LUKS2'),
          icon: Icon(Icons.shield_rounded),
        ),
      ],
      selected: {_format},
      onSelectionChanged: _loading
          ? null
          : (sel) => _onFormatChanged(sel.first),
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
          label: 'Format File System',
          value: _fileSystem,
          prefixIcon: Icons.dns_rounded,
          subtitle: 'File system: $_fileSystem',
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
        SectionHeader('Standard Volume'),
        SectionCard(
          children: [
            // Format Selector
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Container Format',
                    style: textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  _buildFormatSelector(),
                ],
              ),
            ),

            // File Name Field
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'File Name',
                  prefixIcon: Icon(Icons.drive_file_rename_outline_rounded,
                      size: 20),
                ),
              ),
            ),

            // Container Size & Unit Row
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
                      decoration: const InputDecoration(
                        labelText: 'Container Size',
                        prefixIcon: Icon(Icons.sd_card_outlined, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OptionPickerTile<String>(
                      label: 'Unit',
                      value: _sizeUnit,
                      options: const [
                        SelectOption(value: 'MB', label: 'MB'),
                        SelectOption(value: 'GB', label: 'GB'),
                      ],
                      onChanged: (val) => setState(() => _sizeUnit = val),
                    ),
                  ),
                ],
              ),
            ),

            // Password Field
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _passwordCtrl,
                obscureText: _obscure,
                onChanged: (_) => setState(() {}),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon:
                      Icon(Icons.key_rounded, size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _obscure,
                    onToggle: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ),

            // Confirm Password Field
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _confirmPasswordCtrl,
                obscureText: _confirmObscure,
                onChanged: (_) => setState(() {}),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Confirm Password',
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

            // Keyfiles Picker
            _buildKeyfilesPicker(),

            // Advanced Parameters Panel
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
        SectionHeader('Hidden Volume'),
        SectionCard(
          children: [
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: isEnabled && _enableHiddenVolume,
              onChanged: isEnabled
                  ? (val) => setState(() => _enableHiddenVolume = val)
                  : null,
              title: Text('Create Hidden Volume',
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(
                isEnabled
                    ? 'Create an invisible secondary volume'
                    : 'Set outer password or keyfiles first to enable',
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
                    labelText: 'Hidden Password',
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
                    labelText: 'Confirm Hidden Password',
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
                        decoration: const InputDecoration(
                          labelText: 'Hidden Size',
                          prefixIcon: Icon(Icons.sd_card_outlined, size: 20),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OptionPickerTile<String>(
                        label: 'Unit',
                        value: _hiddenSizeUnit,
                        options: const [
                          SelectOption(value: 'MB', label: 'MB (Megabytes)'),
                          SelectOption(value: 'GB', label: 'GB (Gigabytes)'),
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
                    label: 'Hidden File System',
                    value: _hiddenFileSystem,
                    prefixIcon: Icons.dns_rounded,
                    subtitle: 'File system: $_hiddenFileSystem',
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

  // ── Folder vault (Cryptomator / Gocryptfs) section ─────────────────────────

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
                      hasSelection ? 'Destination Folder' : 'Select an empty folder',
                      style: textTheme.labelMedium?.copyWith(
                        color: hasSelection ? cs.primary : cs.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _folderVaultDisplayName ??
                          'Tap to choose where vault will be created…',
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
        SectionHeader('Folder Vault'),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Vault Format',
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _folderVaultPasswordCtrl,
                obscureText: _folderVaultObscure,
                onChanged: (_) => setState(() {}),
                autofillHints: const [AutofillHints.newPassword],
                decoration: InputDecoration(
                  labelText: 'Password',
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
                  labelText: 'Confirm Password',
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
                      "Folder vaults don't support keyfiles, PIM, hidden "
                      'volumes, or VeraCrypt/LUKS cipher choices.',
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
                  _isFolderVault ? 'Create Vault' : 'Create Container',
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
            message:
                '${_isFolderVault ? 'Vault' : 'Container'} creation in progress. Please wait.',
            tone: AppBannerTone.warning,
          );
        }
      },
      child: Scaffold(
        backgroundColor: cs.surfaceContainerLow,
        appBar: AppBar(
          backgroundColor: cs.surfaceContainerHigh,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _isFolderVault
                ? 'Create Encrypted Vault'
                : 'Create Encrypted Container',
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