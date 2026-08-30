import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/services/secure_screen_policy.dart';
import 'package:vaultexplorer/features/decoy/local/decoy_local_explorer_screen.dart';
import 'package:vaultexplorer/features/decoy/widgets/hidden_vault_trigger.dart';

/// The decoy disguise surface -- shown when the app opens in Mask Mode.
/// Hosts [DecoyLocalExplorerScreen] directly.
class DecoyArchiveExplorerScreen extends StatefulWidget {
  const DecoyArchiveExplorerScreen({super.key});

  @override
  State<DecoyArchiveExplorerScreen> createState() => _DecoyArchiveExplorerScreenState();
}

class _DecoyArchiveExplorerScreenState extends State<DecoyArchiveExplorerScreen> {
  @override
  void initState() {
    super.initState();
    // Disable screenshot blocking while in decoy mode
    unawaited(SecureScreenPolicy.disableForDecoy());
  }

  @override
  Widget build(BuildContext context) {
    return const DecoyLocalExplorerScreen();
  }
}