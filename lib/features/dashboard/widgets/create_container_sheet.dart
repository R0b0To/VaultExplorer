import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/core/widgets/cards/expressive_card.dart';

class CreateContainerSheet extends StatefulWidget {
  const CreateContainerSheet({super.key});

  @override
  State<CreateContainerSheet> createState() => _CreateContainerSheetState();
}

class _CreateContainerSheetState extends State<CreateContainerSheet> {
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
  final List<KeyfileRef> _hiddenKeyfiles = [];
  bool _pickingHiddenKeyfiles = false;
  String _hiddenFileSystem = 'FAT';
  int _hiddenCipherId = 0; // AES
  int _hiddenHashId = 0; // SHA-512

  final List<KeyfileRef> _keyfiles = [];
  bool _pickingKeyfiles = false;

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

  Future<void> _pickKeyfiles() async {
    setState(() => _pickingKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (picked.isNotEmpty) {
        setState(() {
          for (final k in picked) {
            if (!_keyfiles.any((existing) => existing.uri == k.uri)) {
              _keyfiles.add(k);
            }
          }
        });
      }
    } finally {
      if (mounted) setState(() => _pickingKeyfiles = false);
    }
  }

  void _removeKeyfile(KeyfileRef keyfile) {
    setState(() => _keyfiles.remove(keyfile));
  }

  Future<void> _pickHiddenKeyfiles() async {
    setState(() => _pickingHiddenKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (picked.isNotEmpty) {
        setState(() {
          for (final k in picked) {
            if (!_hiddenKeyfiles.any((existing) => existing.uri == k.uri)) {
              _hiddenKeyfiles.add(k);
            }
          }
        });
      }
    } finally {
      if (mounted) setState(() => _pickingHiddenKeyfiles = false);
    }
  }

  void _removeHiddenKeyfile(KeyfileRef keyfile) {
    setState(() => _hiddenKeyfiles.remove(keyfile));
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Vault created successfully.'),
            ),
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
    if (_passwordCtrl.text.isEmpty && _keyfiles.isEmpty) {
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
          hasHiddenKeyfiles: _hiddenKeyfiles.isNotEmpty,
          outerKeyfileUris: _keyfiles.map((k) => k.uri).toSet(),
          hiddenKeyfileUris: _hiddenKeyfiles.map((k) => k.uri).toSet(),
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
        keyfilePaths: _keyfiles.map((k) => k.uri).toList(),
        createHiddenVolume: _enableHiddenVolume && _format == CreateFormat.veracrypt,
        hiddenPassword: _hiddenPasswordCtrl.text,
        hiddenFileSystem: _hiddenFileSystem.toLowerCase(),
        hiddenSizeBytes: hiddenSizeBytes,
        hiddenKeyfilePaths: _hiddenKeyfiles.map((k) => k.uri).toList(),
        hiddenPim: _enableHiddenVolume ? clampPim(_hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0) : 0,
        hiddenCipherId: _enableHiddenVolume ? _hiddenCipherId : 255,
        hiddenHashId: _enableHiddenVolume ? _hiddenHashId : 255,
      );

