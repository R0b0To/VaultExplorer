import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/api/vault_engine_types.dart';
import 'package:vaultexplorer/core/api/veracrypt_tools_api.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/widgets/crypto_forms/keyfiles_picker.dart';
import 'package:vaultexplorer/core/widgets/inputs/option_picker_tile.dart';
import 'package:vaultexplorer/core/widgets/inputs/utf8_byte_limit_formatter.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

/// The desktop-VeraCrypt volume operations that work on an existing container.
enum VeraCryptVolumeTool { expand, addHidden }

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

  // expand
  final _sizeCtrl = TextEditingController();
  bool _initFree = true;
  bool _growFs = true;

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

  bool get _isExpand => widget.tool == VeraCryptVolumeTool.expand;

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
        final merged = [...current, ...picked.where((p) => !current.any((c) => c.uri == p.uri))];
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
      FileSystemGrowResult.failed => l10n.vcToolsFsFailed,
      FileSystemGrowResult.notRun => '',
    };
  }

  Future<void> _expand() async {
    if (!_validateCommon()) return;
    final newSize = _bytesFromMiB(_sizeCtrl);
    if (newSize == null) {
      setState(() => _error = context.l10n.vcToolsInvalidSize);
      return;
    }
    final doneText = context.l10n.vcToolsExpandDone;
    await _guard(() async {
      final fs = await _api.expandContainer(
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
      setState(() => _status = fsText.isEmpty ? doneText : '$doneText\n$fsText');
    });
  }

  Future<void> _growFileSystemOnly() async {
    if (!_validateCommon()) return;
    await _guard(() async {
      final fs = await _api.growFileSystem(
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final title = _isExpand ? l10n.toolExpandVolumeTitle : l10n.toolHiddenInExistingTitle;
    final host = _host;
    final hiddenReady = host != null && host.maxHiddenBytes > 0;

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            _isExpand ? l10n.vcToolsExpandNote : l10n.vcToolsHiddenNote,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_open_rounded),
            title: Text(_target?.displayName ?? l10n.vcToolsNoContainer),
            trailing: OutlinedButton(
              onPressed: _busy ? null : _pickContainer,
              child: Text(l10n.vcToolsPickContainer),
            ),
          ),
          _passwordField(controller: _passwordCtrl, label: l10n.vcToolsPasswordLabel),
          _numberField(controller: _pimCtrl, label: l10n.vcToolsPimLabel),
          KeyfilesPicker(
            keyfiles: _keyfiles,
            picking: _pickingKeyfiles,
            onPick: () => _pickKeyfiles(hidden: false),
            onRemove: (k) => setState(() {
              _keyfiles = _keyfiles.where((x) => x.uri != k.uri).toList();
              _host = null;
            }),
            enabled: !_busy,
          ),
          const SizedBox(height: 8),
          if (_isExpand) ...[
            _numberField(controller: _sizeCtrl, label: l10n.vcToolsNewSizeLabel),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _initFree,
              onChanged: _busy ? null : (v) => setState(() => _initFree = v),
              title: Text(l10n.vcToolsInitFreeSpace),
              subtitle: Text(l10n.vcToolsInitFreeSpaceHint),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _growFs,
              onChanged: _busy ? null : (v) => setState(() => _growFs = v),
              title: Text(l10n.vcToolsGrowFsToggle),
              subtitle: Text(l10n.vcToolsGrowFsToggleHint),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _busy ? null : _expand,
              child: Text(l10n.vcToolsExpandAction),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _busy ? null : _growFileSystemOnly,
              child: Text(l10n.vcToolsGrowFsOnlyAction),
            ),
          ] else ...[
            OutlinedButton(
              onPressed: _busy ? null : _analyze,
              child: Text(l10n.vcToolsAnalyzeAction),
            ),
            if (host != null) ...[
              const SizedBox(height: 8),
              Text(
                hiddenReady
                    ? '${l10n.vcToolsMaxHidden}: ${_mib(host.maxHiddenBytes)}'
                    : l10n.vcToolsNoRoom,
              ),
            ],
            if (hiddenReady) ...[
              const SizedBox(height: 12),
              _numberField(controller: _hiddenSizeCtrl, label: l10n.vcToolsHiddenSizeLabel),
              _passwordField(
                controller: _hiddenPasswordCtrl,
                label: l10n.vcToolsHiddenPasswordLabel,
                limitBytes: true,
              ),
              _passwordField(
                controller: _hiddenConfirmCtrl,
                label: l10n.vcToolsHiddenConfirmLabel,
                limitBytes: true,
              ),
              _numberField(controller: _hiddenPimCtrl, label: l10n.vcToolsPimLabel),
              KeyfilesPicker(
                keyfiles: _hiddenKeyfiles,
                picking: _pickingHiddenKeyfiles,
                onPick: () => _pickKeyfiles(hidden: true),
                onRemove: (k) => setState(() {
                  _hiddenKeyfiles = _hiddenKeyfiles.where((x) => x.uri != k.uri).toList();
                }),
                enabled: !_busy,
              ),
              OptionPickerTile<int>(
                label: l10n.encryptionAlgorithmLabel,
                value: _hiddenCipherId,
                prefixIcon: Icons.lock_rounded,
                options: [
                  for (final c in CipherAlgo.concrete) SelectOption<int>(value: c.id, label: c.label),
                ],
                onChanged: (v) => setState(() => _hiddenCipherId = v),
                enabled: !_busy,
              ),
              OptionPickerTile<int>(
                label: l10n.hashAlgorithmLabel,
                value: _hiddenHashId,
                prefixIcon: Icons.tag_rounded,
                options: [
                  for (final h in HashAlgo.concrete) SelectOption<int>(value: h.id, label: h.label),
                ],
                onChanged: (v) => setState(() => _hiddenHashId = v),
                enabled: !_busy,
              ),
              OptionPickerTile<String>(
                label: l10n.vcToolsHiddenFsLabel,
                value: _hiddenFs,
                prefixIcon: Icons.dns_rounded,
                options: [
                  for (final fs in _hiddenFileSystems) SelectOption<String>(value: fs, label: fs),
                ],
                onChanged: (v) => setState(() => _hiddenFs = v),
                enabled: !_busy,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _quick,
                onChanged: _busy ? null : (v) => setState(() => _quick = v),
                title: Text(l10n.vcToolsQuickFormat),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _busy ? null : _createHidden,
                child: Text(l10n.vcToolsCreateHiddenAction),
              ),
            ],
          ],
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error)),
          ],
          if (_status != null) ...[
            const SizedBox(height: 16),
            Text(_status!, style: TextStyle(color: scheme.primary)),
          ],
        ],
      ),
    );
  }
}
