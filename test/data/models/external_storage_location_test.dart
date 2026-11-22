import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/data/models/external_storage_location.dart';

ExternalStorageLocation _loc({int? total, int? free}) => ExternalStorageLocation(
  id: 'sysvol_D:\\',
  path: 'D:\\',
  displayName: 'D: SSD Space',
  volId: -2,
  totalBytes: total,
  freeBytes: free,
);

void main() {
  test('usedFraction is the share of the drive in use', () {
    expect(_loc(total: 1000, free: 250).usedFraction, 0.75);
    expect(_loc(total: 1000, free: 0).usedFraction, 1.0);
  });

  test('usedFraction is null when the size is unknown', () {
    expect(_loc().usedFraction, isNull);
    expect(_loc(total: 0, free: 0).usedFraction, isNull);
  });

  test('sizes are not persisted', () {
    expect(_loc(total: 1000, free: 250).toJson().containsKey('totalBytes'), isFalse);
  });
}
