import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  static const int _goalMl = 2000;

  int _currentMl = 0;
  int _streak = 1;
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
    } catch (_) {}

    if (mounted) {
      setState(() => _loading = false);
    }
  }

  String _todayString() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _addWater(int amountMl) async {
    HapticFeedback.lightImpact();
    setState(() {
      _currentMl = (_currentMl + amountMl).clamp(0, 10000);
    });

    try {
      final secure = AppSecureStorage.instance;
      await secure.write(key: _kWaterKey, value: _currentMl.toString());
      await secure.write(key: _kWaterDateKey, value: _todayString());

      if (_currentMl >= _goalMl) {
        final newStreak = _streak + 1;
        await secure.write(key: _kStreakKey, value: newStreak.toString());
      }
    } catch (_) {}
  }

  Future<void> _resetToday() async {
    final confirm = await showAppConfirmDialog(
      context,
      title: 'Reset Today\'s Water Log?',
      message: 'This will reset your logged water intake for today to 0 ml.',
      confirmLabel: 'Reset',
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

    return Scaffold(
      appBar: AppBar(
        title: const HiddenVaultTrigger(child: Text('Hydro Tracker')),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Reset Today',
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
                            '$_streak Day Streak',
                            style: textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF0288D1),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Main circular progress gauge (Long press title or gauge for 3s to trigger vault login)
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
                                '$_currentMl ml',
                                style: textTheme.headlineMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Goal: $_goalMl ml ($percent%)',
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
                      'QUICK LOG',
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
                            amountMl: 250,
                            label: 'Glass',
                            icon: Icons.local_drink_rounded,
                            onTap: () => _addWater(250),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickAddCard(
                            amountMl: 500,
                            label: 'Bottle',
                            icon: Icons.water_drop_outlined,
                            onTap: () => _addWater(500),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickAddCard(
                            amountMl: 750,
                            label: 'Large',
                            icon: Icons.local_cafe_rounded,
                            onTap: () => _addWater(750),
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
                                    'Daily Hydration Tip',
                                    style: textTheme.labelMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Drink a glass of water right after waking up to kickstart your metabolism.',
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
  final int amountMl;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickAddCard({
    required this.amountMl,
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
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 28, color: const Color(0xFF0288D1)),
              const SizedBox(height: 8),
              Text(
                '+$amountMl ml',
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                style: textTheme.labelSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}