import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/services/app_secure_storage.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

class DecoyWaterTrackerScreen extends StatefulWidget {
  const DecoyWaterTrackerScreen({super.key});

  @override
  State<DecoyWaterTrackerScreen> createState() => _DecoyWaterTrackerScreenState();
}

class _DecoyWaterTrackerScreenState extends State<DecoyWaterTrackerScreen> {
  static const _kWaterKey = 'decoy_water_intake_ml';
  static const _kWaterDateKey = 'decoy_water_intake_date';
  static const _kStreakKey = 'decoy_water_streak_days';
  static const _kUnitKey = 'decoy_water_is_imperial';
  static const int _goalMl = 2000;

  int _currentMl = 0;
  int _streak = 1;
  bool _isImperial = false; // false = ml, true = fl oz
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final secure = AppSecureStorage.instance;
      final dateStr = await secure.read(key: _kWaterDateKey);
      final today = _todayString();

      if (dateStr == today) {
        final mlStr = await secure.read(key: _kWaterKey);
        _currentMl = int.tryParse(mlStr ?? '') ?? 0;
      } else {
        _currentMl = 0;
        await secure.write(key: _kWaterDateKey, value: today);
        await secure.write(key: _kWaterKey, value: '0');
      }

      final streakStr = await secure.read(key: _kStreakKey);
      _streak = (int.tryParse(streakStr ?? '') ?? 1).clamp(1, 999);

      final unitStr = await secure.read(key: _kUnitKey);
      _isImperial = unitStr == 'true';
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _setUnit(bool isImperial) async {
    setState(() => _isImperial = isImperial);
    try {
      final secure = AppSecureStorage.instance;
      await secure.write(key: _kUnitKey, value: isImperial.toString());
    } catch (_) {}
  }

  String _formatVolume(int ml) {
    if (_isImperial) {
      final oz = (ml / 29.5735).round();
      return '$oz ${context.l10n.unitFlOz}';
    }
    return '$ml ${context.l10n.unitMl}';
  }

