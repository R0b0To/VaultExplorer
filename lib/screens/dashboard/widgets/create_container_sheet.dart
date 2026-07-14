import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/vaultexplorer_api.dart';
import '../../../utils/validation_utils.dart';
import '../../../theme.dart';
import '../../../widgets/common_widgets.dart';
import '../../../models/crypto_algorithms.dart';

class CreateContainerSheet extends StatefulWidget {
  const CreateContainerSheet({Key? key}) : super(key: key);

  @override
  State<CreateContainerSheet> createState() => _CreateContainerSheetState();
}

class _CreateContainerSheetState extends State<CreateContainerSheet> {
  final _nameCtrl = TextEditingController(text: 'vault');
  final _sizeCtrl = TextEditingController(text: '100');
  final _passwordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();

  static const _veraCryptFileSystems = ['FAT', 'exFAT', 'NTFS', 'ext2', 'ext3', 'ext4'];
  // LUKS containers are restricted to the ext family — the realistic
  // pairing for a container the user also intends to mount on Linux.
  static const _luksFileSystems = ['ext2', 'ext3', 'ext4'];

  String _sizeUnit = 'MB';
  CreateFormat _format = CreateFormat.veracrypt;
  String _fileSystem = 'FAT';
  int _cipherId = 0; // AES
  int _hashId = 0; // SHA-512
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  bool _enableHiddenVolume = false;
  final _hiddenPasswordCtrl = TextEditingController();
  final _hiddenPimCtrl = TextEditingController();
  bool _hiddenObscure = true;
  String _hiddenSizeUnit = 'MB';
  final _hiddenSizeCtrl = TextEditingController(text: '10');
  List<KeyfileRef> _hiddenKeyfiles = [];
  bool _pickingHiddenKeyfiles = false;
  String _hiddenFileSystem = 'FAT';
  int _hiddenCipherId = 0; // AES
  int _hiddenHashId = 0; // SHA-512

