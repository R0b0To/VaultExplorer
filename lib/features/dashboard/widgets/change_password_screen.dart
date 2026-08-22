import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String uri;
  final int initialCipherId;
  final int initialHashId;

  /// Wire-level format ('veracrypt', 'cryptomator', 'gocryptfs', 'cryfs',
  /// ...) -- decides which underlying change-password call to make and
  /// whether the PIM/keyfile fields apply (folder vaults have neither).
  final String containerFormat;

  const ChangePasswordScreen({
    super.key,
    required this.uri,
    required this.initialCipherId,
    required this.initialHashId,
    required this.containerFormat,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _oldPimCtrl = TextEditingController();
  final _newPimCtrl = TextEditingController();
  final List<KeyfileRef> _oldKeyfiles = [];
  bool _pickingOldKeyfiles = false;
  final List<KeyfileRef> _newKeyfiles = [];
  bool _pickingNewKeyfiles = false;
  bool _oldObscure = true;
  bool _newObscure = true;
  bool _confirmObscure = true;
  bool _isProcessing = false;
  String? _errorMsg;

  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(widget.containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(widget.containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(widget.containerFormat);
  // Folder vaults have neither a PIM (VeraCrypt-only) nor keyfile support,
  // and their change-password call takes just old/new password.
  bool get _isFolderVault => _isCryptomator || _isGocryptfs || _isCryfs;
  // LUKS has keyfile support but no PIM concept (VeraCrypt-only), so it
  // hides just the PIM fields while keeping the keyfile pickers.
  bool get _isLuks => ContainerFormat.isLuksWire(widget.containerFormat);
  bool get _hidePim => _isFolderVault || _isLuks;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _oldPimCtrl.dispose();
    _newPimCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickOldKeyfiles() async {
    setState(() => _pickingOldKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (picked.isNotEmpty) {
        setState(() {
          for (final k in picked) {
            if (!_oldKeyfiles.any((existing) => existing.uri == k.uri)) {
              _oldKeyfiles.add(k);
            }
          }
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _errorMsg = e.message ?? context.l10n.couldNotPickKeyfiles);
    } finally {
      if (mounted) setState(() => _pickingOldKeyfiles = false);
    }
  }

  void _removeOldKeyfile(KeyfileRef keyfile) {
    setState(() => _oldKeyfiles.remove(keyfile));
  }

  Future<void> _pickNewKeyfiles() async {
    setState(() => _pickingNewKeyfiles = true);
    try {
      final picked = await vaultExplorerApi.pickKeyfiles();
      if (picked.isNotEmpty) {
        setState(() {
          for (final k in picked) {
            if (!_newKeyfiles.any((existing) => existing.uri == k.uri)) {
              _newKeyfiles.add(k);
            }
          }
        });
      }
    } on PlatformException catch (e) {
      if (mounted) setState(() => _errorMsg = e.message ?? context.l10n.couldNotPickKeyfiles);
    } finally {
      if (mounted) setState(() => _pickingNewKeyfiles = false);
    }
  }

  void _removeNewKeyfile(KeyfileRef keyfile) {
    setState(() => _newKeyfiles.remove(keyfile));
  }

  Future<void> _submit() async {
    final oldPassword = _oldPasswordCtrl.text;
    final newPassword = _newPasswordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;
    if (newPassword.isEmpty && _newKeyfiles.isEmpty) {
      setState(() => _errorMsg = context.l10n.newPasswordOrKeyfilesRequired);
      return;
    }
    if (newPassword != confirmPassword) {
      setState(() => _errorMsg = context.l10n.newPasswordsDoNotMatch);
      return;
    }
    setState(() {
      _isProcessing = true;
      _errorMsg = null;
    });
    try {
      bool success;
      if (_isCryptomator) {
        success = await vaultExplorerApi.changeCryptomatorVaultPassword(widget.uri, oldPassword, newPassword);
      } else if (_isGocryptfs) {
        success = await vaultExplorerApi.changeGocryptfsVaultPassword(widget.uri, oldPassword, newPassword);
      } else if (_isCryfs) {
        success = await vaultExplorerApi.changeCryfsVaultPassword(widget.uri, oldPassword, newPassword);
      } else if (_isLuks) {
        final oldKeyfilePaths = _oldKeyfiles.map((k) => k.uri).toList();
        final newKeyfilePaths = _newKeyfiles.map((k) => k.uri).toList();
        success = await vaultExplorerApi.changeLuksContainerPassword(
          uri: widget.uri,
          oldPassword: oldPassword,
          newPassword: newPassword,
          oldKeyfilePaths: oldKeyfilePaths,
          newKeyfilePaths: newKeyfilePaths,
        );
      } else {
        final oldKeyfilePaths = _oldKeyfiles.map((k) => k.uri).toList();
        final newKeyfilePaths = _newKeyfiles.map((k) => k.uri).toList();
        success = await vaultExplorerApi.changeContainerPassword(
          uri: widget.uri,
          oldPassword: oldPassword,
          newPassword: newPassword,
          oldPim: int.tryParse(_oldPimCtrl.text) ?? 0,
          newPim: int.tryParse(_newPimCtrl.text) ?? 0,
          cipherId: widget.initialCipherId,
          hashId: widget.initialHashId,
          oldKeyfilePaths: oldKeyfilePaths,
          newKeyfilePaths: newKeyfilePaths,
        );
      }
      if (mounted) {
        setState(() => _isProcessing = false);
        if (success) {
          showAppSnackBar(context, message: context.l10n.passwordChangedSuccessfullyMessage, tone: AppBannerTone.success);
          // Folder vaults don't support keyfiles, so there's nothing for
          // the caller (ContainerConfigScreen) to merge back in.
          Navigator.pop(context, _isFolderVault ? null : _newKeyfiles);
        } else {
          setState(() => _errorMsg = context.l10n.failedToChangePasswordMessage);
        }
      }
    } on PlatformException catch (e) {
      // Folder vaults report specific failures (wrong password, unreadable
      // config, ...) as PlatformExceptions with a pre-formatted message --
      // see changeCryptomatorVaultPassword's doc comment.
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _errorMsg = e.message ?? context.l10n.failedToChangePasswordMessage;
        });
      }
    }
  }

  Widget _buildCurrentCredentials(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.currentCredentialsSectionHeader),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _oldPasswordCtrl,
                obscureText: _oldObscure,
                onChanged: (_) => setState(() {}),
                autofillHints: null,
                decoration: InputDecoration(
                  labelText: context.l10n.oldPasswordLabel,
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _oldObscure,
                    onToggle: () => setState(() => _oldObscure = !_oldObscure),
                  ),
                ),
              ),
            ),
            if (!_hidePim)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _oldPimCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.oldPimOptionalLabel,
                    prefixIcon: Icon(Icons.pin_rounded, size: 20, color: cs.primary),
                  ),
                ),
              ),
            if (!_isFolderVault)
              KeyfilesPicker(
                keyfiles: _oldKeyfiles,
                picking: _pickingOldKeyfiles,
                onPick: _pickOldKeyfiles,
                onRemove: _removeOldKeyfile,
                enabled: !_isProcessing,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildNewCredentials(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeader(context.l10n.newCredentialsSectionHeader),
        SectionCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _newPasswordCtrl,
                obscureText: _newObscure,
                onChanged: (_) => setState(() {}),
                autofillHints: null,
                decoration: InputDecoration(
                  labelText: context.l10n.newPasswordLabel,
                  prefixIcon: Icon(Icons.key_rounded, size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _newObscure,
                    onToggle: () => setState(() => _newObscure = !_newObscure),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _confirmPasswordCtrl,
                obscureText: _confirmObscure,
                onChanged: (_) => setState(() {}),
                autofillHints: null,
                decoration: InputDecoration(
                  labelText: context.l10n.confirmNewPasswordLabel,
                  prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
                  suffixIcon: PasswordVisibilityToggle(
                    obscured: _confirmObscure,
                    onToggle: () => setState(() => _confirmObscure = !_confirmObscure),
                  ),
                ),
              ),
            ),
            if (!_hidePim)
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _newPimCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.l10n.newPimOptionalLabel,
                    prefixIcon: Icon(Icons.pin_rounded, size: 20, color: cs.primary),
                  ),
                ),
              ),
            if (!_isFolderVault)
              KeyfilesPicker(
                keyfiles: _newKeyfiles,
                picking: _pickingNewKeyfiles,
                onPick: _pickNewKeyfiles,
                onRemove: _removeNewKeyfile,
                enabled: !_isProcessing,
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
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
    final actionArea = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_errorMsg != null) ...[
          InlineErrorBanner(_errorMsg!),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: _isProcessing ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: const StadiumBorder(),
          ),
          child: _isProcessing
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(cs.onPrimary),
                  ),
                )
              : Text(
                  context.l10n.changePasswordTitle,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title: Text(
          context.l10n.changePasswordTitle,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: inputDecorationTheme,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: AutofillGroup(
              child: isLandscape
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildCurrentCredentials(cs),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildNewCredentials(cs),
                              const SizedBox(height: 16),
                              actionArea,
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCurrentCredentials(cs),
                        const SizedBox(height: 16),
                        _buildNewCredentials(cs),
                        const SizedBox(height: 16),
                        actionArea,
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}