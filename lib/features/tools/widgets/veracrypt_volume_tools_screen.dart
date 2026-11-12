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
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

/// The desktop-VeraCrypt volume operations that work on an existing container.
enum VeraCryptVolumeTool { expand, expandLuks, addHidden }

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

  bool get _isExpand => widget.tool != VeraCryptVolumeTool.addHidden;
  bool get _isLuksExpand => widget.tool == VeraCryptVolumeTool.expandLuks;

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
    final newSize = _bytesFromMiB(_sizeCtrl);
    if (newSize == null) {
      setState(() => _error = context.l10n.vcToolsInvalidSize);
      return;
    }
    final doneText = context.l10n.vcToolsExpandDone;
    await _guard(() async {
      final fs = _isLuksExpand
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
      setState(() => _status = fsText.isEmpty ? doneText : '$doneText\n$fsText');
    });
  }

  Future<void> _growFileSystemOnly() async {
    if (!_validateCommon()) return;
    await _guard(() async {
      final fs = _isLuksExpand
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
    final title = _isLuksExpand
        ? l10n.toolExpandLuksVolumeTitle
        : (_isExpand ? l10n.toolExpandVolumeTitle : l10n.toolHiddenInExistingTitle);
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
                                _isLuksExpand
                                    ? l10n.luksToolsExpandNote
                                    : (_isExpand ? l10n.vcToolsExpandNote : l10n.vcToolsHiddenNote),
                                style: context.typography.bodyMedium,
                              )),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        const SectionHeader('Container'),
                        SectionCard(children: [
                          ListTile(
                            onTap: _busy ? null : _pickContainer,
                            leading: Icon(Icons.folder_open_rounded, color: cs.primary),
                            title: Text(_target?.displayName ?? l10n.vcToolsNoContainer,
                                maxLines: 2, overflow: TextOverflow.ellipsis),
                            trailing: Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
                          ),
                        ]),
                        const SectionHeader('Credentials'),
                        SectionCard(children: [
                          Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: _passwordField(controller: _passwordCtrl, label: l10n.vcToolsPasswordLabel)),
                          if (!_isLuksExpand)
                            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: _numberField(controller: _pimCtrl, label: l10n.vcToolsPimLabel)),
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
                          const SectionHeader('Volume options'),
                          SectionCard(children: [
                            Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                              child: _numberField(controller: _sizeCtrl, label: l10n.vcToolsNewSizeLabel)),
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
                            const SectionHeader('Hidden volume'),
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