      if (success) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Container file created successfully.'),
            ),
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
    return DropdownButtonFormField<CreateFormat>(
      initialValue: _format,
      decoration: const InputDecoration(
        labelText: 'Container Format',
        prefixIcon: Icon(Icons.dns_outlined, size: 20),
      ),
      items: CreateFormat.values
          .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
          .toList(),
      onChanged: (val) {
        if (val != null) _onFormatChanged(val);
      },
    );
  }

  Widget _buildKeyfilesPicker() {
    return KeyfilesPicker(
      keyfiles: _keyfiles,
      picking: _pickingKeyfiles,
      onPick: _pickKeyfiles,
      onRemove: _removeKeyfile,
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
        DropdownButtonFormField<String>(
          initialValue: _fileSystem,
          decoration: const InputDecoration(
            labelText: 'Format File System',
            prefixIcon: Icon(Icons.dns_rounded, size: AppIconSize.small),
          ),
          items: _availableFileSystems
              .map((fs) => DropdownMenuItem(value: fs, child: Text(fs)))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _fileSystem = val);
          },
        ),
      ],
    );
  }

  Widget _buildMainVolumeSection(ColorScheme cs, TextTheme textTheme) {
    return ExpressiveCard(
      children: [
        const ExpressiveSectionHeader(
          title: 'Standard Volume',
          subtitle: 'Primary container parameters and credentials',
          icon: Icons.storage_rounded,
        ),
        _buildFormatSelector(),
        const SizedBox(height: 14),
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'File Name',
            prefixIcon: Icon(Icons.drive_file_rename_outline_rounded, size: 20),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _sizeCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Container Size',
                  prefixIcon: Icon(Icons.sd_card_outlined, size: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _sizeUnit,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Unit',
                ),
                items: const [
                  DropdownMenuItem(value: 'MB', child: Text('MB')),
                  DropdownMenuItem(value: 'GB', child: Text('GB')),
                ],
                onChanged: (val) {
                  if (val != null) setState(() => _sizeUnit = val);
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordCtrl,
          obscureText: _obscure,
          onChanged: (_) => setState(() {}),
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _obscure,
              onToggle: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPasswordCtrl,
          obscureText: _confirmObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _confirmObscure,
              onToggle: () => setState(() => _confirmObscure = !_confirmObscure),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildKeyfilesPicker(),
        const SizedBox(height: 16),
        _buildAdvancedTile(context),
      ],
    );
  }

  Widget _buildHiddenVolumeSection(ColorScheme cs, TextTheme textTheme) {
    final bool isEnabled = _passwordCtrl.text.isNotEmpty || _keyfiles.isNotEmpty;

    return ExpressiveCard(
      children: [
        const ExpressiveSectionHeader(
          title: 'Hidden Volume',
          subtitle: 'Plausibly deniable secondary volume',
          icon: Icons.visibility_off_rounded,
        ),
        Material(
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            value: isEnabled && _enableHiddenVolume,
            onChanged: isEnabled
                ? (val) => setState(() => _enableHiddenVolume = val)
                : null,
            title: Text('Create Hidden Volume', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Text(
              isEnabled
                  ? 'Create an invisible secondary volume'
                  : 'Set outer password or keyfiles first to enable',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            secondary: Icon(
              Icons.visibility_off_outlined,
              color: isEnabled ? cs.primary : cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (isEnabled && _enableHiddenVolume) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _hiddenPasswordCtrl,
            obscureText: _hiddenObscure,
            onChanged: (_) => setState(() {}),
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Hidden Password',
              prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
              suffixIcon: PasswordVisibilityToggle(
                obscured: _hiddenObscure,
                onToggle: () => setState(() => _hiddenObscure = !_hiddenObscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _hiddenConfirmPasswordCtrl,
            obscureText: _hiddenConfirmObscure,
            onChanged: (_) => setState(() {}),
            autofillHints: const [AutofillHints.newPassword],
            decoration: InputDecoration(
              labelText: 'Confirm Hidden Password',
              prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
              suffixIcon: PasswordVisibilityToggle(
                obscured: _hiddenConfirmObscure,
                onToggle: () => setState(() => _hiddenConfirmObscure = !_hiddenConfirmObscure),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _hiddenSizeCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Hidden Size',
                    prefixIcon: Icon(Icons.sd_card_outlined, size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: _hiddenSizeUnit,
                  decoration: const InputDecoration(
                    labelText: 'Unit',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'MB', child: Text('MB')),
                    DropdownMenuItem(value: 'GB', child: Text('GB')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _hiddenSizeUnit = val);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          KeyfilesPicker(
            keyfiles: _hiddenKeyfiles,
            picking: _pickingHiddenKeyfiles,
            onPick: _pickHiddenKeyfiles,
            onRemove: _removeHiddenKeyfile,
            enabled: !_loading,
          ),
          const SizedBox(height: 16),
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
              DropdownButtonFormField<String>(
                initialValue: _hiddenFileSystem,
                decoration: const InputDecoration(
                  labelText: 'Hidden File System',
                  prefixIcon: Icon(Icons.dns_rounded, size: AppIconSize.small),
                ),
                items: _availableFileSystems.map((fs) => DropdownMenuItem(value: fs, child: Text(fs))).toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _hiddenFileSystem = val);
                },
              ),
            ],
          ),
        ],
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
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: hasSelection ? cs.primary : cs.outlineVariant.withValues(alpha: 0.35),
            width: hasSelection ? 1.5 : 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: hasSelection ? cs.primaryContainer : cs.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  _folderVaultFormat == 'gocryptfs' || _folderVaultFormat == 'cryfs'
                      ? Icons.enhanced_encryption_rounded
                      : Icons.folder_shared_rounded,
                  size: 26,
                  color: hasSelection ? cs.onPrimaryContainer : cs.onSurfaceVariant,
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
                      _folderVaultDisplayName ?? 'Tap to choose where vault will be created…',
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

  Widget _buildFolderVaultSection(ColorScheme cs, TextTheme textTheme) {
    return ExpressiveCard(
      children: [
        const ExpressiveSectionHeader(
          title: 'Folder Vault',
          subtitle: 'Cryptomator, Gocryptfs, or CryFS compatible directory structure',
          icon: Icons.folder_shared_rounded,
        ),
        _buildFolderVaultFormatSelector(),
        const SizedBox(height: 16),
        _buildFolderVaultPickerCard(cs, textTheme),
        const SizedBox(height: 16),
        TextField(
          controller: _folderVaultPasswordCtrl,
          obscureText: _folderVaultObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _folderVaultObscure,
              onToggle: () => setState(() => _folderVaultObscure = !_folderVaultObscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _folderVaultConfirmCtrl,
          obscureText: _folderVaultConfirmObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Confirm Password',
            prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _folderVaultConfirmObscure,
              onToggle: () => setState(() => _folderVaultConfirmObscure = !_folderVaultConfirmObscure),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: cs.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                "Folder vaults don't support keyfiles, PIM, hidden "
                'volumes, or VeraCrypt/LUKS cipher choices.',
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
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
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    final inputDecorationTheme = InputDecorationTheme(
      filled: true,
      fillColor: cs.surfaceContainerHigh,
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
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
      ],
    );

    final primarySection = _isFolderVault
        ? _buildFolderVaultSection(cs, textTheme)
        : _buildMainVolumeSection(cs, textTheme);
    final showHiddenVolumeSection = !_isFolderVault && _format == CreateFormat.veracrypt;

    return PopScope(
      canPop: !_loading,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _loading) {
          showAppSnackBar(
            context,
            message: '${_isFolderVault ? 'Vault' : 'Container'} creation in progress. Please wait.',
            tone: AppBannerTone.warning,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            _isFolderVault ? 'Create Encrypted Vault' : 'Create Encrypted Container',
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildVaultKindSelector(),
                    const SizedBox(height: 20),
                    isLandscape
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: primarySection,
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    if (showHiddenVolumeSection) ...[
                                      _buildHiddenVolumeSection(cs, textTheme),
                                      const SizedBox(height: 20),
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
