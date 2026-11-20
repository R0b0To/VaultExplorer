import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/filesystem/local_storage_container.dart';
import 'package:vaultexplorer/data/models/mounted_container.dart';
import 'package:vaultexplorer/features/tools/models/vault_sync_models.dart';

MountedContainer _vault(int volId) => MountedContainer(
  uri: 'file:///vault$volId.hc',
  displayName: 'Vault $volId',
  volId: volId,
  rootFiles: const [],
  mountedAt: DateTime(2026, 1, 1),
  totalSpace: 1000,
  freeSpace: 500,
  containerFormat: 'veracrypt',
);

MountedContainer _primaryLocal() => buildLocalStorageContainer(
  rootPath: '/storage/emulated/0',
  displayName: 'Local Storage',
);

MountedContainer _savedFolder(String path, {int volId = -100}) =>
    buildExternalStorageContainer(
      rootPath: path,
      displayName: 'Saved',
      volId: volId,
    );

MountedContainer _safTree(String uri, {int volId = -101}) =>
    buildExternalStorageContainer(
      rootPath: uri,
      displayName: 'Provider',
      volId: volId,
    );

VaultSyncSide _side(MountedContainer c, [String path = '']) =>
    VaultSyncSide(container: c, relativePath: path);

void main() {
  group('VaultSyncSide.kind', () {
    test('tells vaults, device storage and document providers apart', () {
      expect(_side(_vault(3)).kind, VaultSyncTargetKind.vault);
      expect(_side(_primaryLocal()).kind, VaultSyncTargetKind.deviceStorage);
      expect(
        _side(_savedFolder('/storage/1234-ABCD/Backups')).kind,
        VaultSyncTargetKind.deviceStorage,
      );
      expect(
        _side(_safTree('content://com.android.providers/tree/x')).kind,
        VaultSyncTargetKind.documentProvider,
      );
    });

    test('only vaults are encrypted', () {
      expect(_side(_vault(3)).isEncrypted, isTrue);
      expect(_side(_primaryLocal()).isEncrypted, isFalse);
      expect(_side(_safTree('content://p/tree/x')).isEncrypted, isFalse);
    });
  });

  group('VaultSyncSide.overlapsWith', () {
    test('the same folder overlaps itself, tolerating stray slashes', () {
      final v = _vault(1);
      expect(_side(v, 'photos').overlapsWith(_side(v, 'photos')), isTrue);
      expect(_side(v, 'photos/').overlapsWith(_side(v, '/photos')), isTrue);
    });

    test('a folder overlaps its ancestors and descendants', () {
      final v = _vault(1);
      expect(_side(v, 'a').overlapsWith(_side(v, 'a/b')), isTrue);
      expect(_side(v, 'a/b').overlapsWith(_side(v, 'a')), isTrue);
      // A container root contains every folder in it.
      expect(_side(v).overlapsWith(_side(v, 'anything')), isTrue);
    });

    test('sibling folders that share a name prefix do not overlap', () {
      final v = _vault(1);
      expect(_side(v, 'photos').overlapsWith(_side(v, 'photos-backup')), isFalse);
      expect(_side(v, 'a/b').overlapsWith(_side(v, 'a/bc')), isFalse);
    });

    test('different vaults never overlap', () {
      expect(_side(_vault(1)).overlapsWith(_side(_vault(2))), isFalse);
    });

    test('primary Local Storage overlaps a saved folder for the same path', () {
      final local = _primaryLocal();
      final saved = _savedFolder('/storage/emulated/0/Documents');
      // Same physical folder reached through two different containers.
      expect(_side(local, 'Documents').overlapsWith(_side(saved)), isTrue);
      expect(_side(local, 'Documents/Work').overlapsWith(_side(saved)), isTrue);
      expect(_side(local, 'Pictures').overlapsWith(_side(saved)), isFalse);
      expect(_side(local).overlapsWith(_side(saved)), isTrue); // root contains it
    });

    test('folders on separate saved locations do not overlap', () {
      final a = _savedFolder('/storage/1234-ABCD/Backups');
      final b = _savedFolder('/storage/emulated/0/Backups', volId: -102);
      expect(_side(a).overlapsWith(_side(b)), isFalse);
    });

    test('document-provider folders overlap only within the same tree', () {
      final tree = _safTree('content://p/tree/one');
      final other = _safTree('content://p/tree/two', volId: -102);
      expect(_side(tree, 'a').overlapsWith(_side(tree, 'a/b')), isTrue);
      expect(_side(tree, 'a').overlapsWith(_side(tree, 'b')), isFalse);
      expect(_side(tree, 'a').overlapsWith(_side(other, 'a')), isFalse);
    });

    test('a vault never overlaps device or provider storage', () {
      expect(_side(_vault(1)).overlapsWith(_side(_primaryLocal())), isFalse);
      expect(
        _side(_vault(1)).overlapsWith(_side(_safTree('content://p/tree/x'))),
        isFalse,
      );
    });
  });

  group('vaultSyncNamesFor', () {
    MountedContainer named(int volId, String name) => MountedContainer(
      uri: 'file:///vault$volId.hc',
      displayName: name,
      volId: volId,
      rootFiles: const [],
      mountedAt: DateTime(2026, 1, 1),
      totalSpace: 1000,
      freeSpace: 500,
      containerFormat: 'veracrypt',
    );

    VaultSyncNames names(VaultSyncSide? l, VaultSyncSide? r) =>
        vaultSyncNamesFor(l, r, leftFallback: 'first?', rightFallback: 'second?');

    test('uses each storage\'s own name when they differ', () {
      final n = names(
        VaultSyncSide(container: named(1, 'Photos'), relativePath: ''),
        VaultSyncSide(container: named(2, 'Backup'), relativePath: 'x/y'),
      );
      expect(n.left, 'Photos');
      expect(n.right, 'Backup');
      expect(n.of(isLeft: true), 'Photos');
      expect(n.of(isLeft: false), 'Backup');
    });

    test('a side that is not chosen yet shows its fallback', () {
      final only = VaultSyncSide(container: named(1, 'Photos'), relativePath: '');
      expect(names(only, null).left, 'Photos');
      expect(names(only, null).right, 'second?');
      expect(names(null, only).left, 'first?');
      expect(names(null, null).right, 'second?');
    });

    test('two folders of one storage are told apart by folder', () {
      final vault = named(1, 'Photos');
      final n = names(
        VaultSyncSide(container: vault, relativePath: ''),
        VaultSyncSide(container: vault, relativePath: 'Backup'),
      );
      expect(n.left, isNot(n.right));
      expect(n.right, contains('Backup'));
    });

    test('same-named storages and same-named folders still differ', () {
      final n = names(
        VaultSyncSide(container: named(1, 'Vault'), relativePath: ''),
        VaultSyncSide(container: named(2, 'Vault'), relativePath: ''),
      );
      expect(n.left, isNot(n.right));
    });
  });
}
