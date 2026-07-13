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
    super.dispose();
  }

  void _onFormatChanged(CreateFormat format) {
    setState(() {
      _format = format;
      if (!_availableFileSystems.contains(_fileSystem)) {
        _fileSystem = _availableFileSystems.first;
      }
      if (!_cipherChoices.any((c) => c.id == _cipherId)) {
        _cipherId = _cipherChoices.first.id;
      }
      if (!_hashChoices.any((h) => h.id == _hashId)) {
        _hashId = _hashChoices.first.id;
      }
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
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: Icon(prefixIcon, size: 22, color: cs.primary),
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
      initialValue: _format,
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Encrypted Container'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: AutofillGroup(
            child: isLandscape
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildFormatSelector(cs),
                            const SizedBox(height: 16),

                            // File name
                            TextField(
                              controller: _nameCtrl,
                              decoration: _getInputDecoration(
                                cs,
                                labelText: 'File Name',
                                prefixIcon: Icons.drive_file_rename_outline_rounded,
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Size and unit selection
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: _sizeCtrl,
                                    keyboardType: const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
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
                                    initialValue: _sizeUnit,
                                    decoration: _getInputDecoration(
                                      cs,
                                      labelText: 'Unit',
                                      prefixIcon: Icons.scale_rounded,
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'MB', child: Text('MB')),
                                      DropdownMenuItem(value: 'GB', child: Text('GB')),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _sizeUnit = val);
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),

                            // Password
                            TextField(
                              controller: _passwordCtrl,
                              obscureText: _obscure,
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 24),
                      // Right column
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildAdvancedTile(context),
                            if (_error != null) ...[
                              const SizedBox(height: 16),
                              InlineErrorBanner(_error!),
                            ],
                            const SizedBox(height: 32),
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
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFormatSelector(cs),
                      const SizedBox(height: 16),

                      // File name
                      TextField(
                        controller: _nameCtrl,
                        decoration: _getInputDecoration(
                          cs,
                          labelText: 'File Name',
                          prefixIcon: Icons.drive_file_rename_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Size and unit selection
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _sizeCtrl,
                              keyboardType: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
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
                              initialValue: _sizeUnit,
                              decoration: _getInputDecoration(
                                cs,
                                labelText: 'Unit',
                                prefixIcon: Icons.scale_rounded,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'MB', child: Text('MB')),
                                DropdownMenuItem(value: 'GB', child: Text('GB')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _sizeUnit = val);
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextField(
                        controller: _passwordCtrl,
                        obscureText: _obscure,
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
                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        InlineErrorBanner(_error!),
                      ],
                      const SizedBox(height: 32),
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
                  ),
          ),
        ),
      ),
    );
  }
}