  List<KeyfileRef> _keyfiles = [];
  bool _pickingKeyfiles = false;

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
    _pimCtrl.dispose();
    _hiddenPasswordCtrl.dispose();
    _hiddenPimCtrl.dispose();
    _hiddenSizeCtrl.dispose();
    super.dispose();
  }

  void _onFormatChanged(CreateFormat format) {
    setState(() {
      _format = format;
      
      // Set the sensible defaults based on the chosen format
      _fileSystem = _format == CreateFormat.veracrypt ? 'FAT' : 'ext4';
      
      if (!_cipherChoices.any((c) => c.id == _cipherId)) {
        _cipherId = _cipherChoices.first.id;
      }
      if (!_hashChoices.any((h) => h.id == _hashId)) {
        _hashId = _hashChoices.first.id;
      }
      
      // Hidden volumes only apply to VeraCrypt, so 'FAT' is a safe default
      _hiddenFileSystem = 'FAT';
    });
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

  Future<void> _create() async {
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

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final multiplier = _sizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
      final sizeBytes = (sizeVal * multiplier).round();

      int hiddenSizeBytes = 0;
      if (_enableHiddenVolume && _format == CreateFormat.veracrypt) {
        final hiddenSizeVal = double.tryParse(_hiddenSizeCtrl.text);
        if (hiddenSizeVal == null || hiddenSizeVal <= 0) {
          setState(() => _error = 'Enter a valid hidden size greater than 0');
          return;
        }
        final hiddenMultiplier = _hiddenSizeUnit == 'GB' ? 1024 * 1024 * 1024 : 1024 * 1024;
        hiddenSizeBytes = (hiddenSizeVal * hiddenMultiplier).round();

        if (hiddenSizeBytes >= sizeBytes) {
          setState(() => _error = 'Hidden volume size must be less than the outer volume size');
          return;
        }
        const vcDataAreaOffset = 131072;
        if (sizeBytes <= vcDataAreaOffset + hiddenSizeBytes) {
          setState(() => _error = 'Hidden volume size is too large for this container size');
          return;
        }

        if (_hiddenPasswordCtrl.text.isEmpty && _hiddenKeyfiles.isEmpty) {
          setState(() => _error = 'A hidden password or keyfile is required when creating a hidden volume');
          return;
        }

        final outerPimVal = _pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0;
        final hiddenPimVal = _hiddenPimCtrl.text.isEmpty ? 0 : int.tryParse(_hiddenPimCtrl.text) ?? 0;

        final outerUris = _keyfiles.map((k) => k.uri).toSet();
        final hiddenUris = _hiddenKeyfiles.map((k) => k.uri).toSet();

        final samePassword = _passwordCtrl.text == _hiddenPasswordCtrl.text;
        final samePim = outerPimVal == hiddenPimVal;
        final sameKeyfiles = outerUris.length == hiddenUris.length && outerUris.difference(hiddenUris).isEmpty;

        if (samePassword && samePim && sameKeyfiles) {
          setState(() => _error = 'Hidden volume credentials (password, PIM, and keyfiles) cannot be identical to the outer volume credentials.');
          return;
        }
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

  InputDecoration _getInputDecoration(
    ColorScheme cs, {
    required String labelText,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 22, color: cs.primary) : null,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 2),
      ),
    );
  }

  Widget _buildFormatSelector(ColorScheme cs) {
    return DropdownButtonFormField<CreateFormat>(
      value: _format,
      decoration: _getInputDecoration(
        cs,
        labelText: 'Container Format',
        prefixIcon: Icons.dns_outlined,
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
          value: _fileSystem,
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
    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.storage_outlined, color: cs.primary),
            title: Text('Standard Volume', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            subtitle: Text('Primary container settings', style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildFormatSelector(cs),
                const SizedBox(height: 16),
                TextField(
                  controller: _nameCtrl,
                  decoration: _getInputDecoration(
                    cs,
                    labelText: 'File Name',
                    prefixIcon: Icons.drive_file_rename_outline_rounded,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _sizeCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: _getInputDecoration(
                          cs,
                          labelText: 'Container Size',
                          prefixIcon: Icons.sd_card_outlined,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _sizeUnit,
                        isExpanded: true,
                        decoration: _getInputDecoration(
                          cs,
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
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  onChanged: (_) => setState(() {}),
                  autofillHints: const [AutofillHints.password],
                  decoration: _getInputDecoration(
                    cs,
                    labelText: 'Password',
                    prefixIcon: Icons.key_rounded,
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _obscure,
                      onToggle: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _buildKeyfilesPicker(),
                const SizedBox(height: 16),
                _buildAdvancedTile(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHiddenVolumeSection(ColorScheme cs, TextTheme textTheme) {
    final bool isEnabled = _passwordCtrl.text.isNotEmpty || _keyfiles.isNotEmpty;

    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            value: isEnabled && _enableHiddenVolume,
            onChanged: isEnabled
                ? (val) => setState(() => _enableHiddenVolume = val)
                : null,
            title: Text('Create Hidden Volume', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          if (isEnabled && _enableHiddenVolume) ...[
            Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  TextField(
                    controller: _hiddenPasswordCtrl,
                    obscureText: _hiddenObscure,
                    onChanged: (_) => setState(() {}),
                    autofillHints: const [AutofillHints.password],
                    decoration: _getInputDecoration(
                      cs,
                      labelText: 'Hidden Password',
                      prefixIcon: Icons.key_rounded,
                      suffixIcon: PasswordVisibilityToggle(
                        obscured: _hiddenObscure,
                        onToggle: () => setState(() => _hiddenObscure = !_hiddenObscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _hiddenSizeCtrl,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: _getInputDecoration(
                            cs,
                            labelText: 'Hidden Size',
                            prefixIcon: Icons.sd_card_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          value: _hiddenSizeUnit,
                          decoration: _getInputDecoration(
                            cs,
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
                        value: _hiddenFileSystem,
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
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
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
              : const Text('Create Container'),
        ),
      ],
    );

    return PopScope(
      canPop: !_loading,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _loading) {
          showAppSnackBar(
            context,
            message: 'Container creation in progress. Please wait.',
            tone: AppBannerTone.warning,
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create Encrypted Container'),
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
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            child: AutofillGroup(
              child: isLandscape
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left column (Main Container Settings)
                        Expanded(
                          child: _buildMainVolumeSection(cs, textTheme),
                        ),
                        const SizedBox(width: 24),
                        // Right column (Hidden Volume Settings + Create Button)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_format == CreateFormat.veracrypt) ...[
                                _buildHiddenVolumeSection(cs, textTheme),
                                const SizedBox(height: 24),
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
                        _buildMainVolumeSection(cs, textTheme),
                        const SizedBox(height: 24),
                        if (_format == CreateFormat.veracrypt) ...[
                          _buildHiddenVolumeSection(cs, textTheme),
                          const SizedBox(height: 24),
                        ],
                        errorAndSubmit,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}