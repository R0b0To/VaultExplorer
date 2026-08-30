import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/data/models/container_format.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/utils/responsive.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/features/dashboard/widgets/change_password_controller.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
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
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _oldPasswordCtrl = TextEditingController();
  final _newPasswordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _oldPimCtrl = TextEditingController();
  final _newPimCtrl = TextEditingController();
  bool _oldObscure = true;
  bool _newObscure = true;
  bool _confirmObscure = true;

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
  void dispose() {
    _oldPasswordCtrl.dispose();
    _newPasswordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _oldPimCtrl.dispose();
    _newPimCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    ref.read(changePasswordProvider(widget.uri, widget.containerFormat, widget.initialCipherId, widget.initialHashId).notifier).submit(
      oldPassword: _oldPasswordCtrl.text,
      newPassword: _newPasswordCtrl.text,
      confirmPassword: _confirmPasswordCtrl.text,
      oldPim: _oldPimCtrl.text,
      newPim: _newPimCtrl.text,
      l10n: context.l10n,
    );
  }

  Widget _buildCurrentCredentials(ColorScheme cs, ChangePasswordState state) {
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
                keyfiles: state.oldKeyfiles,
                picking: state.pickingOldKeyfiles,
                onPick: () => ref.read(changePasswordProvider(widget.uri, widget.containerFormat, widget.initialCipherId, widget.initialHashId).notifier).pickOldKeyfiles(context.l10n),
                onRemove: (k) => ref.read(changePasswordProvider(widget.uri, widget.containerFormat, widget.initialCipherId, widget.initialHashId).notifier).removeOldKeyfile(k),
                enabled: !state.isProcessing,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildNewCredentials(ColorScheme cs, ChangePasswordState state) {
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
                keyfiles: state.newKeyfiles,
                picking: state.pickingNewKeyfiles,
                onPick: () => ref.read(changePasswordProvider(widget.uri, widget.containerFormat, widget.initialCipherId, widget.initialHashId).notifier).pickNewKeyfiles(context.l10n),
                onRemove: (k) => ref.read(changePasswordProvider(widget.uri, widget.containerFormat, widget.initialCipherId, widget.initialHashId).notifier).removeNewKeyfile(k),
                enabled: !state.isProcessing,
              ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(changePasswordProvider(widget.uri, widget.containerFormat, widget.initialCipherId, widget.initialHashId));
    ref.listen<ChangePasswordState>(changePasswordProvider(widget.uri, widget.containerFormat, widget.initialCipherId, widget.initialHashId), (previous, next) {
      if (next.successTick > (previous?.successTick ?? 0)) {
        showAppSnackBar(context, message: context.l10n.passwordChangedSuccessfullyMessage, tone: AppBannerTone.success);
        // Folder vaults don't support keyfiles, so there's nothing for
        // the caller (ContainerConfigScreen) to merge back in.
        Navigator.pop(context, _isFolderVault ? null : next.newKeyfiles);
      }
    });

    final cs = Theme.of(context).colorScheme;
    final wideLayout = context.screen.useWideLayout;
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
        if (state.errorMsg != null) ...[
          InlineErrorBanner(state.errorMsg!),
          const SizedBox(height: 16),
        ],
        FilledButton(
          onPressed: state.isProcessing ? null : _submit,
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            shape: const StadiumBorder(),
          ),
          child: state.isProcessing
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
              child: wideLayout
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildCurrentCredentials(cs, state),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildNewCredentials(cs, state),
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
                        _buildCurrentCredentials(cs, state),
                        const SizedBox(height: 16),
                        _buildNewCredentials(cs, state),
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