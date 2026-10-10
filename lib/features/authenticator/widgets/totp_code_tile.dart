import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/utils/totp_engine.dart';
import 'package:vaultexplorer/core/utils/ve_log.dart';
import 'package:vaultexplorer/features/authenticator/authenticator_registry_controller.dart';

/// A single row in the Authenticator screen styled after Proton Authenticator:
/// top row contains issuer monogram/icon, title, and account with the circular
/// countdown timer at the top right; a subtle divider separates the large
/// current code on the left from the "Next" preview on the right.
class TotpCodeTile extends ConsumerStatefulWidget {
  final TotpVaultEntry entry;
  final VoidCallback onCopy;
  final VoidCallback? onCopyNext;
  final VoidCallback onOpen;

  /// Advances an HOTP entry's counter (and so shows its next code). Only
  /// used for counter-based entries, which have no countdown to show.
  final VoidCallback? onAdvance;
  final bool showNumbers;

  const TotpCodeTile({
    super.key,
    required this.entry,
    required this.onCopy,
    this.onCopyNext,
    required this.onOpen,
    this.onAdvance,
    this.showNumbers = true,
  });

  @override
  ConsumerState<TotpCodeTile> createState() => _TotpCodeTileState();
}

class _TotpCodeTileState extends ConsumerState<TotpCodeTile> {
  static const _kLogTag = 'TotpCodeTile';

  late TotpConfig _config;
  Timer? _timer;
  String? _code;
  String? _nextCode;
  String? _error;
  double _fraction = 0;
  int _secondsLeft = 0;

  // The countdown ring is redrawn every tick, but a code only changes when its
  // time step (or an HOTP counter) does -- and each code is a native call. So
  // codes are generated once per step, not once per tick.
  /// The step [_code]/[_nextCode]/[_error] were generated for.
  int? _codeStep;

  /// The step a generation is currently in flight for, so a slow round trip
  /// isn't re-requested by every tick that lands while it's pending.
  int? _pendingStep;

