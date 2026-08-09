import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/utils/validation_utils.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';

/// Mounts a chunked VeraCrypt or LUKS vault through VaultSync Bridge.
///
/// The screen deliberately keeps its credential surface small: cloud mounts
/// use the normal password/PIM flow, without USB's reconnection or local
/// biometric/pattern flows. The Bridge owns account authentication while this
/// app continues to own the container password and decrypted data.
class CloudUnlockSheet extends StatefulWidget {
  final void Function(MountedContainer container, {ContainerRecord? record})
  onMounted;
  final bool documentProvider;
  final List<String> autoMountFolders;
  final ContainerRecord? existingRecord;
  final String? prefillPassword;
  final List<String> mountedUris;

  const CloudUnlockSheet({
    super.key,
    required this.onMounted,
    this.documentProvider = false,
    this.autoMountFolders = const [],
    this.existingRecord,
    this.prefillPassword,
    this.mountedUris = const [],
  });

  @override
  State<CloudUnlockSheet> createState() => _CloudUnlockSheetState();
}

class _CloudUnlockSheetState extends State<CloudUnlockSheet> {
  static const _bridgeReleasesUrl =
      'https://github.com/R0b0To/VaultSync-Bridge/releases';

  final _passwordCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();

  List<CloudAccount> _accounts = const [];
  List<RemoteVault> _vaults = const [];
  CloudAccount? _selectedAccount;
  RemoteVault? _selectedVault;
  String? _directFolderUri;
  bool _loadingBridge = true;
  bool _loadingVaults = false;
  bool _unlocking = false;
  bool _obscure = true;
  bool _readOnly = false;
  bool _rememberVault = false;
  bool _bridgeAvailable = false;
  String? _bridgeReason;
  String? _error;
  int _cipherId = 255;
  int _hashId = 255;

  _CloudTarget? get _savedTarget =>
      _CloudTarget.tryParse(widget.existingRecord?.uri);

  bool get _isLuks =>
      _selectedVault?.format.toLowerCase().contains('luks') ?? false;

  bool get _isFolderVault => switch (_selectedVault?.format) {
    'cryptomator' || 'gocryptfs' || 'cryfs' => true,
    _ => false,
  };

