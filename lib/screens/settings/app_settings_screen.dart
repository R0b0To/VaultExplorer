import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/app_settings_service.dart';

class AppSettingsScreen extends StatefulWidget {
  const AppSettingsScreen({Key? key}) : super(key: key);

  @override
  State<AppSettingsScreen> createState() => _AppSettingsScreenState();
}

class _AppSettingsScreenState extends State<AppSettingsScreen> {
  AppSettings _settings = AppSettings();
  bool _loading = true;
  bool _saving = false;

  // master password editing
  bool _showMasterPwField = false;
  final _masterPwCtrl = TextEditingController();
  final _masterPwConfirmCtrl = TextEditingController();
  bool _obscurePw = true;
  bool _obscureConfirm = true;
  String? _pwError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await AppSettingsService.loadSettings();
    if (mounted) setState(() { _settings = s; _loading = false; });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await AppSettingsService.saveSettings(_settings);
    setState(() => _saving = false);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }

  void _toggleMasterPassword(bool enabled) {
    setState(() {
      _settings.useMasterPassword = enabled;
      if (!enabled) {
        _settings.masterPasswordHash = null;
        _settings.masterPasswordIsFingerprint = false;
        _showMasterPwField = false;
        _masterPwCtrl.clear();
        _masterPwConfirmCtrl.clear();
        _pwError = null;
      } else {
        _showMasterPwField = true;
      }
    });
  }

  void _confirmMasterPassword() {
    final pw = _masterPwCtrl.text;
    final confirm = _masterPwConfirmCtrl.text;
    if (pw.isEmpty) {
      setState(() => _pwError = 'Password cannot be empty');
      return;
    }
    if (pw != confirm) {
      setState(() => _pwError = 'Passwords do not match');
      return;
    }
    if (pw.length < 4) {
      setState(() => _pwError = 'Password must be at least 4 characters');
      return;
    }
    // Simple hash — in production use bcrypt via a plugin
    setState(() {
      _settings.masterPasswordHash = _simpleHash(pw);
      _showMasterPwField = false;
      _pwError = null;
      _masterPwCtrl.clear();
      _masterPwConfirmCtrl.clear();
    });
  }

  /// Very basic hash placeholder. Replace with proper crypto if needed.
  String _simpleHash(String input) {
    // XOR-fold + decimal encode — not cryptographic, just obfuscation
    int h = 5381;
    for (final c in input.codeUnits) {
      h = ((h << 5) + h) ^ c;
    }
    return h.toUnsigned(32).toRadixString(16).padLeft(8, '0');
  }

  @override
  void dispose() {
    _masterPwCtrl.dispose();
    _masterPwConfirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('App Settings'),
        actions: [
          if (!_loading)
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: cs.primary),
                    )
                  : Text('Save',
                      style: TextStyle(
                          color: cs.primary, fontWeight: FontWeight.w700)),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Security section ───────────────────────────────────────
                _SectionLabel(label: 'SECURITY', cs: cs),
                const SizedBox(height: 8),

                _SettingsCard(
                  cs: cs,
                  children: [
                    _ToggleRow(
                      icon: Icons.lock_person_outlined,
                      title: 'Master Password',
                      subtitle: _settings.useMasterPassword &&
                              _settings.masterPasswordHash != null
                          ? 'Set — tap to change'
                          : 'Lock the app with a password',
                      value: _settings.useMasterPassword,
                      cs: cs,
                      onChanged: _toggleMasterPassword,
                    ),

                    if (_settings.useMasterPassword && _showMasterPwField) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _masterPwCtrl,
                        obscureText: _obscurePw,
                        decoration: InputDecoration(
                          labelText: 'New master password',
                          prefixIcon:
                              const Icon(Icons.password, size: 18),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePw
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () =>
                                setState(() => _obscurePw = !_obscurePw),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _masterPwConfirmCtrl,
                        obscureText: _obscureConfirm,
                        decoration: InputDecoration(
                          labelText: 'Confirm password',
                          prefixIcon:
                              const Icon(Icons.password, size: 18),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () => setState(
                                () => _obscureConfirm = !_obscureConfirm),
                          ),
                        ),
                      ),
                      if (_pwError != null) ...[
                        const SizedBox(height: 8),
                        Text(_pwError!,
                            style:
                                TextStyle(color: cs.error, fontSize: 12)),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: _confirmMasterPassword,
                        child: const Text('Set Master Password'),
                      ),
                    ],

                    if (_settings.useMasterPassword &&
                        !_showMasterPwField &&
                        _settings.masterPasswordHash != null) ...[
                      const SizedBox(height: 4),
                      const Divider(),
                      _ToggleRow(
                        icon: Icons.fingerprint,
                        title: 'Biometric unlock',
                        subtitle: 'Use fingerprint instead of typing',
                        value: _settings.masterPasswordIsFingerprint,
                        cs: cs,
                        onChanged: (v) => setState(
                            () => _settings.masterPasswordIsFingerprint = v),
                      ),
                    ],

                    if (_settings.useMasterPassword &&
                        !_showMasterPwField &&
                        _settings.masterPasswordHash != null) ...[
                      const SizedBox(height: 8),
                      const Divider(),
                      TextButton.icon(
                        onPressed: () => setState(() {
                          _showMasterPwField = true;
                          _pwError = null;
                        }),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Change master password'),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                // ── Integration section ────────────────────────────────────
                _SectionLabel(label: 'INTEGRATION', cs: cs),
                const SizedBox(height: 8),

                _SettingsCard(
                  cs: cs,
                  children: [
                    _ToggleRow(
                      icon: Icons.folder_shared_outlined,
                      title: 'Mount as Document Provider',
                      subtitle:
                          'Expose containers in Android\'s file picker so other apps can open files directly',
                      value: _settings.mountAsDocumentProvider,
                      cs: cs,
                      onChanged: (v) =>
                          setState(() => _settings.mountAsDocumentProvider = v),
                    ),
                    if (_settings.mountAsDocumentProvider) ...[
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.only(left: 30),
                        child: Text(
                          'Containers appear under "VaultExplorer" in the '
                          'system file picker when unlocked. Disable if you '
                          'want stricter isolation.',
                          style: TextStyle(
                              fontSize: 11, color: cs.outline, height: 1.5),
                        ),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 24),

                // ── About section ──────────────────────────────────────────
                _SectionLabel(label: 'ABOUT', cs: cs),
                const SizedBox(height: 8),

                _SettingsCard(
                  cs: cs,
                  children: [
                    _InfoRow(
                        label: 'Version', value: '0.8.4', cs: cs),
                    const Divider(),
                    _InfoRow(
                        label: 'Encryption',
                        value: 'AES-256-XTS (VeraCrypt)',
                        cs: cs),
                    const Divider(),
                    _InfoRow(
                        label: 'Key derivation',
                        value: 'PBKDF2-SHA512',
                        cs: cs),
                    const Divider(),
                    _InfoRow(
                        label: 'Filesystem',
                        value: 'FAT32 / exFAT via FatFs',
                        cs: cs),
                  ],
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── Shared sub-widgets ─────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final ColorScheme cs;
  const _SectionLabel({required this.label, required this.cs});

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.4,
          color: cs.outline,
        ),
      );
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final ColorScheme cs;
  const _SettingsCard({required this.children, required this.cs});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.outline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      );
}

class _ToggleRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ColorScheme cs;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.cs,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 18, color: cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: cs.outline, height: 1.4)),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeColor: cs.primary,
            ),
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme cs;
  const _InfoRow(
      {required this.label, required this.value, required this.cs});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(fontSize: 12, color: cs.outline)),
            const Spacer(),
            Text(value,
                style: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}