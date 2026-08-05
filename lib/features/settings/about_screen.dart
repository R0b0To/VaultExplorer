import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vaultexplorer/data/services/vault_engine/vault_explorer_api.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import '../../app/vault_explorer_app.dart';

const _kGithubUrl = 'https://github.com/R0b0To/VaultExplorer';
const _kReleasesUrl = '$_kGithubUrl/releases';
const _kIssuesUrl = '$_kGithubUrl/issues/new/choose';
const _kContributorsUrl = '$_kGithubUrl/graphs/contributors';
const _kKofiUrl = 'https://ko-fi.com/r0b0to';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  Future<void> _openUrl(BuildContext context, String url) async {
    try {
      final ok = await vaultExplorerApi.launchUrl(url);
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

  Widget _buildHeader(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
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
        const SizedBox(height: 4),
        Text(
          'Free · Open Source · Offline Encrypted Vault',
          style: textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title:
            const Text('About', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                _buildHeader(context),
                const SizedBox(height: 24),

                // ── Application Section ──────────────────────────────────
                SectionHeader('Application'),
                SectionCard(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        'Version',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'v$appVersion · Tap to copy version info for bug reports',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _copyVersionInfo(context),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        "What's New",
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'See recent changes and release notes',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _openUrl(context, _kReleasesUrl),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        'Privacy & Security',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Zero-trust, 100% offline, local memory security design',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _showPrivacySheet(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Volume Formats Section ──────────────────────────────
                SectionHeader('Supported Formats'),
                SectionCard(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Icon(Icons.shield_rounded, color: cs.primary),
                      title: Text(
                        'VeraCrypt & LUKS1/2',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Standard & hidden volumes, custom PIM, keyfiles, xts-plain64, Argon2id/i',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Icon(Icons.key_rounded, color: cs.primary),
                      title: Text(
                        'BitLocker & BitLocker To Go',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'User passphrases and 48-digit numerical recovery key support',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Icon(Icons.folder_zip_rounded, color: cs.primary),
                      title: Text(
                        'Directory Vaults',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Cryptomator (v7/v8 SIV_GCM), gocryptfs (v2 EME), CryFS (0.10 Merkle)',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Icon(Icons.disc_full_rounded, color: cs.primary),
                      title: Text(
                        'Virtual Hard Disks (VHD / VHDX)',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'BAT translation for fixed and dynamic expandable disk images',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Native C++ Architecture Section ────────────────────────
                SectionHeader('Native Core Engine'),
                SectionCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Compiled C++ Libraries',
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '• mbedTLS v3.6.0 (ARMv8 Hardware Crypto & SHA-2)\n'
                            '• ChaN FatFs v4.0.4 (FAT12/16/32 & exFAT)\n'
                            '• Tuxera NTFS-3G & embedded mkntfs\n'
                            '• e2fsprogs v1.47.4 libext2fs (ext2/ext3/ext4)\n'
                            '• Dislocker Virtual I/O (BitLocker FVE / To Go)\n'
                            '• VeraCrypt 1.26.29 (Twofish, Serpent, Camellia, Kuznyechik, Whirlpool, Streebog, BLAKE2s, Argon2id/i)\n'
                            '• cJSON v1.7.18 (LUKS2 & Cryptomator metadata)',
                            style: textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Community & Legal Section ─────────────────────────────
                SectionHeader('Community & Open Source'),
                SectionCard(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        'Report an Issue',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Found a bug? Submit an issue on GitHub',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _openUrl(context, _kIssuesUrl),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        'Contributors',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'People who helped build VaultExplorer',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _openUrl(context, _kContributorsUrl),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        'Open Source Licenses',
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        'Third-party libraries used in this app',
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _showLicenses(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'Made with ❤ for privacy.',
                    style: textTheme.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

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

class _PrivacySheet extends StatelessWidget {
  const _PrivacySheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final points = <(String, String)>[
      (
        'No network access required',
        'VaultExplorer does not request the android.permission.INTERNET permission on Android. It cannot communicate over any network.',
      ),
      (
        'Zero unencrypted disk leaks',
        'Decryption and re-encryption happen entirely in system memory. Temporary unencrypted files are never saved to device storage.',
      ),
      (
        'No analytics or telemetry',
        'There is zero crash reporting, usage tracking, or third-party SDK collecting data about you or your device.',
      ),
      (
        'Secrets stay in Android Keystore',
        'Remembered passwords, patterns, and cached derived keys are sealed using AES-256-GCM in the hardware-backed Android Keystore.',
      ),
      (
        'POSIX Acceleration & Storage Access',
        'Files inside container volumes are read and written locally. Bypasses SAF when direct path access is available for up to 1000x faster I/O.',
      ),
      (
        'Screen & Clipboard Protection',
        'Screenshot/task-switcher preview blocking (FLAG_SECURE) and automatic corrupt clipboard sanitization upon window focus.',
      ),
      (
        'External links open in browser',
        'Tapping links hands off to your default browser app, which handles the request.',
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
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
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
                    '100% offline, local memory security design',
                    style: textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: points.length,
                separatorBuilder: (_, _) => Divider(
                  height: 16,
                  color: cs.outlineVariant.withValues(alpha: 0.25),
                ),
                itemBuilder: (_, i) {
                  final (title, body) = points[i];
                  return Column(
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
                          height: 1.35,
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
                minimumSize: const Size.fromHeight(48),
                shape: const StadiumBorder(),
              ),
              child: const Text('Close',
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}