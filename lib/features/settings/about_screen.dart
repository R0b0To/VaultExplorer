import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'report_issue_sheet.dart';
import '../../app/vault_explorer_app.dart';

const _kGithubUrl = 'https://github.com/R0b0To/VaultExplorer';
const _kReleasesUrl = '$_kGithubUrl/releases';
const _kContributorsUrl = '$_kGithubUrl/graphs/contributors';
const _kKofiUrl = 'https://ko-fi.com/r0b0to';

class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  Future<void> _openUrl(WidgetRef ref, BuildContext context, String url) async {
    try {
      final ok = await ref.read(vaultFileIoApiProvider).launchUrl(url);
      if (!ok && context.mounted) {
        _showSnack(context, context.l10n.couldNotOpenLinkMessage, tone: AppBannerTone.error);
      }
    } catch (_) {
      if (context.mounted) {
        _showSnack(context, context.l10n.couldNotOpenLinkMessage, tone: AppBannerTone.error);
      }
    }
  }

  Future<void> _shareApp(BuildContext context) async {
    final text = context.l10n.aboutShareText(_kGithubUrl);
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      _showSnack(
        context,
        context.l10n.aboutShareLinkCopiedMessage,
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

  Widget _buildHeader(WidgetRef ref, BuildContext context) {
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
          context.l10n.aboutTagline,
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
              tooltip: context.l10n.sourceCodeTooltip,
              onTap: () => _openUrl(ref, context, _kGithubUrl),
            ),
            const SizedBox(width: 12),
            _HeaderIconButton(
              icon: Icons.favorite_rounded,
              tooltip: context.l10n.donateTooltip,
              onTap: () => _openUrl(ref, context, _kKofiUrl),
            ),
            const SizedBox(width: 12),
            _HeaderIconButton(
              icon: Icons.share_rounded,
              tooltip: context.l10n.shareAppTooltip,
              onTap: () => _shareApp(context),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: cs.surfaceContainerHigh,
        title:
            Text(context.l10n.aboutScreenTitle, style: const TextStyle(fontWeight: FontWeight.bold)),
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
                _buildHeader(ref, context),
                const SizedBox(height: 24),

                // ── Application Section ──────────────────────────────────
                SectionHeader(context.l10n.aboutApplicationSectionHeader),
                SectionCard(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        context.l10n.aboutVersionTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutVersionSubtitle(appVersion),
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        context.l10n.aboutWhatsNewTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutWhatsNewSubtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _openUrl(ref, context, _kReleasesUrl),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        context.l10n.aboutPrivacySecurityTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutPrivacySecuritySubtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _showPrivacySheet(context),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Volume Formats Section ──────────────────────────────
                SectionHeader(context.l10n.aboutSupportedFormatsSectionHeader),
                SectionCard(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Icon(Icons.shield_rounded, color: cs.primary),
                      title: Text(
                        context.l10n.aboutVeraCryptLuksTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutVeraCryptLuksSubtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Icon(Icons.key_rounded, color: cs.primary),
                      title: Text(
                        context.l10n.aboutBitLockerTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutBitLockerSubtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Icon(Icons.folder_zip_rounded, color: cs.primary),
                      title: Text(
                        context.l10n.aboutDirectoryVaultsTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutDirectoryVaultsSubtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      leading: Icon(Icons.disc_full_rounded, color: cs.primary),
                      title: Text(
                        context.l10n.aboutVhdTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutVhdSubtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Native C++ Architecture Section ────────────────────────
                SectionHeader(context.l10n.aboutNativeCoreEngineSectionHeader),
                SectionCard(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.l10n.aboutCompiledLibrariesTitle,
                            style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            context.l10n.aboutCompiledLibrariesBody,
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
                SectionHeader(context.l10n.aboutCommunitySectionHeader),
                SectionCard(
                  children: [
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        context.l10n.aboutReportIssueTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutReportIssueSubtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => showReportIssueSheet(context),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        context.l10n.aboutContributorsTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutContributorsSubtitle,
                        style: textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      onTap: () => _openUrl(ref, context, _kContributorsUrl),
                    ),
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      title: Text(
                        context.l10n.aboutLicensesTitle,
                        style: textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        context.l10n.aboutLicensesSubtitle,
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
                    context.l10n.aboutFooterMadeWithLove,
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
        context.l10n.privacyPointNoNetworkTitle,
        context.l10n.privacyPointNoNetworkBody,
      ),
      (
        context.l10n.privacyPointNoDiskLeaksTitle,
        context.l10n.privacyPointNoDiskLeaksBody,
      ),
      (
        context.l10n.privacyPointNoAnalyticsTitle,
        context.l10n.privacyPointNoAnalyticsBody,
      ),
      (
        context.l10n.privacyPointKeystoreTitle,
        context.l10n.privacyPointKeystoreBody,
      ),
      (
        context.l10n.privacyPointPosixTitle,
        context.l10n.privacyPointPosixBody,
      ),
      (
        context.l10n.privacyPointScreenClipboardTitle,
        context.l10n.privacyPointScreenClipboardBody,
      ),
      (
        context.l10n.privacyPointMaskModeTitle,
        context.l10n.privacyPointMaskModeBody,
      ),
      (
        context.l10n.privacyPointExternalLinksTitle,
        context.l10n.privacyPointExternalLinksBody,
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
                    context.l10n.aboutPrivacySheetTitle,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.aboutPrivacySheetSubtitle,
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
              child: Text(context.l10n.close,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