  Future<void> _addWater(int amountMl) async {
    HapticFeedback.lightImpact();
    final previousMl = _currentMl;
    final newMl = (_currentMl + amountMl).clamp(0, 10000);

    setState(() {
      _currentMl = newMl;
    });

    try {
      final secure = AppSecureStorage.instance;
      await secure.write(key: _kWaterKey, value: _currentMl.toString());
      await secure.write(key: _kWaterDateKey, value: _todayString());

      if (previousMl < _goalMl && newMl >= _goalMl) {
        final newStreak = _streak + 1;
        setState(() => _streak = newStreak);
        await secure.write(key: _kStreakKey, value: newStreak.toString());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.goalReachedSnack),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _showCustomAddDialog() async {
    final controller = TextEditingController();
    final unitLabel = _isImperial ? context.l10n.unitFlOz : context.l10n.unitMl;

    final amount = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.addWaterDialogTitle),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: context.l10n.amountWithUnitLabel(unitLabel),
            suffixText: unitLabel,
            border: const OutlineInputBorder(),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.cancel),
          ),
          FilledButton(
            onPressed: () {
              final val = int.tryParse(controller.text);
              Navigator.pop(ctx, val);
            },
            child: Text(context.l10n.add),
          ),
        ],
      ),
    );

    if (amount != null && amount > 0) {
      // Convert fl oz input back to ml for storage if Imperial unit is active
      final mlToAdd = _isImperial ? (amount * 29.5735).round() : amount;
      _addWater(mlToAdd);
    }
  }

  Future<void> _resetToday() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: context.l10n.resetTodayTitle,
      message: context.l10n.resetTodayMessage,
      confirmLabel: context.l10n.reset,
      isDestructive: true,
    );
    if (!confirm || !mounted) return;

    setState(() => _currentMl = 0);
    try {
      final secure = AppSecureStorage.instance;
      await secure.write(key: _kWaterKey, value: '0');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final progress = (_currentMl / _goalMl).clamp(0.0, 1.0);
    final percent = (progress * 100).toInt();

    // Quick add button amounts based on unit system
    final quickAdds = _isImperial
        ? [
            (label: context.l10n.quickAddGlass, display: context.l10n.quickAddDisplay(8, context.l10n.unitFlOz), ml: 237),
            (label: context.l10n.quickAddBottle, display: context.l10n.quickAddDisplay(16, context.l10n.unitFlOz), ml: 473),
            (label: context.l10n.quickAddLarge, display: context.l10n.quickAddDisplay(24, context.l10n.unitFlOz), ml: 710),
          ]
        : [
            (label: context.l10n.quickAddGlass, display: context.l10n.quickAddDisplay(250, context.l10n.unitMl), ml: 250),
            (label: context.l10n.quickAddBottle, display: context.l10n.quickAddDisplay(500, context.l10n.unitMl), ml: 500),
            (label: context.l10n.quickAddLarge, display: context.l10n.quickAddDisplay(750, context.l10n.unitMl), ml: 750),
          ];

    return Scaffold(
      appBar: AppBar(
        title: HiddenVaultTrigger(child: Text(context.l10n.appNameHydroTracker)),
        centerTitle: true,
        actions: [
          PopupMenuButton<bool>(
            icon: const Icon(Icons.tune_rounded),
            tooltip: context.l10n.unitsTooltip,
            onSelected: _setUnit,
            itemBuilder: (context) => [
              PopupMenuItem(
                value: false,
                child: Row(
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: !_isImperial ? cs.primary : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    Text(context.l10n.metricUnitLabel),
                  ],
                ),
              ),
              PopupMenuItem(
                value: true,
                child: Row(
                  children: [
                    Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: _isImperial ? cs.primary : Colors.transparent,
                    ),
                    const SizedBox(width: 8),
                    Text(context.l10n.imperialUnitLabel),
                  ],
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: context.l10n.resetTodayTooltip,
            onPressed: _resetToday,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2.5))
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  children: [
                    // Streak badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0288D1).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(100),
                        border: Border.all(color: const Color(0xFF0288D1).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🔥 ', style: TextStyle(fontSize: 16)),
                          Text(
                            context.l10n.streakBadge(_streak),
                            style: textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF0288D1),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Main circular progress gauge (HiddenVaultTrigger wraps secret vault login)
                    HiddenVaultTrigger(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 220,
                            height: 220,
                            child: CircularProgressIndicator(
                              value: progress,
                              strokeWidth: 14,
                              backgroundColor: cs.surfaceContainerHighest,
                              color: const Color(0xFF0288D1),
                              strokeCap: StrokeCap.round,
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.water_drop_rounded,
                                size: 44,
                                color: Color(0xFF0288D1),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatVolume(_currentMl),
                                style: textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.goalProgressLabel(_formatVolume(_goalMl), percent),
                                style: textTheme.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Quick Add Buttons
                    Text(
                      context.l10n.quickLogHeader,
                      style: textTheme.labelSmall?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _QuickAddCard(
                            amountText: quickAdds[0].display,
                            label: quickAdds[0].label,
                            icon: Icons.local_drink_rounded,
                            onTap: () => _addWater(quickAdds[0].ml),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickAddCard(
                            amountText: quickAdds[1].display,
                            label: quickAdds[1].label,
                            icon: Icons.water_drop_outlined,
                            onTap: () => _addWater(quickAdds[1].ml),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickAddCard(
                            amountText: quickAdds[2].display,
                            label: quickAdds[2].label,
                            icon: Icons.local_cafe_rounded,
                            onTap: () => _addWater(quickAdds[2].ml),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickAddCard(
                            amountText: context.l10n.quickAddCustom,
                            label: context.l10n.quickAddCustom,
                            icon: Icons.add_rounded,
                            onTap: _showCustomAddDialog,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // Info card
                    Card(
                      elevation: 0,
                      color: cs.surfaceContainerLow,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0288D1).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                Icons.lightbulb_outline_rounded,
                                color: Color(0xFF0288D1),
                                size: 22,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.l10n.dailyHydrationTipTitle,
                                    style: textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    context.l10n.hydrationTipBody,
                                    style: textTheme.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

class _QuickAddCard extends StatelessWidget {
  final String amountText;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAddCard({
    required this.amountText,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 26, color: const Color(0xFF0288D1)),
              const SizedBox(height: 8),
              Text(
                amountText,
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}