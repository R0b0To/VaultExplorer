import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/vaultexplorer_api.dart';
import '../../../models/usb_device_info.dart';
import '../../../utils/validation_utils.dart';
import '../../../theme.dart';
import '../../../widgets/common_widgets.dart';
import '../../../models/crypto_algorithms.dart';

/// Formats a brand-new encrypted container directly onto a raw USB drive,
/// erasing everything currently on it.
class UsbCreateContainerSheet extends StatefulWidget {
  const UsbCreateContainerSheet({super.key});

  @override
  State<UsbCreateContainerSheet> createState() =>
      _UsbCreateContainerSheetState();
}

class _UsbCreateContainerSheetState extends State<UsbCreateContainerSheet> {
  static const _veraCryptFileSystems = [
    'FAT',
    'exFAT',
    'NTFS',
    'ext2',
    'ext3',
    'ext4'
  ];
  static const _luksFileSystems = ['ext2', 'ext3', 'ext4'];

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

  String _sizeUnit = 'MB';
  String _fileSystem = 'exFAT';
  int _cipherId = 0; // AES
  int _hashId = 0; // SHA-512
  bool _quickFormat = true;

  final List<KeyfileRef> _keyfiles = [];
  bool _pickingKeyfiles = false;

  // ── Hidden Volume State ──
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

  int? _usableCapacityBytes;
  bool _fetchingCapacity = false;

  CreateFormat _format = CreateFormat.veracrypt;

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

  List<DropdownMenuItem<int>> get _cipherItems => _cipherChoices
      .map((c) => DropdownMenuItem(value: c.id, child: Text(c.label)))
      .toList();

  List<DropdownMenuItem<int>> get _hashItems => _hashChoices
      .map((h) => DropdownMenuItem(value: h.id, child: Text(h.label)))
      .toList();

