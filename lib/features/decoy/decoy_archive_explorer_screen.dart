import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vaultexplorer/core/providers/legacy_services_providers.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_explorer_screen.dart';

/// The decoy disguise surface -- shown when the app opens in Mask Mode.
/// Hosts [DecoyLocalExplorerScreen] directly.
class DecoyArchiveExplorerScreen extends ConsumerStatefulWidget {
  const DecoyArchiveExplorerScreen({super.key});

  @override
  ConsumerState<DecoyArchiveExplorerScreen> createState() =>
      _DecoyArchiveExplorerScreenState();
}

class _DecoyArchiveExplorerScreenState
    extends ConsumerState<DecoyArchiveExplorerScreen> {
  @override
  void initState() {
    super.initState();
    // Disable screenshot blocking while in decoy mode
    unawaited(ref.read(secureScreenPolicyProvider).disableForDecoy());
  }

  @override
  Widget build(BuildContext context) {
    return const DecoyLocalExplorerScreen();
  }
}
