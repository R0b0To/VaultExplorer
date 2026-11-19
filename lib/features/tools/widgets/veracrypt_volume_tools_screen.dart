import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/veracrypt_tools_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/layout/section_card.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfiles_picker.dart';
import 'package:vaultexplorer/core/widgets/inputs/option_picker_tile.dart';
import 'package:vaultexplorer/core/widgets/inputs/utf8_byte_limit_formatter.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

/// The desktop-VeraCrypt volume operations that work on an existing container.
enum VeraCryptVolumeTool { expand, addHidden }

/// Which encryption layer the expand tool is working on. Auto-detected from the picked file, user-overridable.
enum _ExpandFormat { veracrypt, luks, bitlocker }

class VeraCryptVolumeToolsScreen extends ConsumerStatefulWidget {
  const VeraCryptVolumeToolsScreen({super.key, required this.tool});

  final VeraCryptVolumeTool tool;

  @override
  ConsumerState<VeraCryptVolumeToolsScreen> createState() => _VeraCryptVolumeToolsScreenState();
}

class _VeraCryptVolumeToolsScreenState extends ConsumerState<VeraCryptVolumeToolsScreen> {
  late final _api = VeraCryptToolsApi(ref.read(vaultEngineChannelProvider));
  static const _hiddenFileSystems = ['exFAT', 'FAT', 'NTFS'];

  ({String uri, String displayName})? _target;
  final _passwordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();
  List<KeyfileRef> _keyfiles = const [];
  bool _pickingKeyfiles = false;
  bool _showPassword = false;

  // expand: [_sizeCtrl] is the amount to add, or the new total when [_exact] is on (or growing by isn't possible).
  final _sizeCtrl = TextEditingController();
  bool _unitGiB = true;
  bool _exact = false;
  int? _currentBytes;
  int? _freeBytes;
  bool _sizeLoading = false;
  // BitLocker volumes are normally only partly pre-filled, so this flips to off for them in [_setFormat].
  bool _initFree = true;
  bool _growFs = true;
  _ExpandFormat _format = _ExpandFormat.veracrypt;
  bool _probing = false;
  String? _formatHint;

  // hidden volume
  HiddenHostInfo? _host;
  final _hiddenSizeCtrl = TextEditingController();
  final _hiddenPasswordCtrl = TextEditingController();
  final _hiddenConfirmCtrl = TextEditingController();
  final _hiddenPimCtrl = TextEditingController();
  List<KeyfileRef> _hiddenKeyfiles = const [];
  bool _pickingHiddenKeyfiles = false;
  String _hiddenFs = 'exFAT';
  int _hiddenCipherId = CipherAlgo.aes.id;
  int _hiddenHashId = HashAlgo.sha512.id;
  bool _quick = false;