  /// Bumped whenever [_config] changes so an in-flight result for the old
  /// config is dropped instead of shown.
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _config = TotpConfig.fromFields(widget.entry.item.fields);
    _tick();
    _timer = Timer.periodic(const Duration(milliseconds: 200), (_) => _tick());
  }

  @override
  void didUpdateWidget(covariant TotpCodeTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    const configKeys = [
      'totp_secret',
      'totp_algorithm',
      'totp_digits',
      'totp_period',
      'totp_type',
      'hotp_counter',
    ];
    final oldFields = oldWidget.entry.item.fields;
    final newFields = widget.entry.item.fields;
    if (configKeys.any((k) => oldFields[k] != newFields[k])) {
      _config = TotpConfig.fromFields(widget.entry.item.fields);
      _epoch++;
      _codeStep = null;
      _pendingStep = null;
      _tick();
    }
  }

  void _tick() {
    final now = DateTime.now();
    final step = TotpEngine.stepFor(_config, at: now);
    if (step != _codeStep && step != _pendingStep) {
      unawaited(_generate(step, now));
    }
    final fraction = TotpEngine.fractionElapsed(_config, at: now);
    final secondsLeft = TotpEngine.secondsRemaining(_config, at: now);
    if (!mounted) return;
    setState(() {
      _fraction = fraction;
      _secondsLeft = secondsLeft;
    });
  }

  Future<void> _generate(int step, DateTime at) async {
    final epoch = _epoch;
    final config = _config;
    final crypto = ref.read(vaultCryptoApiProvider);
    _pendingStep = step;
    String? code;
    String? nextCode;
    String? error;
    try {
      code = await TotpEngine.generateCode(config, crypto: crypto, at: at);
      // A counter-based code has no "next period" to preview -- the next
      // one only exists once the counter is advanced (see onAdvance).
      if (config.isTimeBased) {
        nextCode = await TotpEngine.generateNextCode(config, crypto: crypto, at: at);
      }
    } on TotpCodeException catch (e) {
      error = e.message;
    } on PlatformException catch (e) {
      // The platform HMAC failing is not a bad secret, but the tile's error
      // state is the same either way: show it rather than a stale code.
      VeLog.e(_kLogTag, 'HMAC failed while generating a code', e);
      error = e.message ?? e.code;
    }
    if (!mounted || epoch != _epoch) return;
    _pendingStep = null;
    setState(() {
      _code = code;
      _nextCode = nextCode;
      _error = error;
      _codeStep = step;
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// Bullets shown in place of a hidden code -- one per character, so a
  /// five-character Steam code doesn't look like a six-digit one.
  static String _maskFor(TotpConfig config) => '•' * config.digits;

  String? get _subtitle {
    final issuer = (widget.entry.item.fields['issuer'] ?? '').trim();
    final account = (widget.entry.item.fields['account'] ?? '').trim();
    if (issuer.isNotEmpty && account.isNotEmpty) return '$issuer • $account';
    if (issuer.isNotEmpty) return issuer;
    if (account.isNotEmpty) return account;
    return null;
  }

  Widget _buildLeadingIcon(ColorScheme cs) {
    final issuer = (widget.entry.item.fields['issuer'] ?? '').trim();
    final title = widget.entry.item.title.trim();
    final name = issuer.isNotEmpty ? issuer : title;
    final initial = name.characters.firstOrNull?.toUpperCase() ?? '';

    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: 0.35),
          width: 0.8,
        ),
      ),
      alignment: Alignment.center,
      child: initial.isNotEmpty
          ? Text(
              initial,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cs.primary,
              ),
            )
          : Icon(Icons.verified_user_rounded, size: 20, color: cs.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final subtitle = _subtitle;
    final hasError = _error != null;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,

      color: cs.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: hasError ? widget.onOpen : widget.onCopy,
        onLongPress: widget.onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Leading Icon, Title + Subtitle, Top-Right Countdown Ring
              Tooltip(
                message: context.l10n.authenticatorOpenItemTooltip,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: widget.onOpen,
                  child: Row(
                    children: [
                      _buildLeadingIcon(cs),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              widget.entry.item.title,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (_config.isTimeBased)
                        _CountdownRing(
                          fraction: _fraction,
                          secondsLeft: _secondsLeft,
                          color: hasError ? cs.error : cs.primary,
                        )
                      else
                        IconButton(
                          tooltip: context.l10n.authenticatorGenerateNextCode,
                          icon: Icon(Icons.refresh_rounded, color: cs.primary),
                          onPressed: hasError ? null : widget.onAdvance,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Divider(
                height: 1,
                thickness: 0.6,
                color: cs.outlineVariant.withValues(alpha: 0.3),
              ),
              const SizedBox(height: 12),
              // Bottom Row: Main Code (Left), "Next" + Code Preview (Right)
              if (hasError)
                Row(
                  children: [
                    Icon(Icons.error_outline_rounded, size: AppIconSize.small, color: cs.error),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        context.l10n.authenticatorInvalidSecretError,
                        style: TextStyle(color: cs.error, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        widget.showNumbers
                            ? formatOtpCode(_code ?? '', _config.kind)
                            : _maskFor(_config),
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontFeatures: const [FontFeature.tabularFigures()],
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.bold,
                          letterSpacing: widget.showNumbers ? 2 : 4,
                        ),
                      ),
                    ),
                    if (_nextCode != null)
                      Tooltip(
                        message: context.l10n.authenticatorCopyNextCodeTooltip,
                        child: InkWell(
                          onTap: widget.onCopyNext,
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  context.l10n.authenticatorNextCodePrefix,
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: cs.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.showNumbers
                                      ? formatOtpCode(_nextCode!, _config.kind)
                                      : _maskFor(_config),
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: cs.onSurfaceVariant,
                                    letterSpacing: widget.showNumbers ? 1 : 3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small circular countdown that drains smoothly as [fraction] (driven by
/// real wall-clock time, not frame count -- see TotpEngine.fractionElapsed)
/// approaches 1, with the seconds remaining shown in its center.
class _CountdownRing extends StatelessWidget {
  final double fraction;
  final int secondsLeft;
  final Color color;

  const _CountdownRing({required this.fraction, required this.secondsLeft, required this.color});

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 2.8,
              color: cs.surfaceContainerHighest,
            ),
          ),
          SizedBox(
            width: 36,
            height: 36,
            child: Transform.rotate(
              angle: fraction * 2 * math.pi,
              child: CircularProgressIndicator(
                value: (1 - fraction).clamp(0.0, 1.0),
                strokeWidth: 2.8,
                color: color,
                strokeCap: StrokeCap.round,
              ),
            ),
          ),
          Text(
            '$secondsLeft',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 12,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}