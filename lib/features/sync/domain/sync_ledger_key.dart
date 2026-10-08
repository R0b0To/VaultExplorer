import 'package:vaultexplorer/features/sync/domain/models/sync_rule.dart';

/// Device-local ledger namespace for one rule/target relationship.
/// Keep this identical for foreground and scheduled runs so both continue
/// from the same three-way sync baseline.
String syncLedgerKeyFor(
  SyncRule rule, {
  required String targetIdentity,
  required String targetSubPath,
}) {
  final value = '${rule.vaultRelativePath}|$targetIdentity|$targetSubPath';
  var hash = 0x811c9dc5;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return '${rule.id}#${hash.toRadixString(16).padLeft(8, '0')}';
}
