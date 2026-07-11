import 'package:vaultexplorer/services/container_repository.dart';

import '../services/vaultexplorer_api.dart';
import 'mounted_container.dart';

/// Unifies the two "things that can appear in the vault list" — an
/// actively-mounted [MountedContainer] and a saved-but-locked
/// [ContainerRecord] — behind one type.
///
/// Before this existed, the dashboard carried a `List<dynamic>` and every
/// consumer (`_getItemName`, `_getItemDate`, `_getItemSize`,
/// `_getItemStatus`, `_buildVaultListTile`) re-derived "what kind of thing
/// is this" with `is` checks and casts. With a sealed class, Dart's
/// exhaustiveness checking guarantees every switch handles both cases, and
/// there's exactly one place (below) that knows how to read a name/date/size
/// off each underlying model.
sealed class VaultListItem {
  const VaultListItem({
    required this.uri,
    required this.name,
    required this.sortDate,
    required this.size,
    required this.isMounted,
  });

  final String uri;
  final String name;
  final DateTime sortDate;
  final int size;
  final bool isMounted;
}

final class MountedVaultItem extends VaultListItem {
  MountedVaultItem(this.container, {required DateTime sortDate})
      : super(
          uri: container.uri,
          name: container.displayName,
          sortDate: sortDate,
          size: container.totalSpace,
          isMounted: true,
        );

  final MountedContainer container;
}

final class LockedVaultItem extends VaultListItem {
  LockedVaultItem(this.record, {required DateTime sortDate})
      : super(
          uri: record.uri,
          name: record.label.isNotEmpty
              ? record.label
              : record.uri.split('/').last,
          sortDate: sortDate,
          size: 0,
          isMounted: false,
        );

  final ContainerRecord record;
}