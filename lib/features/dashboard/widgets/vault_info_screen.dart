import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/filesystem/file_size.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';
import 'package:vaultexplorer/features/dashboard/widgets/vault_info_controller.dart';

/// Vault Settings' "Vault Information" screen: read-only technical details
/// about how the vault was created (cipher, format version, etc.), one
/// layout per container format.
///
/// Reachable even when [uri] isn't currently unlocked (Vault Settings
/// itself doesn't require an active session) — in that case the platform
/// call throws a `NOT_MOUNTED` PlatformException and this screen shows
/// an "unlock required" state instead of the details. See
/// ContainerEngine.getVaultInfo()'s doc comment (Kotlin side) for exactly
/// which map keys each format returns.
class VaultInfoScreen extends ConsumerWidget {
  final String uri;
  final String containerFormat;

  const VaultInfoScreen({
    super.key,
    required this.uri,
    required this.containerFormat,
  });

  ContainerFormat get _format => ContainerFormat.fromWire(containerFormat);

  /// [uri] as shown to the user: percent-decoded for readability (it's
  /// normally an opaque SAF `content://` URI), or the device name alone
  /// for a `usb:<deviceName>` synthetic URI (see usb_unlock_sheet.dart
  /// for where that scheme is constructed -- USB volumes aren't backed by
  /// SAF, so there's no real URI to decode).
  String get _location {
    if (uri.startsWith('usb:')) return uri.substring('usb:'.length);
    try {
      return Uri.decodeFull(uri);
    } catch (_) {
      return uri;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
                // always shown, independent of the controller's load state.
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
                Expanded(child: _buildBody(context, ref)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref) {
    final controllerState = ref.watch(vaultInfoProvider(uri));
    switch (controllerState.loadState) {
      case VaultInfoLoadState.loading:
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: CircularProgressIndicator(),
          ),
        );
      case VaultInfoLoadState.unlockRequired:
        return AppEmptyState(
          icon: Icons.lock_outline_rounded,
          title: context.l10n.vaultInfoRequiresUnlockTitle,
          message: context.l10n.vaultInfoRequiresUnlockMessage,
        );
      case VaultInfoLoadState.error:
        return AppEmptyState(
          icon: Icons.error_outline_rounded,
          title: context.l10n.vaultInfoLoadFailedTitle,
          message: context.l10n.vaultInfoLoadFailedMessage,
          actionLabel: context.l10n.retryButtonLabel,
          actionIcon: Icons.refresh_rounded,
          onAction: () => ref.read(vaultInfoProvider(uri).notifier).retry(),
        );
      case VaultInfoLoadState.loaded:
        final info = controllerState.info;
        final rows = _buildRows(context, info);
        if (rows.isEmpty) {
          // Format we don't recognize (e.g. a bare directory_vault, or a
          // future format the sheet doesn't special-case yet) — still show
          // whatever the common fields say rather than a blank screen.
          rows.addAll(_genericRows(context, info));
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

  List<Widget> _buildRows(BuildContext context, Map<String, dynamic> info) {
    if (_format.isBitlocker) return _bitlockerRows(context, info);
    if (_format.isLuks) return _luksRows(context, info);
    if (_format.isCryptomator) return _cryptomatorRows(context, info);
    if (_format.isGocryptfs) return _gocryptfsRows(context, info);
    if (_format.isCryfs) return _cryfsRows(context, info);
    if (_format == ContainerFormat.veracrypt) return _veracryptRows(context, info);
    return const [];
  }

  String _yesNo(BuildContext context, bool value) =>
      value ? context.l10n.vaultInfoYesValue : context.l10n.vaultInfoNoValue;

  int? _int(Map<String, dynamic> info, String key) => (info[key] as num?)?.toInt();
  bool? _bool(Map<String, dynamic> info, String key) => info[key] as bool?;
  String? _str(Map<String, dynamic> info, String key) => info[key] as String?;

  List<Widget> _veracryptRows(BuildContext context, Map<String, dynamic> info) {
    final cipherId = _int(info, 'cipherId');
    final hashId = _int(info, 'hashId');
    final hidden = _bool(info, 'hiddenVolume');
    final size = _int(info, 'volumeSizeBytes');
    final fileSystem = _str(info, 'fileSystem');
    final readOnly = _bool(info, 'readOnly') ?? false;
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

  List<Widget> _luksRows(BuildContext context, Map<String, dynamic> info) {
    final version = _int(info, 'luksVersion');
    final cipherId = _int(info, 'cipherId');
    final sectorSize = _int(info, 'sectorSize');
    final size = _int(info, 'volumeSizeBytes');
    final fileSystem = _str(info, 'fileSystem');
    final readOnly = _bool(info, 'readOnly') ?? false;
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
  
  List<Widget> _bitlockerRows(BuildContext context, Map<String, dynamic> info) {
    final size = _int(info, 'volumeSizeBytes');
    final fileSystem = _str(info, 'fileSystem');
    final readOnly = _bool(info, 'readOnly') ?? false;
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

  List<Widget> _cryptomatorRows(BuildContext context, Map<String, dynamic> info) {
    final vaultFormat = _int(info, 'vaultFormat');
    final cipherCombo = _str(info, 'cipherCombo');
    final threshold = _int(info, 'shorteningThreshold');
    final readOnly = _bool(info, 'readOnly') ?? false;
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

  List<Widget> _gocryptfsRows(BuildContext context, Map<String, dynamic> info) {
    final version = _int(info, 'formatVersion');
    final cipher = _str(info, 'cipher');
    final plaintextNames = _bool(info, 'plaintextNames');
    final readOnly = _bool(info, 'readOnly') ?? false;
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

  List<Widget> _cryfsRows(BuildContext context, Map<String, dynamic> info) {
    final formatVersion = _str(info, 'formatVersion');
    final blockCipher = _str(info, 'blockCipherName');
    final createdWith = _str(info, 'createdWithVersion');
    final lastOpenedWith = _str(info, 'lastOpenedWithVersion');
    final blockSize = _int(info, 'blockSizeBytes');
    final readOnly = _bool(info, 'readOnly') ?? false;
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

  List<Widget> _genericRows(BuildContext context, Map<String, dynamic> info) {
    final readOnly = _bool(info, 'readOnly') ?? false;
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