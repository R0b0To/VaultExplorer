import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/file_size.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

enum _VaultInfoLoadState { loading, unlockRequired, error, loaded }

/// Vault Settings' "Vault Information" screen: read-only technical details
/// about how the vault was created (cipher, format version, etc.), one
/// layout per container format.
///
/// Reachable even when [uri] isn't currently unlocked (Vault Settings
/// itself doesn't require an active session) — in that case the platform
/// call throws a `NOT_MOUNTED` [PlatformException] and this screen shows
/// an "unlock required" state instead of the details. See
/// ContainerEngine.getVaultInfo()'s doc comment (Kotlin side) for exactly
/// which map keys each format returns.
class VaultInfoScreen extends StatefulWidget {
  final String uri;
  final String containerFormat;

  const VaultInfoScreen({
    super.key,
    required this.uri,
    required this.containerFormat,
  });

  @override
  State<VaultInfoScreen> createState() => _VaultInfoScreenState();
}

class _VaultInfoScreenState extends State<VaultInfoScreen> {
  _VaultInfoLoadState _state = _VaultInfoLoadState.loading;
  Map<String, dynamic> _info = const {};

  ContainerFormat get _format => ContainerFormat.fromWire(widget.containerFormat);

  /// [widget.uri] as shown to the user: percent-decoded for readability
  /// (it's normally an opaque SAF `content://` URI), or the device name
  /// alone for a `usb:<deviceName>` synthetic URI (see usb_unlock_sheet.dart
  /// for where that scheme is constructed -- USB volumes aren't backed by
  /// SAF, so there's no real URI to decode).
  String get _location {
    final uri = widget.uri;
    if (uri.startsWith('usb:')) return uri.substring('usb:'.length);
    try {
      return Uri.decodeFull(uri);
    } catch (_) {
      return uri;
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _state = _VaultInfoLoadState.loading);
    try {
      final info = await vaultExplorerApi.getVaultInfo(widget.uri);
      if (!mounted) return;
      setState(() {
        _info = info ?? const {};
        _state = _VaultInfoLoadState.loaded;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() {
        _state = e.code == 'NOT_MOUNTED'
            ? _VaultInfoLoadState.unlockRequired
            : _VaultInfoLoadState.error;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _VaultInfoLoadState.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final wideLayout = context.screen.useWideLayout;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.l10n.vaultInformationSectionHeader,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              _format.label.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: cs.primary,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: wideLayout ? 1000 : 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // The vault's location doesn't need an unlocked session --
                // it's just the URI this screen was opened with -- so it's
                // always shown, independent of _state below.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SectionCard(
                    children: [
                      _LocationRow(
                        label: context.l10n.vaultInfoLocationLabel,
                        value: _location,
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _VaultInfoLoadState.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      case _VaultInfoLoadState.unlockRequired:
        return AppEmptyState(
          icon: Icons.lock_outline_rounded,
          title: context.l10n.vaultInfoRequiresUnlockTitle,
          message: context.l10n.vaultInfoRequiresUnlockMessage,
        );
      case _VaultInfoLoadState.error:
        return AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: context.l10n.vaultInfoLoadFailedTitle,
          message: context.l10n.vaultInfoLoadFailedMessage,
          actionLabel: context.l10n.retryButtonLabel,
          actionIcon: Icons.refresh_rounded,
          onAction: _load,
        );
      case _VaultInfoLoadState.loaded:
        final rows = _buildRows(context);
        if (rows.isEmpty) {
          // Format we don't recognize (e.g. a bare directory_vault, or a
          // future format the sheet doesn't special-case yet) — still show
          // whatever the common fields say rather than a blank screen.
          rows.addAll(_genericRows(context));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        );
    }
  }

  List<Widget> _buildRows(BuildContext context) {
    if (_format.isBitlocker) return _bitlockerRows(context);
    if (_format.isLuks) return _luksRows(context);
    if (_format.isCryptomator) return _cryptomatorRows(context);
    if (_format.isGocryptfs) return _gocryptfsRows(context);
    if (_format.isCryfs) return _cryfsRows(context);
    if (_format == ContainerFormat.veracrypt) return _veracryptRows(context);
    return const [];
  }

  String _yesNo(BuildContext context, bool value) =>
      value ? context.l10n.vaultInfoYesValue : context.l10n.vaultInfoNoValue;

  int? _int(String key) => (_info[key] as num?)?.toInt();
  bool? _bool(String key) => _info[key] as bool?;
  String? _str(String key) => _info[key] as String?;

  List<Widget> _veracryptRows(BuildContext context) {
    final cipherId = _int('cipherId');
    final hashId = _int('hashId');
    final hidden = _bool('hiddenVolume');
    final size = _int('volumeSizeBytes');
    final fileSystem = _str('fileSystem');
    final readOnly = _bool('readOnly') ?? false;
    return [
      SectionCard(children: [
        if (cipherId != null)
          _InfoRow(
            label: context.l10n.encryptionAlgorithmLabel,
            value: CipherAlgo.nameFor(cipherId),
          ),
        if (hashId != null)
          _InfoRow(
            label: context.l10n.hashAlgorithmLabel,
            value: HashAlgo.nameFor(hashId),
          ),
        if (fileSystem != null)
          _InfoRow(
            label: context.l10n.vaultInfoFileSystemLabel,
            value: fileSystem,
          ),
        if (hidden != null)
          _InfoRow(
            label: context.l10n.vaultInfoHiddenVolumeLabel,
            value: _yesNo(context, hidden),
          ),
        if (size != null)
          _InfoRow(
            label: context.l10n.vaultInfoVolumeSizeLabel,
            value: formatByteCount(size),
          ),
        _InfoRow(
          label: context.l10n.vaultInfoReadOnlyLabel,
          value: _yesNo(context, readOnly),
        ),
      ]),
    ];
  }

  List<Widget> _luksRows(BuildContext context) {
    final version = _int('luksVersion');
    final cipherId = _int('cipherId');
    final sectorSize = _int('sectorSize');
    final size = _int('volumeSizeBytes');
    final fileSystem = _str('fileSystem');
    final readOnly = _bool('readOnly') ?? false;
    return [
      SectionCard(children: [
        if (version != null)
          _InfoRow(label: context.l10n.vaultInfoLuksVersionLabel, value: 'LUKS$version'),
        if (cipherId != null)
          _InfoRow(
            label: context.l10n.encryptionAlgorithmLabel,
            value: CipherAlgo.nameFor(cipherId),
          ),
        if (fileSystem != null)
          _InfoRow(
            label: context.l10n.vaultInfoFileSystemLabel,
            value: fileSystem,
          ),
        if (sectorSize != null)
          _InfoRow(
            label: context.l10n.vaultInfoSectorSizeLabel,
            value: formatByteCount(sectorSize),
          ),
        if (size != null)
          _InfoRow(
            label: context.l10n.vaultInfoVolumeSizeLabel,
            value: formatByteCount(size),
          ),
        _InfoRow(
          label: context.l10n.vaultInfoReadOnlyLabel,
          value: _yesNo(context, readOnly),
        ),
      ]),
    ];
  }

  List<Widget> _bitlockerRows(BuildContext context) {
    final size = _int('volumeSizeBytes');
    final fileSystem = _str('fileSystem');
    final readOnly = _bool('readOnly') ?? false;
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return [
      SectionCard(children: [
        if (fileSystem != null)
          _InfoRow(
            label: context.l10n.vaultInfoFileSystemLabel,
            value: fileSystem,
          ),
        if (size != null)
          _InfoRow(
            label: context.l10n.vaultInfoVolumeSizeLabel,
            value: formatByteCount(size),
          ),
        _InfoRow(
          label: context.l10n.vaultInfoReadOnlyLabel,
          value: _yesNo(context, readOnly),
        ),
      ]),
      const SizedBox(height: 12),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          context.l10n.vaultInfoBitlockerNote,
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.3),
        ),
      ),
    ];
  }

  List<Widget> _cryptomatorRows(BuildContext context) {
    final vaultFormat = _int('vaultFormat');
    final cipherCombo = _str('cipherCombo');
    final threshold = _int('shorteningThreshold');
    final readOnly = _bool('readOnly') ?? false;
    return [
      SectionCard(children: [
        if (vaultFormat != null)
          _InfoRow(label: context.l10n.vaultInfoVaultFormatLabel, value: '$vaultFormat'),
        if (cipherCombo != null)
          _InfoRow(label: context.l10n.vaultInfoCipherComboLabel, value: cipherCombo),
        if (threshold != null)
          _InfoRow(
            label: context.l10n.vaultInfoShorteningThresholdLabel,
            value: '$threshold',
          ),
        _InfoRow(
          label: context.l10n.vaultInfoReadOnlyLabel,
          value: _yesNo(context, readOnly),
        ),
      ]),
    ];
  }

  List<Widget> _gocryptfsRows(BuildContext context) {
    final version = _int('formatVersion');
    final cipher = _str('cipher');
    final plaintextNames = _bool('plaintextNames');
    final readOnly = _bool('readOnly') ?? false;
    return [
      SectionCard(children: [
        if (version != null)
          _InfoRow(label: context.l10n.vaultInfoFormatVersionLabel, value: '$version'),
        if (cipher != null)
          _InfoRow(label: context.l10n.vaultInfoContentCipherLabel, value: cipher),
        if (plaintextNames != null)
          _InfoRow(
            label: context.l10n.vaultInfoFilenameEncryptionLabel,
            value: plaintextNames
                ? context.l10n.vaultInfoPlaintextNamesValue
                : context.l10n.vaultInfoEncryptedNamesValue,
          ),
        _InfoRow(
          label: context.l10n.vaultInfoReadOnlyLabel,
          value: _yesNo(context, readOnly),
        ),
      ]),
    ];
  }

  List<Widget> _cryfsRows(BuildContext context) {
    final formatVersion = _str('formatVersion');
    final blockCipher = _str('blockCipherName');
    final createdWith = _str('createdWithVersion');
    final lastOpenedWith = _str('lastOpenedWithVersion');
    final blockSize = _int('blockSizeBytes');
    final readOnly = _bool('readOnly') ?? false;
    return [
      SectionCard(children: [
        if (formatVersion != null)
          _InfoRow(label: context.l10n.vaultInfoFormatVersionLabel, value: formatVersion),
        if (blockCipher != null)
          _InfoRow(label: context.l10n.vaultInfoBlockCipherLabel, value: blockCipher),
        if (blockSize != null)
          _InfoRow(
            label: context.l10n.vaultInfoBlockSizeLabel,
            value: formatByteCount(blockSize),
          ),
        if (createdWith != null)
          _InfoRow(label: context.l10n.vaultInfoCreatedWithVersionLabel, value: createdWith),
        if (lastOpenedWith != null)
          _InfoRow(
            label: context.l10n.vaultInfoLastOpenedWithVersionLabel,
            value: lastOpenedWith,
          ),
        _InfoRow(
          label: context.l10n.vaultInfoReadOnlyLabel,
          value: _yesNo(context, readOnly),
        ),
      ]),
    ];
  }

  List<Widget> _genericRows(BuildContext context) {
    final readOnly = _bool('readOnly') ?? false;
    return [
      SectionCard(children: [
        _InfoRow(
          label: context.l10n.vaultInfoReadOnlyLabel,
          value: _yesNo(context, readOnly),
        ),
      ]),
    ];
  }
}

class _LocationRow extends StatelessWidget {
  final String label;
  final String value;
  const _LocationRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: textTheme.bodyMedium),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      title: Text(label, style: textTheme.bodyMedium),
      trailing: Text(
        value,
        style: textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}