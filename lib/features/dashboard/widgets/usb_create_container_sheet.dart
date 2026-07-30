import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/data/models/usb_device_info.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfile_picker_mixin.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

/// Formats a brand-new encrypted container directly onto a raw USB drive,
/// erasing everything currently on it.
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

  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);

  String _sizeUnit = 'MB';
  String _fileSystem = 'exFAT';
  int _cipherId = 0; // AES
  int _hashId = 0; // SHA-512
  bool _quickFormat = true;

  // ── Hidden Volume State ──
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

  Widget _buildFormatSelector() {
    final busy = _creating || _requestingPermission;
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
      onSelectionChanged: busy ? null : (sel) => _onFormatChanged(sel.first),
    );
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
    if (_passwordCtrl.text.isEmpty && keyfiles.isEmpty) {
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
          hasHiddenKeyfiles: _hiddenKeyfilesController.keyfiles.isNotEmpty,
          outerKeyfileUris: keyfiles.map((k) => k.uri).toSet(),
          hiddenKeyfileUris:
              _hiddenKeyfilesController.keyfiles.map((k) => k.uri).toSet(),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader('USB Drive & Standard Volume'),
        SectionCard(
          children: [
            // Warning Banner
            Padding(
              padding: const EdgeInsets.all(16),
              child: InlineBanner(
                'Formatting erases everything currently on the selected drive.',
                tone: AppBannerTone.warning,
              ),
            ),

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

            // USB Drive Selection List
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                                                  ? 'Ready to format'
                                                  : 'Permission required',
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

            // Container Size & Unit Row
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
                            SelectOption(
                                value: 'MB', label: 'MB (Megabytes)'),
                            SelectOption(
                                value: 'GB', label: 'GB (Gigabytes)'),
                          ],
                          onChanged: busy
                              ? (v) {}
                              : (v) => setState(() => _sizeUnit = v),
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
                      style: textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant),
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
                enabled: !busy,
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
            ),

            // Keyfiles Picker
            KeyfilesPicker(
              keyfiles: keyfiles,
              picking: pickingKeyfiles,
              onPick: pickKeyfiles,
              onRemove: removeKeyfile,
              enabled: !busy,
            ),

            // Advanced Parameters Panel
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
                OptionPickerTile<String>(
                  label: 'Format File System',
                  value: _fileSystem,
                  prefixIcon: Icons.dns_rounded,
                  options: _availableFileSystems
                      .map((fs) => SelectOption(value: fs, label: fs))
                      .toList(),
                  onChanged: busy
                      ? (val) {}
                      : (val) => setState(() => _fileSystem = val),
                ),
              ],
            ),

            // Quick Format Switch Tile
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: Text('Quick Format',
                  style: textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              subtitle: Text(
                'Skips zero-filling the drive. Faster, but does not securely erase old data.',
                style: textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: _quickFormat,
              onChanged: busy ? null : (val) => setState(() => _quickFormat = val),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHiddenVolumeSection(ColorScheme cs, TextTheme textTheme) {
    final busy = _creating || _requestingPermission;
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
              onChanged: (isEnabled && !busy)
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
                  enabled: !busy,
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
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _hiddenSizeCtrl,
                        enabled: !busy,
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
                        onChanged: busy
                            ? (val) {}
                            : (val) => setState(() => _hiddenSizeUnit = val),
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
                  OptionPickerTile<String>(
                    label: 'Hidden File System',
                    value: _hiddenFileSystem,
                    prefixIcon: Icons.dns_rounded,
                    options: _veraCryptFileSystems
                        .map((fs) => SelectOption(value: fs, label: fs))
                        .toList(),
                    onChanged: busy
                        ? (val) {}
                        : (val) => setState(() => _hiddenFileSystem = val),
                  ),
                ],
              ),
            ],
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
    final busy = _creating || _requestingPermission;

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
          backgroundColor: cs.surfaceContainerHigh,
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: AutofillGroup(
                child: isLandscape
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildMainVolumeSection(cs, textTheme),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (showHiddenSection) ...[
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