  bool _busy = false;
  String? _error;
  String? _status;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    _sizeCtrl.dispose();
    _hiddenSizeCtrl.dispose();
    _hiddenPasswordCtrl.dispose();
    _hiddenConfirmCtrl.dispose();
    _hiddenPimCtrl.dispose();
    super.dispose();
  }

  bool get _isExpand => widget.tool != VeraCryptVolumeTool.addHidden;
  bool get _isLuksExpand => _isExpand && _format == _ExpandFormat.luks;
  bool get _isBitLockerExpand => _isExpand && _format == _ExpandFormat.bitlocker;

  // A BitLocker target may be a dynamic VHD/VHDX whose file size isn't its virtual disk size, so growing by an amount
  // from the file size would be wrong there: that format always takes the exact new total.
  bool get _canGrowBy => _currentBytes != null && !_isBitLockerExpand;
  bool get _exactMode => !_canGrowBy || _exact;

  int? get _amountBytes {
    final v = double.tryParse(_sizeCtrl.text.trim().replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return (v * (_unitGiB ? 1073741824 : 1048576)).round();
  }

  /// The new total size the native side will apply (it rounds down to 4096).
  int? get _targetBytes {
    final a = _amountBytes;
    if (a == null) return null;
    final total = _exactMode ? a : (_currentBytes ?? 0) + a;
    return (total ~/ 4096) * 4096;
  }

  /// Bytes added to the container, or null when it can't be told (size unknown or no amount entered).
  int? get _addedBytes {
    final t = _targetBytes, c = _currentBytes;
    return (t == null || c == null) ? null : t - c;
  }

  bool get _tooLarge {
    final added = _addedBytes, free = _freeBytes;
    return added != null && free != null && added > free;
  }

  int _pimOf(TextEditingController c) => int.tryParse(c.text.trim()) ?? 0;

  int? _bytesFromMiB(TextEditingController c) {
    final mib = int.tryParse(c.text.trim());
    if (mib == null || mib <= 0) return null;
    return mib * 1048576;
  }

  List<String> get _keyfilePaths => _keyfiles.map((k) => k.uri).toList();

  Future<void> _guard(Future<void> Function() body) async {
    setState(() {
      _busy = true;
      _error = null;
      _status = null;
    });
    try {
      await body();
    } on VeraCryptToolsException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? e.code);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickContainer() async {
    final picked = await _api.pickContainer();
    if (picked == null || !mounted) return;
    setState(() {
      _target = picked;
      _host = null;
      _error = null;
      _status = null;
      _currentBytes = null;
      _freeBytes = null;
      _exact = false;
      _sizeCtrl.clear();
    });
    if (_isExpand) {
      unawaited(_detectFormat(picked.uri));
      unawaited(_loadSizeInfo(picked.uri));
    }
  }

  Future<void> _loadSizeInfo(String uri) async {
    setState(() => _sizeLoading = true);
    ContainerSizeInfo? info;
    try {
      info = await _api.getContainerSizeInfo(uri);
    } catch (_) {
      // Unknown size: the screen falls back to asking for the exact new total.
    }
    if (!mounted || _target?.uri != uri) return;
    setState(() {
      _sizeLoading = false;
      _currentBytes = (info != null && info.sizeBytes > 0) ? info.sizeBytes : null;
      // Some providers report 0 for "can't tell"; treat that as unknown rather than blocking the expand.
      _freeBytes = (info?.freeBytes != null && info!.freeBytes! > 0) ? info.freeBytes : null;
    });
  }

  void _setAmountBytes(int bytes) {
    final inGiB = bytes >= 1073741824;
    final value = bytes / (inGiB ? 1073741824 : 1048576);
    setState(() {
      _unitGiB = inGiB;
      _sizeCtrl.text = value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
      _error = null;
      _status = null;
    });
  }

  Future<void> _detectFormat(String uri) async {
    final l10n = context.l10n;
    setState(() {
      _probing = true;
      _formatHint = null;
    });
    var wire = 'unknown';
    try {
      wire = await ref.read(vaultLifecycleApiProvider).probeContainerFormat(uri);
    } catch (_) {}
    if (!mounted || _target?.uri != uri) return;
    final f = ContainerFormat.fromWire(wire);
    setState(() => _probing = false);
    if (f.isLuks) {
      _setFormat(_ExpandFormat.luks, hint: l10n.vcToolsDetectedFormat(f.label));
    } else if (f.isBitlocker) {
      _setFormat(_ExpandFormat.bitlocker, hint: l10n.vcToolsDetectedFormat('BitLocker'));
    } else if (f.isPlain) {
      _setFormat(_ExpandFormat.veracrypt, hint: l10n.vcToolsUnencryptedDetected);
    } else {
      // VeraCrypt headers are indistinguishable from random data, so "unknown" is the normal VeraCrypt result.
      _setFormat(_ExpandFormat.veracrypt, hint: l10n.vcToolsAssumingVeraCrypt);
    }
  }

  void _setFormat(_ExpandFormat f, {String? hint}) {
    setState(() {
      // "Add" and "new total" mean different things, so a typed amount doesn't carry across that switch.
      if ((f == _ExpandFormat.bitlocker) != (_format == _ExpandFormat.bitlocker)) _sizeCtrl.clear();
      _format = f;
      _formatHint = hint ?? context.l10n.vcToolsManualFormat;
      _initFree = f != _ExpandFormat.bitlocker;
      _error = null;
      _status = null;
      if (f == _ExpandFormat.bitlocker) {
        // Password or recovery key only: drop credentials this format can't use so they can't pass validation silently.
        _keyfiles = const [];
        _pimCtrl.clear();
      } else if (f == _ExpandFormat.luks) {
        _pimCtrl.clear();
        if (_keyfiles.length > 1) _keyfiles = _keyfiles.take(1).toList();
      }
    });
  }

  Future<void> _pickKeyfiles({required bool hidden}) async {
    setState(() {
      if (hidden) {
        _pickingHiddenKeyfiles = true;
      } else {
        _pickingKeyfiles = true;
      }
    });
    try {
      final picked = await _api.pickKeyfiles();
      if (!mounted) return;
      setState(() {
        final current = hidden ? _hiddenKeyfiles : _keyfiles;
        final distinct = picked.where((p) => !current.any((c) => c.uri == p.uri));
        // LUKS follows cryptsetup key-file semantics and this native path
        // consumes one keyfile (which replaces the typed password).
        final merged = _isLuksExpand
            ? (current.isNotEmpty ? current : distinct.take(1).toList())
            : [...current, ...distinct];
        if (hidden) {
          _hiddenKeyfiles = merged;
        } else {
          _keyfiles = merged;
          _host = null;
        }
      });
    } finally {
      if (mounted) {
        setState(() {
          _pickingKeyfiles = false;
          _pickingHiddenKeyfiles = false;
        });
      }
    }
  }

  bool _validateCommon() {
    final l10n = context.l10n;
    if (_target == null) {
      setState(() => _error = l10n.vcToolsNoContainer);
      return false;
    }
    if (_passwordCtrl.text.isEmpty && _keyfiles.isEmpty) {
      setState(() => _error = l10n.vcToolsCredentialsRequired);
      return false;
    }
    return true;
  }

  String _fsResultText(FileSystemGrowResult result) {
    final l10n = context.l10n;
    return switch (result) {
      FileSystemGrowResult.grown => l10n.vcToolsFsGrown,
      FileSystemGrowResult.alreadyFills => l10n.vcToolsFsAlreadyFills,
      FileSystemGrowResult.unsupported => l10n.vcToolsFsUnsupported,
      FileSystemGrowResult.needsCheck => l10n.vcToolsFsNeedsCheck,
      FileSystemGrowResult.busy => l10n.vcToolsFsBusy,
      FileSystemGrowResult.failed => l10n.vcToolsFsFailed,
      FileSystemGrowResult.notRun => '',
    };
  }

  Future<void> _expand() async {
    if (!_validateCommon()) return;
    final newSize = _targetBytes;
    final current = _currentBytes;
    if (newSize == null || (current != null && newSize <= current)) {
      setState(() => _error = context.l10n.vcToolsInvalidSize);
      return;
    }
    if (_tooLarge) {
      setState(() => _error = context.l10n.vcToolsExpandInsufficientSpaceForSize);
      return;
    }
    final doneText = context.l10n.vcToolsExpandDone;
    await _guard(() async {
      final fs = _isBitLockerExpand
          ? await _api.expandBitLockerContainer(
              uri: _target!.uri,
              password: _passwordCtrl.text,
              newSizeBytes: newSize,
              initFreeSpace: _initFree,
              growFileSystem: _growFs,
            )
          : _isLuksExpand
          ? await _api.expandLuksContainer(
              uri: _target!.uri,
              password: _passwordCtrl.text,
              keyfilePaths: _keyfilePaths,
              newSizeBytes: newSize,
              initFreeSpace: _initFree,
              growFileSystem: _growFs,
            )
          : await _api.expandContainer(
              uri: _target!.uri,
              password: _passwordCtrl.text,
              pim: _pimOf(_pimCtrl),
              keyfilePaths: _keyfilePaths,
              newSizeBytes: newSize,
              initFreeSpace: _initFree,
              growFileSystem: _growFs,
            );
      if (!mounted) return;
      final fsText = _fsResultText(fs.result);
      setState(() {
        _status = fsText.isEmpty ? doneText : '$doneText\n$fsText';
        _sizeCtrl.clear();
      });
      unawaited(_loadSizeInfo(_target!.uri));
    });
  }

  Future<void> _growFileSystemOnly() async {
    if (!_validateCommon()) return;
    await _guard(() async {
      final fs = _isBitLockerExpand
          ? await _api.growBitLockerFileSystem(
              uri: _target!.uri,
              password: _passwordCtrl.text,
            )
          : _isLuksExpand
          ? await _api.growLuksFileSystem(
              uri: _target!.uri,
              password: _passwordCtrl.text,
              keyfilePaths: _keyfilePaths,
            )
          : await _api.growFileSystem(
              uri: _target!.uri,
              password: _passwordCtrl.text,
              pim: _pimOf(_pimCtrl),
              keyfilePaths: _keyfilePaths,
            );
      if (mounted) setState(() => _status = _fsResultText(fs.result));
    });
  }

  Future<void> _analyze() async {
    if (!_validateCommon()) return;
    await _guard(() async {
      final info = await _api.analyzeHiddenHost(
        uri: _target!.uri,
        password: _passwordCtrl.text,
        pim: _pimOf(_pimCtrl),
        keyfilePaths: _keyfilePaths,
      );
      if (!mounted) return;
      setState(() {
        _host = info;
        final maxMiB = info.maxHiddenBytes ~/ 1048576;
        if (maxMiB >= 1) _hiddenSizeCtrl.text = maxMiB.toString();
      });
    });
  }

  Future<void> _createHidden() async {
    final l10n = context.l10n;
    if (!_validateCommon()) return;
    final host = _host;
    final size = _bytesFromMiB(_hiddenSizeCtrl);
    if (host == null || host.maxHiddenBytes <= 0 || size == null || size > host.maxHiddenBytes) {
      setState(() => _error = l10n.vcToolsInvalidSize);
      return;
    }
    if (_hiddenPasswordCtrl.text.isEmpty && _hiddenKeyfiles.isEmpty) {
      setState(() => _error = l10n.vcToolsCredentialsRequired);
      return;
    }
    if (_hiddenPasswordCtrl.text != _hiddenConfirmCtrl.text) {
      setState(() => _error = l10n.vcToolsPasswordsDiffer);
      return;
    }
    final doneText = l10n.vcToolsHiddenDone;
    await _guard(() async {
      await _api.createHiddenInExisting(
        uri: _target!.uri,
        outerPassword: _passwordCtrl.text,
        outerPim: _pimOf(_pimCtrl),
        outerKeyfilePaths: _keyfilePaths,
        hiddenPassword: _hiddenPasswordCtrl.text,
        hiddenPim: _pimOf(_hiddenPimCtrl),
        hiddenFileSystem: _hiddenFs,
        hiddenSizeBytes: size,
        hiddenCipherId: _hiddenCipherId,
        hiddenHashId: _hiddenHashId,
        hiddenKeyfilePaths: _hiddenKeyfiles.map((k) => k.uri).toList(),
        quickFormat: _quick,
      );
      if (mounted) setState(() => _status = doneText);
    });
  }

  String _mib(int bytes) => '${(bytes / 1048576).toStringAsFixed(1)} MiB';

  String _fmtSize(int bytes) => bytes >= 1073741824
      ? '${(bytes / 1073741824).toStringAsFixed(2)} GiB'
      : _mib(bytes);

  Widget _amountField({required String label}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: _sizeCtrl,
        enabled: !_busy,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  /// Current size, the amount to add (or exact total), unit, quick amounts and a live "new size" line.
  List<Widget> _sizeSection(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final current = _currentBytes;
    final target = _targetBytes;
    final added = _addedBytes;
    final over = _tooLarge;
    final invalid = target != null && current != null && target <= current;

    final preview = target == null
        ? null
        : (added != null && added > 0)
            ? l10n.vcToolsNewSizePreviewWithAdded(_fmtSize(target), _fmtSize(added))
            : l10n.vcToolsNewSizePreview(_fmtSize(target));

    return [
      ListTile(
        leading: Icon(Icons.straighten_rounded, color: cs.primary),
        title: Text(_isBitLockerExpand ? l10n.vcToolsFileSize : l10n.vcToolsCurrentSize),
        subtitle: _freeBytes != null ? Text(l10n.vcToolsFreeOnDevice(_fmtSize(_freeBytes!))) : null,
        trailing: _sizeLoading
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Text(current != null ? _fmtSize(current) : l10n.unknownValue,
                style: context.typography.titleMedium),
      ),
      if (_canGrowBy)
        SwitchListTile(
          value: _exact,
          onChanged: _busy
              ? null
              : (v) => setState(() {
                    _exact = v;
                    _sizeCtrl.clear();
                  }),
          title: Text(l10n.vcToolsSetExactTotalInstead),
        ),
      if (_isBitLockerExpand && current != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            l10n.vcToolsBitLockerDiskImageSizeHint,
            style: context.typography.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _amountField(label: _exactMode ? l10n.vcToolsNewTotalSize : l10n.vcToolsAddSize)),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('MiB')),
                  ButtonSegment(value: true, label: Text('GiB')),
                ],
                selected: {_unitGiB},
                showSelectedIcon: false,
                onSelectionChanged: _busy ? null : (s) => setState(() => _unitGiB = s.first),
              ),
            ),
          ],
        ),
      ),
      if (!_exactMode && current != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final gib in const [1, 5, 10])
                ActionChip(
                  label: Text(l10n.vcToolsQuickAddGiB(gib.toString())),
                  onPressed: _busy ? null : () => _setAmountBytes(gib * 1073741824),
                ),
              ActionChip(
                label: Text(l10n.vcToolsDoubleSize),
                onPressed: _busy ? null : () => _setAmountBytes(current),
              ),
            ],
          ),
        ),
      if (preview != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            invalid
                ? l10n.vcToolsSizeMustExceedCurrent
                : over
                    ? '$preview\n${l10n.vcToolsInsufficientFreeSpace}'
                    : preview,
            style: context.typography.bodyMedium?.copyWith(
              color: (invalid || over) ? cs.error : cs.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        )
     
       
    ];
  }

  Widget _passwordField({
    required TextEditingController controller,
    required String label,
    bool limitBytes = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        enabled: !_busy,
        obscureText: !_showPassword,
        autocorrect: false,
        enableSuggestions: false,
        inputFormatters: limitBytes ? const [Utf8ByteLimitingFormatter(128)] : null,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: IconButton(
            icon: Icon(_showPassword ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => setState(() => _showPassword = !_showPassword),
          ),
        ),
      ),
    );
  }

  Widget _numberField({required TextEditingController controller, required String label}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        enabled: !_busy,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      ),
    );
  }

  Widget _feedbackBanner(BuildContext context, {required String message, required bool error}) {
    final cs = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: error ? cs.errorContainer : cs.primaryContainer,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(error ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
              color: error ? cs.onErrorContainer : cs.onPrimaryContainer, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(
              color: error ? cs.onErrorContainer : cs.onPrimaryContainer,
            )),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = context.colors;
    final isWide = context.screen.useWideLayout;
    final title = _isExpand ? l10n.vcToolsExpandAction : l10n.toolHiddenInExistingTitle;
    final host = _host;
    final hiddenReady = host != null && host.maxHiddenBytes > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        elevation: 0,
        backgroundColor: cs.surfaceContainerHigh,
      ),
      body: Column(
        children: [
          if (_busy) const LinearProgressIndicator(minHeight: 3),
          if (_error != null) _feedbackBanner(context, message: _error!, error: true),
          if (_status != null) _feedbackBanner(context, message: _status!, error: false),
          Expanded(
            child: ListView(
              padding: isWide
                  ? const EdgeInsets.symmetric(horizontal: 24, vertical: 16)
                  : AppSpacing.pagePadding,
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline_rounded, color: cs.primary),
                              const SizedBox(width: 12),
                              Expanded(child: Text(
                                _isBitLockerExpand
                                    ? l10n.bitlockerToolsExpandNote
                                    : _isLuksExpand
                                        ? l10n.luksToolsExpandNote
                                        : (_isExpand ? l10n.vcToolsExpandNote : l10n.vcToolsHiddenNote),
                                style: context.typography.bodyMedium,
                              )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        SectionHeader(l10n.vcToolsContainerSectionHeader),
                        SectionCard(children: [
                          ListTile(
                            onTap: _busy ? null : _pickContainer,
                            leading: Icon(Icons.folder_open_rounded, color: cs.primary),
                            title: Text(_target?.displayName ?? l10n.vcToolsNoContainer,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                          ),
                        ]),
                        if (_isExpand && _target != null) ...[
                          const SizedBox(height: 8),
                          SectionCard(children: [
                            OptionPickerTile<_ExpandFormat>(
                              label: l10n.formatLabel,
                              value: _format,
                              prefixIcon: Icons.lock_outline_rounded,
                              subtitle: _probing ? l10n.vcToolsDetectingFormat : _formatHint,
                              options: const [
                                SelectOption<_ExpandFormat>(value: _ExpandFormat.veracrypt, label: 'VeraCrypt'),
                                SelectOption<_ExpandFormat>(value: _ExpandFormat.luks, label: 'LUKS (LUKS1 / LUKS2)'),
                                SelectOption<_ExpandFormat>(value: _ExpandFormat.bitlocker, label: 'BitLocker'),
                              ],
                              onChanged: _setFormat,
                              enabled: !_busy && !_probing,
                            ),
                          ]),
                        ],
                        SectionHeader(l10n.vcToolsCredentialsSectionHeader),
                        SectionCard(children: [
                          Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, _isBitLockerExpand ? 12 : 4),
                            child: _passwordField(
                              controller: _passwordCtrl,
                              label: _isBitLockerExpand ? l10n.bitlockerToolsPasswordLabel : l10n.vcToolsPasswordLabel,
                            )),
                          // BitLocker: password or recovery key only -- no PIM, no keyfiles.
                          if (!_isLuksExpand && !_isBitLockerExpand)
                            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: _numberField(controller: _pimCtrl, label: l10n.vcToolsPimLabel)),
                          if (!_isBitLockerExpand)
                            Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                              child: KeyfilesPicker(
                                keyfiles: _keyfiles,
                                picking: _pickingKeyfiles,
                                onPick: () => _pickKeyfiles(hidden: false),
                                onRemove: (k) => setState(() {
                                  _keyfiles = _keyfiles.where((x) => x.uri != k.uri).toList();
                                  _host = null;
                                }),
                                enabled: !_busy,
                                addEnabled: !_isLuksExpand || _keyfiles.isEmpty,
                              )),
                        ]),
                        const SizedBox(height: 8),
                        if (_isExpand) ...[
                          SectionHeader(l10n.vcToolsVolumeOptionsSectionHeader),
                          SectionCard(children: [
                            ..._sizeSection(context),
                            SwitchListTile(
                              value: _initFree,
                              onChanged: _busy ? null : (v) => setState(() => _initFree = v),
                              title: Text(l10n.vcToolsInitFreeSpace),
                              subtitle: Text(l10n.vcToolsInitFreeSpaceHint),
                            ),
                            SwitchListTile(
                              value: _growFs,
                              onChanged: _busy ? null : (v) => setState(() => _growFs = v),
                              title: Text(l10n.vcToolsGrowFsToggle),
                              subtitle: Text(l10n.vcToolsGrowFsToggleHint),
                            ),
                          ]),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _busy ? null : _expand,
                            icon: const Icon(Icons.open_in_full_rounded),
                            label: Text(l10n.vcToolsExpandAction),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _growFileSystemOnly,
                            icon: const Icon(Icons.storage_rounded),
                            label: Text(l10n.vcToolsGrowFsOnlyAction),
                          ),
                        ] else ...[
                          const SizedBox(height: 16),
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _analyze,
                            icon: const Icon(Icons.analytics_outlined),
                            label: Text(l10n.vcToolsAnalyzeAction),
                          ),
                          if (host != null) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(AppRadius.lg),
                              ),
                              child: Row(children: [
                                Icon(hiddenReady ? Icons.check_circle_outline : Icons.info_outline,
                                    color: hiddenReady ? cs.primary : cs.onSurfaceVariant),
                                const SizedBox(width: 12),
                                Expanded(child: Text(hiddenReady
                                    ? '${l10n.vcToolsMaxHidden}: ${_mib(host.maxHiddenBytes)}'
                                    : l10n.vcToolsNoRoom)),
                              ]),
                            ),
                          ],
                          if (hiddenReady) ...[
                            SectionHeader(l10n.hiddenVolumeHeader),
                            SectionCard(children: [
                              Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                                child: _numberField(controller: _hiddenSizeCtrl, label: l10n.vcToolsHiddenSizeLabel)),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: _passwordField(controller: _hiddenPasswordCtrl,
                                  label: l10n.vcToolsHiddenPasswordLabel, limitBytes: true)),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: _passwordField(controller: _hiddenConfirmCtrl,
                                  label: l10n.vcToolsHiddenConfirmLabel, limitBytes: true)),
                              Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: _numberField(controller: _hiddenPimCtrl, label: l10n.vcToolsPimLabel)),
                              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                                child: KeyfilesPicker(
                                  keyfiles: _hiddenKeyfiles,
                                  picking: _pickingHiddenKeyfiles,
                                  onPick: () => _pickKeyfiles(hidden: true),
                                  onRemove: (k) => setState(() {
                                    _hiddenKeyfiles = _hiddenKeyfiles.where((x) => x.uri != k.uri).toList();
                                  }),
                                  enabled: !_busy,
                                )),
                              OptionPickerTile<int>(
                                label: l10n.encryptionAlgorithmLabel,
                                value: _hiddenCipherId,
                                prefixIcon: Icons.lock_rounded,
                                options: [for (final c in CipherAlgo.concrete)
                                  SelectOption<int>(value: c.id, label: c.label)],
                                onChanged: (v) => setState(() => _hiddenCipherId = v),
                                enabled: !_busy,
                              ),
                              OptionPickerTile<int>(
                                label: l10n.hashAlgorithmLabel,
                                value: _hiddenHashId,
                                prefixIcon: Icons.tag_rounded,
                                options: [for (final h in HashAlgo.concrete)
                                  SelectOption<int>(value: h.id, label: h.label)],
                                onChanged: (v) => setState(() => _hiddenHashId = v),
                                enabled: !_busy,
                              ),
                              OptionPickerTile<String>(
                                label: l10n.vcToolsHiddenFsLabel,
                                value: _hiddenFs,
                                prefixIcon: Icons.dns_rounded,
                                options: [for (final fs in _hiddenFileSystems)
                                  SelectOption<String>(value: fs, label: fs)],
                                onChanged: (v) => setState(() => _hiddenFs = v),
                                enabled: !_busy,
                              ),
                              SwitchListTile(
                                value: _quick,
                                onChanged: _busy ? null : (v) => setState(() => _quick = v),
                                title: Text(l10n.vcToolsQuickFormat),
                              ),
                            ]),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: _busy ? null : _createHidden,
                              icon: const Icon(Icons.add_to_drive_rounded),
                              label: Text(l10n.vcToolsCreateHiddenAction),
                            ),
                          ],
                        ],
                        const SizedBox(height: 24),
                      ],
                    ),
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
