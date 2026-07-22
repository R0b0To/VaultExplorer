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

  Widget _buildCurrentCredentials(ColorScheme cs, TextTheme textTheme) {
    return _ExpressiveCard(
      children: [
        const _ExpressiveSectionHeader(
          title: 'Current Credentials',
          subtitle: 'Enter existing container password and keyfiles',
          icon: Icons.lock_clock_rounded,
        ),
        TextField(
          controller: _oldPasswordCtrl,
          obscureText: _oldObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: const [AutofillHints.password],
          decoration: InputDecoration(
            labelText: 'Old Password',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _oldObscure,
              onToggle: () => setState(() => _oldObscure = !_oldObscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _oldPimCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Old PIM (Optional)',
            prefixIcon: Icon(Icons.pin_rounded, size: 20, color: cs.primary),
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
    );
  }

  Widget _buildNewCredentials(ColorScheme cs, TextTheme textTheme) {
    return _ExpressiveCard(
      children: [
        const _ExpressiveSectionHeader(
          title: 'New Credentials',
          subtitle: 'Set new container password, PIM and keyfiles',
          icon: Icons.lock_reset_rounded,
        ),
        TextField(
          controller: _newPasswordCtrl,
          obscureText: _newObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'New Password',
            prefixIcon: Icon(Icons.lock_outline_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _newObscure,
              onToggle: () => setState(() => _newObscure = !_newObscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _confirmPasswordCtrl,
          obscureText: _confirmObscure,
          onChanged: (_) => setState(() {}),
          autofillHints: const [AutofillHints.newPassword],
          decoration: InputDecoration(
            labelText: 'Confirm New Password',
            prefixIcon: Icon(Icons.check_circle_outline_rounded, size: 20, color: cs.primary),
            suffixIcon: PasswordVisibilityToggle(
              obscured: _confirmObscure,
              onToggle: () => setState(() => _confirmObscure = !_confirmObscure),
            ),
          ),
        ),
        const SizedBox(height: 14),
        TextField(
          controller: _newPimCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'New PIM (Optional)',
            prefixIcon: Icon(Icons.pin_rounded, size: 20, color: cs.primary),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

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
              : const Text(
                  'Change Password',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
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
      body: Theme(
        data: Theme.of(context).copyWith(
          inputDecorationTheme: inputDecorationTheme,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: isLandscape
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _buildCurrentCredentials(cs, textTheme),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildNewCredentials(cs, textTheme),
                            const SizedBox(height: 20),
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
                      const SizedBox(height: 16),
                      _buildNewCredentials(cs, textTheme),
                      const SizedBox(height: 20),
                      actionArea,
                    ],
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