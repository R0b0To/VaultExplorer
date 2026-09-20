import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/widgets/feedback/inline_banner.dart';
import 'package:vaultexplorer/features/sync/services/sync_providers.dart';

/// Dashboard banner for auto-sync: progress while files are being
/// transferred, and a gentle warning when the latest run of some folder
/// needs a look. Takes no space when there is nothing to say.
class SyncStatusBanner extends ConsumerWidget {
  const SyncStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final l10n = context.l10n;

    Widget? banner;
    if (status.running) {
      banner = InlineBanner(
        l10n.autoSyncBannerRunning(
          status.targetLabel,
          status.doneActions,
          status.totalActions,
        ),
        icon: Icons.sync_rounded,
        trailing: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, value: status.fraction),
        ),
      );
    } else if (status.attention > 0) {
      banner = InlineBanner(
        l10n.autoSyncBannerAttention,
        tone: AppBannerTone.warning,
        icon: Icons.sync_problem_rounded,
      );
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: banner == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: banner,
                ),
              ),
            ),
    );
  }
}