  void _onFormatChanged(CreateFormat format) {
    setState(() {
      _format = format;
      _fileSystem = format == CreateFormat.veracrypt ? 'exFAT' : 'ext4';
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
          _error = 'Failed to list USB devices: $e';
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
        if (!granted) _error = 'USB permission denied';
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
        _error = 'Could not read drive capacity — enter size manually.';
      }
    });
  }

  Future<void> _pickKeyfiles() async {
    setState(() => _pickingKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (picked.isNotEmpty && mounted) {
        setState(() {
          for (final k in picked) {
            if (!_keyfiles.any((existing) => existing.uri == k.uri)) {
              _keyfiles.add(k);
            }
          }
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Could not pick keyfiles');
      }
    } finally {
      if (mounted) setState(() => _pickingKeyfiles = false);
    }
  }

  void _removeKeyfile(KeyfileRef keyfile) {
    setState(() => _keyfiles.removeWhere((k) => k.uri == keyfile.uri));
  }

  Future<void> _pickHiddenKeyfiles() async {
    setState(() => _pickingHiddenKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (picked.isNotEmpty && mounted) {
        setState(() {
          for (final k in picked) {
            if (!_hiddenKeyfiles.any((existing) => existing.uri == k.uri)) {
              _hiddenKeyfiles.add(k);
            }
          }
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Could not pick hidden keyfiles');
      }
    } finally {
      if (mounted) setState(() => _pickingHiddenKeyfiles = false);
    }
  }

  void _removeHiddenKeyfile(KeyfileRef keyfile) {
    setState(() => _hiddenKeyfiles.removeWhere((k) => k.uri == keyfile.uri));
  }

  Future<void> _create() async {
    final device = _selected;
    if (device == null) {
      setState(() => _error = 'Select a USB drive first');
      return;
    }
    final sizeVal = double.tryParse(_sizeCtrl.text);
    if (sizeVal == null || sizeVal <= 0) {
      setState(() => _error = 'Enter a valid size greater than 0');
      return;
    }
    if (_passwordCtrl.text.isEmpty && _keyfiles.isEmpty) {
      setState(
          () => _error = 'A password or at least one keyfile is required');
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

    final confirmed = await showAppConfirmDialog(
      context,
      title: 'Erase "${device.productName}"?',
      message: 'This will permanently erase everything currently on this '
          'USB drive and replace it with a new encrypted container. This '
          'cannot be undone.',
      confirmLabel: 'Erase & Create',
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
          setState(() => _error = 'USB permission is required to continue');
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

      final success = await vaultExplorerApi.createUsbContainer(
        deviceName: device.deviceName,
        sizeBytes: sizeBytes,
        password: _passwordCtrl.text,
        pim: pim,
        fileSystem: _fileSystem.toLowerCase(),
        containerFormat: _format.id,
        cipherId: _cipherId,
        hashId: _hashId,
        keyfilePaths: _keyfiles.map((k) => k.uri).toList(),
        quickFormat: _quickFormat,
        createHiddenVolume:
            _enableHiddenVolume && _format == CreateFormat.veracrypt,
        hiddenPassword: _hiddenPasswordCtrl.text,
        hiddenFileSystem: _hiddenFileSystem.toLowerCase(),
        hiddenSizeBytes: hiddenSizeBytes,
        hiddenKeyfilePaths: _hiddenKeyfiles.map((k) => k.uri).toList(),
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
          message: 'USB container created. Use "Mount USB drive" to unlock it.',
          tone: AppBannerTone.success,
        );
      } else {
        setState(() => _error = 'USB container creation failed.');
      }
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? 'Unknown error occurred');
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  Widget _buildMainVolumeSection(ColorScheme cs, TextTheme textTheme) {
    final busy = _creating || _requestingPermission;

    return _ExpressiveCard(
      children: [
        const _ExpressiveSectionHeader(
          title: 'USB Drive & Standard Volume',
          subtitle: 'Target device, format and credentials',
          icon: Icons.usb_rounded,
        ),
        InlineBanner(
          'Formatting erases everything currently on the selected drive.',
          tone: AppBannerTone.warning,
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<CreateFormat>(
          initialValue: _format,
          decoration: const InputDecoration(
            labelText: 'Container Format',
            prefixIcon: Icon(Icons.layers_outlined, size: 20),
          ),
          items: CreateFormat.values
              .map((f) => DropdownMenuItem(value: f, child: Text(f.label)))
              .toList(),
          onChanged: busy
              ? null
              : (val) {
                  if (val != null) _onFormatChanged(val);
                },
        ),
        const SizedBox(height: 20),
        Text(
          'Select USB Drive',
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
                    child: Icon(Icons.usb_off_rounded,
                        size: 32, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'No USB storage detected',
                    style: textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Connect an OTG drive to format',
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy ? null : _loadDevices,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Refresh list'),
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
                final isSelected = _selected?.deviceName == d.deviceName;
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
                                    d.hasPermission
                                        ? 'Ready to format'
                                        : 'Permission required',
                                    style: textTheme.bodySmall?.copyWith(
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
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              flex: 2,
              child: TextField(
                controller: _sizeCtrl,
                enabled: !busy,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
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
                onChanged: busy
                    ? null
                    : (v) {
                        if (v != null) setState(() => _sizeUnit = v);
                      },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _fetchingCapacity
                ? 'Reading drive capacity…'
                : _usableCapacityBytes != null
                    ? 'Drive usable capacity: ${(_usableCapacityBytes! / (1024 * 1024)).floor()} MB. Must not exceed this.'
                    : 'Must not exceed the drive\'s actual capacity.',
            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _passwordCtrl,
          enabled: !busy,
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
          enabled: !busy,
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
        const SizedBox(height: 16),
        KeyfilesPicker(
          keyfiles: _keyfiles,
          picking: _pickingKeyfiles,
          onPick: _pickKeyfiles,
          onRemove: _removeKeyfile,
          enabled: !busy,
        ),
        const SizedBox(height: 16),
        AdvancedParamsPanel(
          pimController: _pimCtrl,
          cipherId: _cipherId,
          hashId: _hashId,
          includeAuto: false,
          enabled: !busy,
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
              onChanged: busy
                  ? null
                  : (val) {
                      if (val != null) setState(() => _fileSystem = val);
                    },
            ),
          ],
        ),
        const SizedBox(height: 16),
        Material(
          color: cs.surfaceContainerHigh,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            title: Text('Quick Format',
                style:
                    textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Skips zero-filling the drive. Faster, but does not securely erase old data.',
              style: textTheme.bodySmall,
            ),
            value: _quickFormat,
            onChanged: busy ? null : (val) => setState(() => _quickFormat = val),
          ),
        ),
      ],
    );
  }

  Widget _buildHiddenVolumeSection(ColorScheme cs, TextTheme textTheme) {
    final busy = _creating || _requestingPermission;
    final bool isEnabled =
        _passwordCtrl.text.isNotEmpty || _keyfiles.isNotEmpty;

    return _ExpressiveCard(
      children: [
        const _ExpressiveSectionHeader(
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
            onChanged: (isEnabled && !busy)
                ? (val) => setState(() => _enableHiddenVolume = val)
                : null,
            title: Text('Create Hidden Volume',
                style:
                    textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold)),
            subtitle: Text(
              isEnabled
                  ? 'Create an invisible secondary volume'
                  : 'Set outer password or keyfiles first to enable',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            secondary: Icon(
              Icons.visibility_off_outlined,
              color: isEnabled
                  ? cs.primary
                  : cs.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        if (isEnabled && _enableHiddenVolume) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _hiddenPasswordCtrl,
            enabled: !busy,
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
            enabled: !busy,
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
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _hiddenSizeCtrl,
                  enabled: !busy,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
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
                  onChanged: busy
                      ? null
                      : (val) {
                          if (val != null) {
                            setState(() => _hiddenSizeUnit = val);
                          }
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
            enabled: !busy,
          ),
          const SizedBox(height: 16),
          AdvancedParamsPanel(
            pimController: _hiddenPimCtrl,
            cipherId: _hiddenCipherId,
            hashId: _hiddenHashId,
            includeAuto: false,
            enabled: !busy,
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
                items: _veraCryptFileSystems
                    .map((fs) => DropdownMenuItem(value: fs, child: Text(fs)))
                    .toList(),
                onChanged: busy
                    ? null
                    : (val) {
                        if (val != null) {
                          setState(() => _hiddenFileSystem = val);
                        }
                      },
              ),
            ],
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final busy = _creating || _requestingPermission;

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
          onPressed: busy || _devices.isEmpty ? null : _create,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: const StadiumBorder(),
          ),
          child: _creating
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                  ),
                )
              : const Text(
                  'Erase & Create Container',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
      ],
    );

    final showHiddenSection = _format == CreateFormat.veracrypt;

    return PopScope(
      canPop: !busy,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && busy) {
          showAppSnackBar(
            context,
            message: 'Container creation in progress. Please wait.',
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
          title: const Text(
            'Format USB Drive',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          bottom: _creating
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
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildMainVolumeSection(cs, textTheme),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showHiddenSection) ...[
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
                          _buildMainVolumeSection(cs, textTheme),
                          const SizedBox(height: 16),
                          if (showHiddenSection) ...[
                            _buildHiddenVolumeSection(cs, textTheme),
                            const SizedBox(height: 16),
                          ],
                          errorAndSubmit,
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

// ── Android 16/17 Expressive Card Wrapper ──────────────────────────────────────

class _ExpressiveCard extends StatelessWidget {
  final List<Widget> children;
  const _ExpressiveCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

// ── Expressive Section Header ────────────────────────────────────────────────

class _ExpressiveSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _ExpressiveSectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}