  bool get _isBusy => _loadingBridge || _loadingVaults || _unlocking;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.text = widget.prefillPassword ?? '';
    final record = widget.existingRecord;
    if (record != null) {
      _readOnly = record.readOnly;
      _cipherId = record.cipherId;
      _hashId = record.hashId;
    }
    _loadBridge();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBridge() async {
    if (mounted) {
      setState(() {
        _loadingBridge = true;
        _error = null;
      });
    }

    try {
      final status = await vaultExplorerApi.checkCloudBridgeAvailable();
      if (!status.available) {
        if (mounted) {
          setState(() {
            _bridgeAvailable = false;
            _bridgeReason = status.reason;
            _accounts = const [];
            _vaults = const [];
            _selectedAccount = null;
            _selectedVault = null;
            _directFolderUri = null;
          });
        }
        return;
      }

      final accounts = await vaultExplorerApi.listCloudAccounts();
      final savedTarget = _savedTarget;
      CloudAccount? selected;
      for (final account in accounts) {
        if (account.accountId == savedTarget?.accountId) {
          selected = account;
          break;
        }
      }
      selected ??= accounts.isEmpty ? null : accounts.first;

      if (!mounted) return;
      setState(() {
        _bridgeAvailable = true;
        _bridgeReason = null;
        _accounts = accounts;
        _selectedAccount = selected;
        _vaults = const [];
        _selectedVault = null;
        _directFolderUri = null;
      });
      if (selected != null) {
        await _loadVaults(
          selected,
          preferredRemotePath: savedTarget?.remotePath,
        );
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _bridgeAvailable = false;
          _bridgeReason = 'disconnected';
          _error = e.message ?? 'Could not connect to VaultSync Bridge.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _bridgeAvailable = false;
          _bridgeReason = 'disconnected';
          _error = 'Could not connect to VaultSync Bridge.';
        });
      }
    } finally {
      if (mounted) setState(() => _loadingBridge = false);
    }
  }

  Future<void> _loadVaults(
    CloudAccount account, {
    String? preferredRemotePath,
  }) async {
    setState(() {
      _selectedAccount = account;
      _selectedVault = null;
      _vaults = const [];
      _loadingVaults = true;
      _directFolderUri = null;
      _error = null;
    });

    try {
      final vaults = await vaultExplorerApi.discoverRemoteVaults(
        account.accountId,
      );
      if (!mounted || _selectedAccount?.accountId != account.accountId) return;

      RemoteVault? selected;
      for (final vault in vaults) {
        if (vault.remotePath == preferredRemotePath) {
          selected = vault;
          break;
        }
      }
      setState(() {
        _vaults = vaults;
        _selectedVault = selected;
        if (preferredRemotePath != null && selected == null) {
          _error =
              'The saved cloud vault is no longer available in this account.';
        }
      });
    } on PlatformException catch (e) {
      if (mounted && _selectedAccount?.accountId == account.accountId) {
        setState(
          () => _error = e.message ?? 'Could not discover cloud vaults.',
        );
      }
    } catch (_) {
      if (mounted && _selectedAccount?.accountId == account.accountId) {
        setState(() => _error = 'Could not discover cloud vaults.');
      }
    } finally {
      if (mounted && _selectedAccount?.accountId == account.accountId) {
        setState(() => _loadingVaults = false);
      }
    }
  }

  bool _isAlreadyMounted(RemoteVault vault) {
    final directFolderUri = _directFolderUri;
    if (directFolderUri != null && identical(vault, _selectedVault)) {
      return widget.mountedUris.contains(directFolderUri);
    }
    return widget.mountedUris.any((uri) {
      final target = _CloudTarget.tryParse(uri);
      return target?.accountId == vault.accountId &&
          target?.remotePath == vault.remotePath;
    });
  }

  String _mountUri(RemoteVault vault) {
    final directFolderUri = _directFolderUri;
    if (directFolderUri != null && identical(vault, _selectedVault)) {
      return directFolderUri;
    }
    return _isFolderFormat(vault.format)
        ? 'cloudfolder://${vault.accountId}/${vault.format}/${Uri.encodeComponent(vault.remotePath)}'
        : 'cloud://${vault.accountId}/${Uri.encodeComponent(vault.remotePath)}';
  }

  static bool _isFolderFormat(String format) => switch (format) {
    'cryptomator' || 'gocryptfs' || 'cryfs' => true,
    _ => false,
  };

  Future<
    ({
      int volId,
      String filePath,
      List<String> files,
      int matchedCipherId,
      int matchedHashId,
      String containerFormat,
    })?
  >
  _unlockVault(RemoteVault vault, String password) async {
    if (!_isFolderFormat(vault.format)) {
      return vaultExplorerApi.unlockRemoteChunkedVault(
        vault,
        password,
        clampPim(int.tryParse(_pimCtrl.text) ?? 0),
        displayName: widget.existingRecord?.label.isNotEmpty == true
            ? widget.existingRecord!.label
            : vault.displayName,
        documentProvider: widget.documentProvider,
        autoMountFolders: widget.autoMountFolders,
        cipherId: _cipherId,
        hashId: _hashId,
        readOnly: _readOnly,
      );
    }

    final folderUri = _directFolderUri != null && identical(vault, _selectedVault)
        ? _directFolderUri
        : vault.folderUri;
    if (folderUri == null || folderUri.isEmpty) {
      throw PlatformException(
        code: 'FOLDER_UNAVAILABLE',
        message: 'The Bridge did not provide access to this cloud folder.',
      );
    }
    final displayName = widget.existingRecord?.label.isNotEmpty == true
        ? widget.existingRecord!.label
        : vault.displayName;
    final result = switch (vault.format) {
      'cryptomator' => await vaultExplorerApi.unlockCryptomatorVault(
        folderUri,
        password,
        displayName: displayName,
        documentProvider: widget.documentProvider,
        autoMountFolders: widget.autoMountFolders,
        readOnly: _readOnly,
      ),
      'gocryptfs' => await vaultExplorerApi.unlockGocryptfsVault(
        folderUri,
        password,
        displayName: displayName,
        documentProvider: widget.documentProvider,
        autoMountFolders: widget.autoMountFolders,
        readOnly: _readOnly,
      ),
      'cryfs' => await vaultExplorerApi.unlockCryfsVault(
        folderUri,
        password,
        displayName: displayName,
        documentProvider: widget.documentProvider,
        autoMountFolders: widget.autoMountFolders,
        readOnly: _readOnly,
      ),
      _ => null,
    };
    if (result == null) return null;
    return (
      volId: result.volId,
      filePath: _mountUri(vault),
      files: result.files,
      matchedCipherId: result.matchedCipherId,
      matchedHashId: result.matchedHashId,
      containerFormat: result.containerFormat,
    );
  }

  Future<void> _unlock() async {
    final vault = _selectedVault;
    if (vault == null) {
      setState(() => _error = 'Select a cloud vault first.');
      return;
    }
    if (_isAlreadyMounted(vault)) {
      setState(() => _error = 'This cloud vault is already mounted.');
      return;
    }

    final password = _passwordCtrl.text.trim();
    if (password.isEmpty) {
      setState(() => _error = 'Enter the vault password to continue.');
      return;
    }

    setState(() {
      _unlocking = true;
      _error = null;
    });
    try {
      final result = await _unlockVault(vault, password);
      if (result == null) {
        if (mounted) {
          setState(
            () => _error = 'The password was not accepted by this vault.',
          );
        }
        return;
      }

      await AppSecureStorage.instance.write(
        key: 'temp_pw_${result.filePath}',
        value: password,
      );

      final temporaryContainer = MountedContainer(
        uri: result.filePath,
        displayName: widget.existingRecord?.label.isNotEmpty == true
            ? widget.existingRecord!.label
            : vault.displayName,
        volId: result.volId,
        rootFiles: result.files,
        mountedAt: DateTime.now(),
        totalSpace: 0,
        freeSpace: 0,
        containerFormat: result.containerFormat,
        readOnly: _readOnly,
      );
      final space = await vaultExplorerApi.getSpaceInfo(temporaryContainer);
      final mountedContainer = temporaryContainer.copyWith(
        totalSpace: space != null && space.isNotEmpty ? space[0] : 0,
        freeSpace: space != null && space.length > 1 ? space[1] : 0,
      );

      ContainerRecord? record = widget.existingRecord;
      if (record != null) {
        record = record.copyWith(
          readOnly: _readOnly,
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
          containerFormat: result.containerFormat,
        );
        await ContainerRepository.instance.save(record);
      } else if (_rememberVault) {
        record = ContainerRecord(
          uri: result.filePath,
          label: vault.displayName,
          documentProvider: widget.documentProvider,
          readOnly: _readOnly,
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
          containerFormat: result.containerFormat,
        );
        await ContainerRepository.instance.save(record);
      }

      widget.onMounted(mountedContainer, record: record);
      await HapticFeedback.lightImpact();
      if (mounted) Navigator.pop(context);
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() => _error = e.message ?? 'Could not unlock cloud vault.');
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not unlock cloud vault.');
    } finally {
      if (mounted) setState(() => _unlocking = false);
    }
  }

  Future<void> _openBridgeReleases() async {
    final opened = await vaultExplorerApi.launchUrl(_bridgeReleasesUrl);
    if (!opened && mounted) {
      setState(
        () => _error = 'Could not open the VaultSync Bridge download page.',
      );
    }
  }

  Future<void> _selectExistingFolderVault() async {
    // This is deliberately VaultExplorer's normal ACTION_OPEN_DOCUMENT_TREE
    // route. Choosing the Google Drive provider here gives the engines its
    // optimised direct provider instead of proxying thousands of ciphertext
    // files through VaultSync Bridge.
    final picked = await vaultExplorerApi.pickCryptomatorVault();
    if (picked == null || !mounted) return;
    final format = picked.format;
    if (format == null) {
      setState(
        () => _error =
            'No Cryptomator, gocryptfs, or CryFS marker was found in the selected folder.',
      );
      return;
    }
    final account = _selectedAccount;
    if (account == null) return;
    final vault = RemoteVault(
      accountId: account.accountId,
      remotePath: picked.uri,
      displayName: picked.displayName,
      format: format,
      totalSizeBytes: 0,
      chunkSizeNumBytes: 0,
      folderUri: picked.uri,
    );
    setState(() {
      _selectedVault = vault;
      _directFolderUri = picked.uri;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.surfaceContainerHigh,
        title: Text(
          widget.existingRecord == null
              ? 'Cloud Storage'
              : 'Unlock Cloud Vault',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh cloud accounts',
            onPressed: _isBusy ? null : _loadBridge,
            icon: const Icon(Icons.refresh_rounded),
          ),
          const SizedBox(width: 4),
        ],
        bottom: _unlocking
            ? PreferredSize(
                preferredSize: const Size.fromHeight(4),
                child: LinearProgressIndicator(
                  color: colors.primary,
                  backgroundColor: colors.primaryContainer,
                ),
              )
            : null,
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            child: _loadingBridge
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 56),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : !_bridgeAvailable
                ? _buildBridgeUnavailable(colors, textTheme)
                : _buildPicker(colors, textTheme),
          ),
        ),
      ),
    );
  }

  Widget _buildBridgeUnavailable(ColorScheme colors, TextTheme textTheme) {
    final isMissing = _bridgeReason == 'not_installed';
    final title = isMissing
        ? 'VaultSync Bridge is not installed'
        : _bridgeReason == 'version_mismatch'
        ? 'VaultSync Bridge needs an update'
        : 'VaultSync Bridge is unavailable';
    final description = isMissing
        ? 'Install VaultSync Bridge to mount and stream cloud-stored encrypted vaults directly.'
        : 'Reconnect or update VaultSync Bridge, then try again.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          color: colors.tertiaryContainer.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: colors.tertiary.withValues(alpha: 0.3)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 48,
                  color: colors.onTertiaryContainer,
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium?.copyWith(
                    color: colors.onTertiaryContainer.withValues(alpha: 0.85),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                if (isMissing)
                  FilledButton.tonalIcon(
                    onPressed: _openBridgeReleases,
                    icon: const Icon(Icons.download_rounded),
                    label: const Text('Get VaultSync Bridge'),
                  ),
                if (isMissing) const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _loadBridge,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Check again'),
                ),
              ],
            ),
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 16),
          InlineErrorBanner(_error!),
        ],
      ],
    );
  }

  Widget _buildPicker(ColorScheme colors, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_accounts.isEmpty)
          _buildNoAccounts(colors, textTheme)
        else ...[
          Text(
            'Cloud account',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SectionCard(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_selectedAccount?.accountId),
                  initialValue: _selectedAccount?.accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Connected account',
                    prefixIcon: Icon(Icons.cloud_outlined),
                  ),
                  items: _accounts
                      .map(
                        (account) => DropdownMenuItem(
                          value: account.accountId,
                          child: Text(
                            account.displayLabel,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _isBusy
                      ? null
                      : (accountId) {
                          final account = _accounts
                              .where((item) => item.accountId == accountId)
                              .firstOrNull;
                          if (account != null) _loadVaults(account);
                        },
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Existing folder vault',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'Select the folder with Android\'s Drive provider for fast file-by-file access.',
            style: textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _isBusy ? null : _selectExistingFolderVault,
            icon: const Icon(Icons.folder_open_outlined),
            label: const Text('Select existing folder'),
          ),
          const SizedBox(height: 24),
          Text(
            'Available cloud vaults',
            style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (_loadingVaults)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_vaults.isEmpty)
            _buildNoVaults(colors, textTheme)
          else
            RadioGroup<RemoteVault>(
              groupValue: _selectedVault,
              onChanged: (value) {
                if (_unlocking) return;
                setState(() {
                  _selectedVault = value;
                  _directFolderUri = null;
                  _error = null;
                });
              },
              child: Column(
                children: [
                  for (final vault in _vaults)
                    _buildVaultTile(vault, colors, textTheme),
                ],
              ),
            ),
          if (_selectedVault != null) ...[
            const SizedBox(height: 24),
            _buildUnlockForm(colors, textTheme),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 16),
          InlineErrorBanner(_error!),
        ],
      ],
    );
  }

  Widget _buildNoAccounts(ColorScheme colors, TextTheme textTheme) {
    return Card(
      elevation: 0,
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(
              Icons.manage_accounts_outlined,
              size: 42,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              'No cloud accounts are connected',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add an account in VaultSync Bridge, then refresh this screen.',
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.tonalIcon(
              onPressed: _loadBridge,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh accounts'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoVaults(ColorScheme colors, TextTheme textTheme) {
    return Card(
      elevation: 0,
      color: colors.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              Icons.folder_off_outlined,
              size: 38,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              'No vaults found',
              style: textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Browse to an encrypted folder, choose its format, or convert and upload a container.',
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: _selectedAccount == null
                  ? null
                  : () => _loadVaults(_selectedAccount!),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh vaults'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVaultTile(
    RemoteVault vault,
    ColorScheme colors,
    TextTheme textTheme,
  ) {
    final selected = _selectedVault?.remotePath == vault.remotePath;
    final alreadyMounted = _isAlreadyMounted(vault);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        elevation: 0,
        color: alreadyMounted
            ? colors.surfaceContainerHigh.withValues(alpha: 0.55)
            : selected
            ? colors.primaryContainer.withValues(alpha: 0.2)
            : colors.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: selected
                ? colors.primary
                : colors.outlineVariant.withValues(alpha: 0.35),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          enabled: !alreadyMounted && !_unlocking,
          onTap: alreadyMounted || _unlocking
              ? null
              : () => setState(() {
                  _selectedVault = vault;
                  _error = null;
                }),
          leading: Icon(
            alreadyMounted
                ? Icons.lock_outline_rounded
                : Icons.cloud_queue_rounded,
            color: alreadyMounted ? colors.onSurfaceVariant : colors.primary,
          ),
          title: Text(
            vault.displayName,
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            _isFolderFormat(vault.format)
                ? '${_formatName(vault.format)} · folder vault'
                : '${_formatName(vault.format)} · ${_formatBytes(vault.totalSizeBytes)}',
          ),
          trailing: alreadyMounted
              ? Text(
                  'Mounted',
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              : Radio<RemoteVault>(value: vault),
        ),
      ),
    );
  }

  Widget _buildUnlockForm(ColorScheme colors, TextTheme textTheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Unlock ${_selectedVault!.displayName}',
          style: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _passwordCtrl,
                enabled: !_unlocking,
                autofocus: true,
                obscureText: _obscure,
                keyboardType: TextInputType.visiblePassword,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) {
                  if (!_unlocking) _unlock();
                },
                decoration: InputDecoration(
                  filled: true,
                  fillColor: colors.surfaceContainerHighest,
                  labelText: 'Vault password',
                  prefixIcon: Icon(
                    Icons.lock_outline_rounded,
                    color: colors.primary,
                  ),
                  suffixIcon: IconButton(
                    tooltip: _obscure ? 'Show password' : 'Hide password',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ),
            if (!_isLuks && !_isFolderVault)
              AdvancedParamsPanel(
                pimController: _pimCtrl,
                cipherId: _cipherId,
                hashId: _hashId,
                enabled: !_unlocking,
                onCipherChanged: (value) => setState(() => _cipherId = value),
                onHashChanged: (value) => setState(() => _hashId = value),
                onExpansionChanged: (_) =>
                    FocusManager.instance.primaryFocus?.unfocus(),
              ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              value: _readOnly,
              onChanged: _unlocking
                  ? null
                  : (value) => setState(() => _readOnly = value),
              secondary: Icon(Icons.visibility_outlined, color: colors.primary),
              title: Text(
                'Mount read-only',
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Prevent changes to the remote vault during this session.',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            if (widget.existingRecord == null)
              SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                value: _rememberVault,
                onChanged: _unlocking
                    ? null
                    : (value) => setState(() => _rememberVault = value),
                secondary: Icon(
                  Icons.bookmark_add_outlined,
                  color: colors.primary,
                ),
                title: Text(
                  'Keep on dashboard',
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  'Save this vault entry without saving its password.',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _unlocking ? null : _unlock,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: const StadiumBorder(),
          ),
          icon: _unlocking
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: colors.onPrimary,
                  ),
                )
              : const Icon(Icons.lock_open_rounded),
          label: Text(
            _unlocking ? 'Unlocking cloud vault…' : 'Unlock and mount',
          ),
        ),
      ],
    );
  }

  static String _formatName(String format) {
    return switch (format) {
      'veracrypt_chunked' => 'VeraCrypt (chunked)',
      'luks_chunked' => 'LUKS (chunked)',
      'cryptomator' => 'Cryptomator',
      'gocryptfs' => 'gocryptfs',
      'cryfs' => 'CryFS',
      _ => format.replaceAll('_', ' '),
    };
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final precision = value >= 100 || unit == 0 ? 0 : 1;
    return '${value.toStringAsFixed(precision)} ${units[unit]}';
  }
}

class _CloudTarget {
  final String accountId;
  final String remotePath;
  final String? format;

  const _CloudTarget(this.accountId, this.remotePath, {this.format});

  static _CloudTarget? tryParse(String? uri) {
    if (uri == null) return null;
    final isFolder = uri.startsWith('cloudfolder://');
    if (!isFolder && !uri.startsWith('cloud://')) return null;
    final remainder = uri.substring(
      isFolder ? 'cloudfolder://'.length : 'cloud://'.length,
    );
    final segments = remainder.split('/');
    if ((!isFolder && segments.length < 2) ||
        (isFolder && segments.length < 3)) {
      return null;
    }
    try {
      return _CloudTarget(
        segments.first,
        Uri.decodeComponent(
          isFolder
              ? segments.sublist(2).join('/')
              : segments.sublist(1).join('/'),
        ),
        format: isFolder ? segments[1] : null,
      );
    } on FormatException {
      return null;
    }
  }
}
