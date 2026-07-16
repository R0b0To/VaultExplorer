import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../services/vaultexplorer_api.dart';
import '../../../widgets/common_widgets.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String uri;
  final int initialCipherId;
  final int initialHashId;

  const ChangePasswordScreen({
    super.key,
    required this.uri,
    required this.initialCipherId,
    required this.initialHashId,
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
      if (mounted) setState(() => _errorMsg = e.message ?? 'Could not pick keyfiles');
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
      if (mounted) setState(() => _errorMsg = e.message ?? 'Could not pick keyfiles');
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
      setState(() => _errorMsg = 'New password or keyfiles are required.');
      return;
    }

    if (newPassword != confirmPassword) {
      setState(() => _errorMsg = 'New passwords do not match.');
      return;
    }

    setState(() {
      _isProcessing = true;
      _errorMsg = null;
    });

    final oldKeyfilePaths = _oldKeyfiles.map((k) => k.uri).toList();
    final newKeyfilePaths = _newKeyfiles.map((k) => k.uri).toList();

    final success = await vaultExplorerApi.changeContainerPassword(
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

    if (mounted) {
      setState(() => _isProcessing = false);
      if (success) {
        showAppSnackBar(context, message: 'Password changed successfully.', tone: AppBannerTone.success);
        Navigator.pop(context, true);
      } else {
        setState(() => _errorMsg = 'Failed to change password. Check old credentials.');
      }
    }
  }

  InputDecoration _getInputDecoration(
    ColorScheme cs, {
    required String labelText,
    IconData? prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 22, color: cs.primary) : null,
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

  Widget _buildCurrentCredentials(ColorScheme cs, TextTheme textTheme) {
    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.lock_clock_rounded, color: cs.primary),
            title: Text('Current Credentials', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            subtitle: Text('Enter existing container credentials', style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _oldPasswordCtrl,
                  obscureText: _oldObscure,
                  onChanged: (_) => setState(() {}),
                  autofillHints: const [AutofillHints.password],
                  decoration: _getInputDecoration(
                    cs,
                    labelText: 'Old Password',
                    prefixIcon: Icons.lock_outline_rounded,
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _oldObscure,
                      onToggle: () => setState(() => _oldObscure = !_oldObscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _oldPimCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _getInputDecoration(
                    cs,
                    labelText: 'Old PIM (Optional)',
                    prefixIcon: Icons.pin_rounded,
                  ),
                ),
                const SizedBox(height: 16),
                KeyfilesPicker(
                  keyfiles: _oldKeyfiles,
                  picking: _pickingOldKeyfiles,
                  onPick: _pickOldKeyfiles,
                  onRemove: _removeOldKeyfile,
                  enabled: !_isProcessing,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewCredentials(ColorScheme cs, TextTheme textTheme) {
    return Material(
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: Icon(Icons.lock_reset_rounded, color: cs.primary),
            title: Text('New Credentials', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500)),
            subtitle: Text('Set new container credentials', style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          ),
          Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.5)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _newPasswordCtrl,
                  obscureText: _newObscure,
                  onChanged: (_) => setState(() {}),
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: _getInputDecoration(
                    cs,
                    labelText: 'New Password',
                    prefixIcon: Icons.lock_outline_rounded,
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _newObscure,
                      onToggle: () => setState(() => _newObscure = !_newObscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _confirmPasswordCtrl,
                  obscureText: _confirmObscure,
                  onChanged: (_) => setState(() {}),
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: _getInputDecoration(
                    cs,
                    labelText: 'Confirm New Password',
                    prefixIcon: Icons.check_circle_outline_rounded,
                    suffixIcon: PasswordVisibilityToggle(
                      obscured: _confirmObscure,
                      onToggle: () => setState(() => _confirmObscure = !_confirmObscure),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _newPimCtrl,
                  keyboardType: TextInputType.number,
                  decoration: _getInputDecoration(
                    cs,
                    labelText: 'New PIM (Optional)',
                    prefixIcon: Icons.pin_rounded,
                  ),
                ),
                const SizedBox(height: 16),
                KeyfilesPicker(
                  keyfiles: _newKeyfiles,
                  picking: _pickingNewKeyfiles,
                  onPick: _pickNewKeyfiles,
                  onRemove: _removeNewKeyfile,
                  enabled: !_isProcessing,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
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
              : const Text('Change Password'),
        ),
      ],
    );

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Change Password',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: isLandscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _buildCurrentCredentials(cs, textTheme),
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildNewCredentials(cs, textTheme),
                          const SizedBox(height: 24),
                          actionArea,
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildCurrentCredentials(cs, textTheme),
                    const SizedBox(height: 20),
                    _buildNewCredentials(cs, textTheme),
                    const SizedBox(height: 24),
                    actionArea,
                  ],
                ),
        ),
      ),
    );
  }
}