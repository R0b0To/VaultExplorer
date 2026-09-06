import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/data/services/container_repository.dart';
import 'package:vaultexplorer/features/composite/presentation/composite_create_sheet.dart';
import 'package:vaultexplorer/features/unlock/unlock_sheet.dart';

/// Legacy entry point for composite container operations.
/// Creation is handled by [CompositeCreateSheet], and unlocking is unified
/// under the standard [UnlockSheet].
class CompositeContainerSheet extends ConsumerWidget {
  const CompositeContainerSheet({
    super.key,
    this.existingRecord,
    this.onMounted,
  });

  /// A previously-remembered composite record. When set, delegates directly
  /// to the standard [UnlockSheet].
  final ContainerRecord? existingRecord;

  /// Called once the composite volume is successfully mounted.
  final void Function(MountedContainer container, {ContainerRecord? record})? onMounted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = existingRecord;
    if (record != null) {
      return UnlockSheet(
        initialUri: record.uri,
        initialName: record.label,
        onMounted: onMounted ?? (_, {record}) {},
      );
    }
    return const CompositeCreateSheet();
  }
}