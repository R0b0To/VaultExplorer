part of 'container_config_sheet.dart';

class _PatternVerifySheet extends StatefulWidget {
  final String storedHash;
  const _PatternVerifySheet({required this.storedHash});
  @override
  State<_PatternVerifySheet> createState() => _PatternVerifySheetState();
}

class _PatternVerifySheetState extends State<_PatternVerifySheet> {
  String? _error;
  bool _showError = false;
  int _resetKey = 0;

  Future<void> _onPatternComplete(List<int> pattern) async {
    final ok = await verifyPattern(pattern, widget.storedHash);
    if (ok) {
      if (mounted) Navigator.pop(context, widget.storedHash);
    } else {
      setState(() {
        _error = context.l10n.incorrectPatternError;
        _showError = true;
      });
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted) {
          setState(() {
            _showError = false;
            _error = null;
            _resetKey++;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(context.l10n.verifyPatternTitle,
              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 24),
          PatternLockView(
            key: ValueKey(_resetKey),
            onPatternComplete: _onPatternComplete,
            showError: _showError,
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: textTheme.bodySmall?.copyWith(color: cs.error)),
          ],
          const SizedBox(height: 20),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.cancel),
          ),
        ],
      ),
    );
  }
}

class _RealPasswordGateDialog extends StatefulWidget {
  final String uri;
  final int cipherId;
  final int hashId;
  final bool documentProvider;
  final bool cacheDerivedKey;
  final String containerFormat;
  final List<Map<String, String>> initialKeyfiles;
  final String? initialPassword;
  const _RealPasswordGateDialog({
    required this.uri,
    required this.cipherId,
    required this.hashId,
    required this.documentProvider,
    required this.cacheDerivedKey,
    this.containerFormat = 'veracrypt',
    this.initialKeyfiles = const [],
    this.initialPassword,
  });
  @override
  State<_RealPasswordGateDialog> createState() => _RealPasswordGateDialogState();
}

