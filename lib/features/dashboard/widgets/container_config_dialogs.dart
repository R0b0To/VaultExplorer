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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    Widget header = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.pattern_rounded,
              size: 22,
              color: _showError ? cs.error : cs.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.verifyPatternTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _showError ? cs.error : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _showError ? (_error ?? '') : ' ',
          style: textTheme.bodySmall?.copyWith(
            color: _showError ? cs.error : Colors.transparent,
            fontWeight: _showError ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );

    Widget cancelButton = TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      child: Text(
        context.l10n.cancel,
        style: textTheme.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );

    Widget patternView = PatternLockView(
      key: ValueKey(_resetKey),
      onPatternComplete: _onPatternComplete,
      showError: _showError,
    );

    return AppBottomSheet(
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: isLandscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 24),
                          cancelButton,
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    patternView,
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 24),
                    Center(child: patternView),
                    const SizedBox(height: 16),
                    Center(child: cancelButton),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PinVerifySheet extends StatefulWidget {
  final String storedHash;
  const _PinVerifySheet({required this.storedHash});
  @override
  State<_PinVerifySheet> createState() => _PinVerifySheetState();
}

class _PinVerifySheetState extends State<_PinVerifySheet> {
  String? _error;
  bool _showError = false;
  int _resetKey = 0;

  Future<void> _onPinComplete(String pin) async {
    final ok = await verifyPin(pin, widget.storedHash);
    if (ok) {
      if (mounted) Navigator.pop(context, widget.storedHash);
    } else {
      setState(() {
        _error = context.l10n.incorrectPinError;
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
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    Widget header = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.dialpad_rounded,
              size: 22,
              color: _showError ? cs.error : cs.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.verifyPinTitle,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: _showError ? cs.error : null,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          _showError ? (_error ?? '') : ' ',
          style: textTheme.bodySmall?.copyWith(
            color: _showError ? cs.error : Colors.transparent,
            fontWeight: _showError ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ],
    );

    Widget cancelButton = TextButton(
      onPressed: () => Navigator.pop(context),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      ),
      child: Text(
        context.l10n.cancel,
        style: textTheme.labelLarge?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );

    Widget pinView = PinLockView(
      key: ValueKey(_resetKey),
      onPinComplete: _onPinComplete,
      showError: _showError,
    );

    return AppBottomSheet(
      child: SingleChildScrollView(
        child: SizedBox(
          width: double.infinity,
          child: isLandscape
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          header,
                          const SizedBox(height: 24),
                          cancelButton,
                        ],
                      ),
                    ),
                    const SizedBox(width: 24),
                    pinView,
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    header,
                    const SizedBox(height: 28),
                    Center(child: pinView),
                    const SizedBox(height: 16),
                    Center(child: cancelButton),
                    const SizedBox(height: 4),
                  ],
                ),
        ),
      ),
    );
  }
}

class _RealPasswordGateDialog extends ConsumerStatefulWidget {
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
  ConsumerState<_RealPasswordGateDialog> createState() => _RealPasswordGateDialogState();
}

class _RealPasswordGateDialogState extends ConsumerState<_RealPasswordGateDialog> {
  final _pwCtrl = TextEditingController();
  final _pimCtrl = TextEditingController();
  bool _showAdvanced = false;
  bool _obscure = true;

  bool get _isCryptomator => ContainerFormat.isCryptomatorWire(widget.containerFormat);
  bool get _isGocryptfs => ContainerFormat.isGocryptfsWire(widget.containerFormat);
  bool get _isCryfs => ContainerFormat.isCryfsWire(widget.containerFormat);
  bool get _isBitlocker => ContainerFormat.isBitlockerWire(widget.containerFormat);
  bool get _supportsAdvanced => !_isCryptomator && !_isGocryptfs && !_isCryfs && !_isBitlocker;

  @override
  void initState() {
    super.initState();
    if (widget.initialPassword != null && widget.initialPassword!.isNotEmpty) {
      _pwCtrl.text = widget.initialPassword!;
    }
    if (widget.initialKeyfiles.isNotEmpty) {
      // Auto-expand advanced options if initial keyfiles are present
      _showAdvanced = true;
    }
  }

  @override
  void dispose() {
    _pwCtrl.dispose();
    _pimCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickKeyfiles() =>
      ref
          .read(realPasswordGateProvider(widget.initialKeyfiles).notifier)
          .pickKeyfiles();

  Future<void> _verify() async {
    final result = await ref
        .read(realPasswordGateProvider(widget.initialKeyfiles).notifier)
        .verify(
          uri: widget.uri,
          containerFormat: widget.containerFormat,
          cipherId: widget.cipherId,
          hashId: widget.hashId,
          documentProvider: widget.documentProvider,
          cacheDerivedKey: widget.cacheDerivedKey,
          password: _pwCtrl.text,
          pimText: _pimCtrl.text,
          l10n: context.l10n,
        );
    if (result != null && mounted) {
      Navigator.pop(context, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final gateState = ref.watch(realPasswordGateProvider(widget.initialKeyfiles));

    final hasConfiguredAdvanced = gateState.keyfiles.isNotEmpty || _pimCtrl.text.isNotEmpty;

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

            // --- Advanced Options Section ---
            if (_supportsAdvanced) ...[
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced ? Icons.expand_less : Icons.expand_more,
                        color: cs.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        context.l10n.advancedOptionsTitle,
                        style: textTheme.bodyMedium?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (!_showAdvanced && hasConfiguredAdvanced) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            gateState.keyfiles.isNotEmpty
                                ? '${gateState.keyfiles.length} keyfile${gateState.keyfiles.length > 1 ? 's' : ''}'
                                : 'PIM',
                            style: textTheme.labelSmall?.copyWith(
                              color: cs.onPrimaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                crossFadeState: _showAdvanced ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox.shrink(),
                secondChild: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    KeyfilesPicker(
                      keyfiles: gateState.keyfiles,
                      picking: gateState.pickingKeyfiles,
                      onPick: _pickKeyfiles,
                      onRemove: (k) => ref
                          .read(realPasswordGateProvider(widget.initialKeyfiles).notifier)
                          .removeKeyfile(k),
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
                ),
              ),
            ],

            if (gateState.error != null) ...[
              const SizedBox(height: 12),
              Text(
                gateState.error!,
                style: textTheme.bodySmall?.copyWith(color: cs.error, fontWeight: FontWeight.bold),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref
                .read(realPasswordGateProvider(widget.initialKeyfiles).notifier)
                .cancelActiveUnlock();
            Navigator.pop(context);
          },
          child: Text(context.l10n.cancel),
        ),
        FilledButton(
          onPressed: gateState.loading ? null : _verify,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: gateState.loading
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