import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/providers/vault_engine_providers.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import '../../app/vault_explorer_app.dart';

const _kGithubUrl = 'https://github.com/R0b0To/VaultExplorer';
const _kIssuesNewUrl = '$_kGithubUrl/issues/new';
const _kIssuesChooseUrl = '$_kGithubUrl/issues/new/choose';

/// Maps `Build.VERSION.SDK_INT` to the Android release number shown to
/// users (e.g. Settings → About phone). Only needs to cover minSdk (26)
/// and up; unknown/newer levels fall back to showing the raw API level.
String _androidVersionName(int sdkInt) {
  const names = {
    26: '8.0', 27: '8.1',
    28: '9', 29: '10', 30: '11', 31: '12', 32: '12L',
    33: '13', 34: '14', 35: '15', 36: '16',
  };
  final name = names[sdkInt];
  return name != null ? 'Android $name (API $sdkInt)' : 'API $sdkInt';
}

/// Builds a GitHub issue-form URL with as many fields prefilled as
/// possible. Issue-form fields are prefilled via `?field_id=value` query
/// params, matched against each field's `id` in the template YAML.
String _buildIssueUrl({
  required String template,
  String? androidVersion,
}) {
  final params = <String, String>{
    'template': template,
    'app_version': appVersion,
  };
  if (androidVersion != null && androidVersion.isNotEmpty) {
    params['android_version'] = androidVersion;
  }
  return Uri.parse(_kIssuesNewUrl).replace(queryParameters: params).toString();
}

Future<String> _resolveAndroidVersion(WidgetRef ref) async {
  try {
    final sdkInt = await ref.read(vaultLifecycleApiProvider).getAndroidSdkInt();
    return _androidVersionName(sdkInt);
  } catch (_) {
    return '';
  }
}

void showReportIssueSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ReportIssueSheet(),
  );
}

class _ReportIssueSheet extends ConsumerWidget {
  const _ReportIssueSheet();

  Future<void> _open(WidgetRef ref, BuildContext context, String url) async {
    Navigator.pop(context);
    try {
      final ok = await ref.read(vaultFileIoApiProvider).launchUrl(url);
      if (!ok && context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.couldNotOpenLinkMessage,
          tone: AppBannerTone.error,
        );
      }
    } catch (_) {
      if (context.mounted) {
        showAppSnackBar(
          context,
          message: context.l10n.couldNotOpenLinkMessage,
          tone: AppBannerTone.error,
        );
      }
    }
  }

  Future<void> _openBugReport(WidgetRef ref, BuildContext context) async {
    final androidVersion = await _resolveAndroidVersion(ref);
    final url = _buildIssueUrl(
      template: 'bug_report.yml',
      androidVersion: androidVersion,
    );
    if (context.mounted) await _open(ref, context, url);
  }

  Future<void> _openContainerIssue(WidgetRef ref, BuildContext context) async {
    final androidVersion = await _resolveAndroidVersion(ref);
    final url = _buildIssueUrl(
      template: 'container_issue.yml',
      androidVersion: androidVersion,
    );
    if (context.mounted) await _open(ref, context, url);
  }

  Future<void> _openFeatureRequest(WidgetRef ref, BuildContext context) async {
    final url = _buildIssueUrl(template: 'feature_request.yml');
    if (context.mounted) await _open(ref, context, url);
  }

  Future<void> _openChooser(WidgetRef ref, BuildContext context) async {
    await _open(ref, context, _kIssuesChooseUrl);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = context.colors;
    final textTheme = context.typography;

    return AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.l10n.reportIssueSheetTitle,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  context.l10n.reportIssueSheetSubtitle,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          SheetOptionTile(
            icon: Icons.bug_report_rounded,
            title: context.l10n.reportIssueBugTitle,
            subtitle: context.l10n.reportIssueBugSubtitle,
            onTap: () => _openBugReport(ref, context),
          ),
          SheetOptionTile(
            icon: Icons.lock_outline_rounded,
            title: context.l10n.reportIssueContainerTitle,
            subtitle: context.l10n.reportIssueContainerSubtitle,
            onTap: () => _openContainerIssue(ref, context),
          ),
          SheetOptionTile(
            icon: Icons.lightbulb_outline_rounded,
            title: context.l10n.reportIssueFeatureTitle,
            subtitle: context.l10n.reportIssueFeatureSubtitle,
            onTap: () => _openFeatureRequest(ref, context),
          ),
          SheetOptionTile(
            icon: Icons.list_alt_rounded,
            title: context.l10n.reportIssueOtherTitle,
            subtitle: context.l10n.reportIssueOtherSubtitle,
            onTap: () => _openChooser(ref, context),
          ),
        ],
      ),
    );
  }
}