class _RealPasswordGateDialogState extends State<_RealPasswordGateDialog>
    with KeyfilePickerMixin {
  final _pwCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();
  String? _error;
  bool _obscure = true;
  bool _loading = false;
  @override
  void onKeyfilePickError(String message) => setState(() => _error = message);
  bool get _isUsb => widget.uri.startsWith('usb:');
  String get _usbDeviceName => widget.uri.substring(4);
  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(widget.containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(widget.containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(widget.containerFormat);
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(widget.containerFormat);
  int? _activeVolId;
  late final void Function(int) _onUnlockStarted;

  @override
  void initState() {
    super.initState();
    if (widget.initialPassword != null && widget.initialPassword!.isNotEmpty) {
      _pwCtrl.text = widget.initialPassword!;
    }
    if (widget.initialKeyfiles.isNotEmpty) {
      keyfiles.addAll(widget.initialKeyfiles.map((k) => (uri: k['uri']!, displayName: k['name']!)));
    }
    _onUnlockStarted = (volId) {
      if (mounted) setState(() => _activeVolId = volId);
    };
    VaultExplorerApi.addUnlockStartedListener(_onUnlockStarted);
  }

  @override
  void dispose() {
    if (_loading && _activeVolId != null) {
      vaultExplorerApi.cancelUnlock(_activeVolId!);
    }
    VaultExplorerApi.removeUnlockStartedListener(_onUnlockStarted);
    _pwCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_pwCtrl.text.isEmpty && keyfiles.isEmpty) {
      setState(() => _error = context.l10n.passwordOrKeyfilesRequired);
      return;
    }
    setState(() { _loading = true; _error = null; });
    if (_isCryptomator || _isGocryptfs || _isCryfs) {
      try {
        final result = _isCryptomator
            ? await vaultExplorerApi.unlockCryptomatorVault(
                widget.uri,
                _pwCtrl.text,
                displayName: '',
                documentProvider: widget.documentProvider,
              )
            : _isGocryptfs
                ? await vaultExplorerApi.unlockGocryptfsVault(
                    widget.uri,
                    _pwCtrl.text,
                    displayName: '',
                    documentProvider: widget.documentProvider,
                  )
                : await vaultExplorerApi.unlockCryfsVault(
                    widget.uri,
                    _pwCtrl.text,
                    displayName: '',
                    documentProvider: widget.documentProvider,
                  );
        if (result == null) {
          if (mounted) setState(() { _loading = false; _error = context.l10n.incorrectPasswordError; });
          return;
        }
        await vaultExplorerApi.lockContainer(widget.uri);
        if (mounted) {
          Navigator.pop(context, (
            password: _pwCtrl.text,
            keyfiles: List<KeyfileRef>.from(keyfiles),
            cipherId: 255,
            hashId: 255,
          ));
        }
      } catch (e) {
        final isCancelled = e is PlatformException && e.code == 'CANCELLED';
        if (mounted && !isCancelled) {
          setState(() { _loading = false; _error = context.l10n.verificationFailedError; });
        }
      }
      return;
    }
    try {
      final pim = clampPim(_pimCtrl.text.isEmpty ? 0 : int.tryParse(_pimCtrl.text) ?? 0);
      final keyfilePaths = keyfiles.map((k) => k.uri).toList();
      final result = _isUsb
          ? await vaultExplorerApi.unlockUsbContainer(
              _usbDeviceName,
              _pwCtrl.text,
              pim,
              displayName: '',
              documentProvider: widget.documentProvider,
              cipherId: widget.cipherId,
              hashId: widget.hashId,
              preservedKey: null,
              cacheDerivedKey: widget.cacheDerivedKey,
              keyfilePaths: keyfilePaths,
            )
          : await vaultExplorerApi.unlockContainer(
              widget.uri,
              _pwCtrl.text,
              pim,
              displayName: '',
              documentProvider: widget.documentProvider,
              cipherId: widget.cipherId,
              hashId: widget.hashId,
              preservedKey: null,
              cacheDerivedKey: widget.cacheDerivedKey,
              keyfilePaths: keyfilePaths,
            );
      if (result == null) {
        if (mounted) setState(() { _loading = false; _error = context.l10n.incorrectCredentialsError; });
        return;
      }
      await vaultExplorerApi.lockContainer(_isUsb ? _usbDeviceName : widget.uri);
      if (mounted) {
        Navigator.pop(context, (
          password: _pwCtrl.text,
          keyfiles: List<KeyfileRef>.from(keyfiles),
          cipherId: result.matchedCipherId,
          hashId: result.matchedHashId,
        ));
      }
    } catch (e) {
      final isCancelled = e is PlatformException && e.code == 'CANCELLED';
      if (mounted && !isCancelled) {
        setState(() { _loading = false; _error = context.l10n.verificationFailedError; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(context.l10n.verifyCredentialsTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _pwCtrl,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                labelText: context.l10n.containerPasswordOptionalLabel,
                suffixIcon: PasswordVisibilityToggle(
                  obscured: _obscure,
                  onToggle: () => setState(() => _obscure = !_obscure),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _verify(),
            ),
            if (!_isCryptomator && !_isGocryptfs && !_isCryfs && !_isBitlocker) ...[
              const SizedBox(height: 16),
              KeyfilesPicker(
                keyfiles: keyfiles,
                picking: pickingKeyfiles,
                onPick: pickKeyfiles,
                onRemove: removeKeyfile,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _pimCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: cs.surfaceContainerHighest,
                  labelText: context.l10n.pimOptionalLabel,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            if (_loading && _activeVolId != null) {
              vaultExplorerApi.cancelUnlock(_activeVolId!);
            }
            Navigator.pop(context);
          },
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: _loading ? null : _verify,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _loading
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : Text(context.l10n.verifyButton),
        ),
      ],
    );
  }
}

class _DisplayNameDialog extends StatefulWidget {
  final String initialText;
  const _DisplayNameDialog({required this.initialText});
  @override
  State<_DisplayNameDialog> createState() => _DisplayNameDialogState();
}

class _DisplayNameDialogState extends State<_DisplayNameDialog> {
  late final TextEditingController _controller;
  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(context.l10n.displayNameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(hintText: context.l10n.containerNameHint),
        onSubmitted: (value) => Navigator.pop(context, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.l10n.cancel),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: Text(context.l10n.save),
        ),
      ],
    );
  }
}