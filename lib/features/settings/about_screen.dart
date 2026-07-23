import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/core/widgets/cards/expressive_card.dart';

import '../../app/vault_explorer_app.dart';


// ── External links ────────────────────────────────────────────────────────
const _kGithubUrl = 'https://github.com/R0b0To/VaultExplorer';
const _kReleasesUrl = '$_kGithubUrl/releases';
const _kIssuesUrl = '$_kGithubUrl/issues/new/choose';
const _kContributorsUrl = '$_kGithubUrl/graphs/contributors';
const _kKofiUrl = 'https://ko-fi.com/r0b0to';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        _showSnack(context, 'Could not open link', tone: AppBannerTone.error);
      }
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, 'Could not open link', tone: AppBannerTone.error);
      }
    }
  }

  Future<void> _copyVersionInfo(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: 'VaultExplorer v$appVersion (Android)'),
    );
    if (context.mounted) {
      _showSnack(
        context,
        'Version info copied — handy for bug reports',
        tone: AppBannerTone.success,
      );
    }
  }

  Future<void> _shareApp(BuildContext context) async {
    const text =
        'VaultExplorer — a free, open-source, offline vault for Android.\n\n'
        'Store passwords, notes, and files inside an encrypted container '
        '(VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs, CryFS).\n\n$_kGithubUrl';
    await Clipboard.setData(const ClipboardData(text: text));
    if (context.mounted) {
      _showSnack(
        context,
        'Copied a shareable link to your clipboard',
        tone: AppBannerTone.success,
      );
    }
  }

  void _showPrivacySheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _PrivacySheet(),
    );
  }

  void _showLicenses(BuildContext context) {
    showLicensePage(
      context: context,
      applicationName: 'VaultExplorer',
      applicationVersion: appVersion,
      applicationIcon: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Image.asset(
            'assets/images/app_icon.png',
            width: 64,
            height: 64,
          ),
        ),
      ),
    );
  }

  static void _showSnack(
    BuildContext context,
    String msg, {
    AppBannerTone tone = AppBannerTone.info,
  }) {
    showAppSnackBar(context, message: msg, tone: tone);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            // ── Header Hero Area ──────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: cs.outlineVariant.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'VaultExplorer',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Open-source · Offline · VeraCrypt, LUKS, BitLocker, Cryptomator, Gocryptfs & CryFS',
                      textAlign: TextAlign.center,
                      style: textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  // Primary Quick-Action Bar
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HeaderIconButton(
                        icon: Icons.code_rounded,
                        tooltip: 'Source Code',
                        onTap: () => _openUrl(context, _kGithubUrl),
                      ),
                      const SizedBox(width: 12),
                      _HeaderIconButton(
                        icon: Icons.favorite_rounded,
                        tooltip: 'Donate',
                        onTap: () => _openUrl(context, _kKofiUrl),
                      ),
                      const SizedBox(width: 12),
                      _HeaderIconButton(
                        icon: Icons.share_rounded,
                        tooltip: 'Share App',
                        onTap: () => _shareApp(context),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Section 1: Application ────────────────────────────────────
            ExpressiveCard(
              children: [
                const ExpressiveSectionHeader(
                  title: 'Application',
                  subtitle: 'App version, release notes & privacy assurances',
                  icon: Icons.smartphone_rounded,
                ),
                _AboutTile(
                  icon: Icons.info_outline_rounded,
                  title: 'Version',
                  subtitle: 'Tap to copy version info for bug reports',
                  trailing: _VersionPill(version: appVersion),
                  onTap: () => _copyVersionInfo(context),
                ),
                const SizedBox(height: 4),
                _AboutTile(
                  icon: Icons.auto_awesome_outlined,
                  title: "What's New",
                  subtitle: 'See recent changes and release notes',
                  onTap: () => _openUrl(context, _kReleasesUrl),
                ),
                const SizedBox(height: 4),
                _AboutTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy & Data Security',
                  subtitle: 'What VaultExplorer does — and doesn\'t — collect',
                  onTap: () => _showPrivacySheet(context),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ── Section 2: Open Source & Community ─────────────────────────
            ExpressiveCard(
              children: [
                const ExpressiveSectionHeader(
                  title: 'Open Source & Community',
                  subtitle: 'Issue tracking, contributors & third-party licenses',
                  icon: Icons.hub_rounded,
                ),
                _AboutTile(
                  icon: Icons.bug_report_outlined,
                  title: 'Report an Issue',
                  subtitle: 'Found a bug? Submit an issue on GitHub',
                  onTap: () => _openUrl(context, _kIssuesUrl),
                ),
                const SizedBox(height: 4),
                _AboutTile(
                  icon: Icons.groups_outlined,
                  title: 'Contributors',
                  subtitle: 'People who helped build VaultExplorer',
                  onTap: () => _openUrl(context, _kContributorsUrl),
                ),
                const SizedBox(height: 4),
                _AboutTile(
                  icon: Icons.article_outlined,
                  title: 'Open Source Licenses',
                  subtitle: 'Third-party libraries used in this app',
                  onTap: () => _showLicenses(context),
                ),
              ],
            ),

            const SizedBox(height: 28),

            Center(
              child: Text(
                'Made with ❤ for privacy.',
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── Header quick-action icon button ─────────────────────────────────────────

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeaderIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: cs.surfaceContainerHigh,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Icon(icon, size: 20, color: cs.primary),
          ),
        ),
      ),
    );
  }
}

// ── Version pill ─────────────────────────────────────────────────────────────

class _VersionPill extends StatelessWidget {
  final String version;
  const _VersionPill({required this.version});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        'v$version',
        style: textTheme.labelSmall?.copyWith(
          color: cs.onPrimaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

// ── Single action row ────────────────────────────────────────────────────────

class _AboutTile extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;

  const _AboutTile({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final accent = iconColor ?? cs.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (trailing != null)
                trailing!
              else if (onTap != null)
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: cs.onSurfaceVariant,
                    size: 18,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Privacy sheet ─────────────────────────────────────────────────────────────

class _PrivacySheet extends StatelessWidget {
  const _PrivacySheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final points = <(IconData, String, String)>[
      (
        Icons.wifi_off_rounded,
        'No network access required',
        'VaultExplorer does not request the Internet permission on Android. '
            'It cannot phone home even if it wanted to.',
      ),
      (
        Icons.analytics_outlined,
        'No analytics or telemetry',
        'There is no crash reporting, usage tracking, or third-party SDK '
            'collecting data about you or your device.',
      ),
      (
        Icons.folder_off_outlined,
        'Your files stay on your device',
        'Containers, and everything inside them, are read and written '
            'locally. Nothing is ever uploaded anywhere.',
      ),
      (
        Icons.key_outlined,
        'Secrets stay in Android Keystore',
        'Remembered passwords, patterns, and cached derived keys are '
            'encrypted using the Android Keystore, tied to this device.',
      ),
      (
        Icons.open_in_new_rounded,
        'Links open in your browser',
        'Tapping Source Code, Donate, or similar links hands off to your '
            'browser app — that app, not VaultExplorer, handles the request.',
      ),
    ];

    return AppBottomSheet(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    Icons.privacy_tip_outlined,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy & Data Security',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Built to work 100% offline and locally',
                        style: textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: points.length,
                separatorBuilder: (_, _) => const SizedBox(height: 16),
                itemBuilder: (_, i) {
                  final (icon, title, body) = points[i];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
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
                              style: textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              body,
                              style: textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                shape: const StadiumBorder(),
              ),
              child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
