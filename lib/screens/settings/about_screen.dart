import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vaultexplorer/main.dart';
import '../../theme.dart';
import '../../widgets/common_widgets.dart';

// ── External links ────────────────────────────────────────────────────────
//
// Single source of truth so a repo move / rename only needs updating here.
const _kGithubUrl = 'https://github.com/R0b0To/VaultExplorer';
const _kReleasesUrl = '$_kGithubUrl/releases';
const _kIssuesUrl = '$_kGithubUrl/issues/new/choose';
const _kContributorsUrl = '$_kGithubUrl/graphs/contributors';
const _kKofiUrl = 'https://ko-fi.com/r0b0to';

class AboutScreen extends StatelessWidget {
  const AboutScreen({Key? key}) : super(key: key);

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && context.mounted) {
        _showSnack(context, 'Could not open link');
      }
    } catch (_) {
      if (context.mounted) _showSnack(context, 'Could not open link');
    }
  }

  Future<void> _copyVersionInfo(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: 'VaultExplorer v$appVersion (Android)'),
    );
    if (context.mounted) {
      _showSnack(context, 'Version info copied — handy for bug reports');
    }
  }

  Future<void> _shareApp(BuildContext context) async {
    const text =
        'VaultExplorer — a free, open-source, offline vault for Android.\n\n'
        'Store passwords, notes, and files inside a VeraCrypt-compatible '
        'encrypted container.\n\n$_kGithubUrl';
    await Clipboard.setData(const ClipboardData(text: text));
    if (context.mounted) {
      _showSnack(context, 'Copied a shareable link to your clipboard');
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

  static void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: ListView(
        padding: AppSpacing.pagePadding,
        children: [
          // ── Header ───────────────────────────────────────────────────
          Center(
            child: Column(
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg - 1),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'VaultExplorer',
                  style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Open-source · Offline · VeraCrypt-compatible',
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HeaderIconButton(
                      icon: Icons.code_rounded,
                      tooltip: 'Source code',
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
                      tooltip: 'Share app',
                      onTap: () => _shareApp(context),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 28),

          // ── App ──────────────────────────────────────────────────────
          const SectionLabel('App'),
          _AboutGroup(
            children: [
              _AboutTile(
                icon: Icons.new_releases_outlined,
                title: 'Version',
                subtitle:
                    'AES · Serpent · Twofish (VeraCrypt) · PBKDF2 · FAT32/exFAT',
                trailing: _VersionPill(version: appVersion),
                onTap: () => _copyVersionInfo(context),
              ),
              _AboutTile(
                icon: Icons.auto_awesome_outlined,
                title: "What's New",
                subtitle: 'See recent changes and releases',
                onTap: () => _openUrl(context, _kReleasesUrl),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Open source ──────────────────────────────────────────────
          const SectionLabel('Open Source'),
          _AboutGroup(
            children: [
              _AboutTile(
                icon: Icons.code_rounded,
                title: 'Source Code',
                subtitle: 'View the project on GitHub',
                onTap: () => _openUrl(context, _kGithubUrl),
              ),
              _AboutTile(
                icon: Icons.bug_report_outlined,
                title: 'Report an Issue',
                subtitle: 'Found a bug? Let us know',
                onTap: () => _openUrl(context, _kIssuesUrl),
              ),
              _AboutTile(
                icon: Icons.groups_outlined,
                title: 'Contributors',
                subtitle: 'People who helped build VaultExplorer',
                onTap: () => _openUrl(context, _kContributorsUrl),
              ),
              _AboutTile(
                icon: Icons.article_outlined,
                title: 'Open Source Licenses',
                subtitle: 'Third-party libraries used in this app',
                onTap: () => _showLicenses(context),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Legal ────────────────────────────────────────────────────
          const SectionLabel('Legal'),
          _AboutGroup(
            children: [
              _AboutTile(
                icon: Icons.privacy_tip_outlined,
                title: 'Privacy',
                subtitle: 'What VaultExplorer does — and doesn\'t — collect',
                onTap: () => _showPrivacySheet(context),
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Support ──────────────────────────────────────────────────
          const SectionLabel('Support the Project'),
          _AboutGroup(
            children: [
              _AboutTile(
                icon: Icons.favorite_outline_rounded,
                iconColor: const Color(0xFFEF5350),
                title: 'Donate',
                subtitle: 'Buy the developer a coffee on Ko-fi',
                onTap: () => _openUrl(context, _kKofiUrl),
              ),
              _AboutTile(
                icon: Icons.share_outlined,
                title: 'Share App',
                subtitle: 'Tell a friend about VaultExplorer',
                onTap: () => _shareApp(context),
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
            padding: const EdgeInsets.all(10),
            child: Icon(icon, size: AppIconSize.standard, color: cs.primary),
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

// ── Grouped card of tiles ────────────────────────────────────────────────────
//
// Mirrors the `_Card` pattern used in app_settings_screen.dart — a single
// rounded Card containing several rows separated by hairline dividers,
// rather than one Card per action.
class _AboutGroup extends StatelessWidget {
  final List<Widget> children;
  const _AboutGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surfaceContainerLow,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i < children.length - 1)
              const Divider(height: 1, indent: 68, endIndent: 16),
          ],
        ],
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

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, size: AppIconSize.standard, color: accent),
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
              Icon(
                Icons.chevron_right_rounded,
                color: cs.onSurfaceVariant,
                size: AppIconSize.standard,
              ),
          ],
        ),
      ),
    );
  }
}

// ── Privacy sheet ─────────────────────────────────────────────────────────────
//
// VaultExplorer has no hosted privacy-policy page (no server component, no
// tracking) — the honest thing to show is what the app actually does, not a
// link to a document that doesn't exist.
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
                Icon(
                  Icons.privacy_tip_outlined,
                  color: cs.primary,
                  size: AppIconSize.standard,
                ),
                const SizedBox(width: 10),
                Text(
                  'Privacy',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'VaultExplorer is built to work fully offline.',
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: points.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (_, i) {
                  final (icon, title, body) = points[i];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: AppIconSize.standard, color: cs.primary),
                      const SizedBox(width: 12),
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
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Got it'),
            ),
          ],
        ),
      ),
    );
  }
}