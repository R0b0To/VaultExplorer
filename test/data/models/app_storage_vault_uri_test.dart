import 'package:test/test.dart';
import 'package:vaultexplorer/data/models/app_storage_vault_uri.dart';

void main() {
  const pkg = 'com.aeidolon.vaultexplorer';

  group('isAppStorage', () {
    test('accepts a container and a folder vault in the app sandbox', () {
      expect(AppStorageVaultUri.isAppStorage('file:///data/user/0/$pkg/files/vaults/vault.hc'), isTrue);
      expect(AppStorageVaultUri.isAppStorage('file:///data/user/0/$pkg/files/vaults/My%20notes'), isTrue);
    });

    test('accepts other Android users and the legacy data path', () {
      expect(AppStorageVaultUri.isAppStorage('file:///data/user/10/$pkg/files/vaults/a.hc'), isTrue);
      expect(AppStorageVaultUri.isAppStorage('file:///data/data/$pkg/files/vaults/a.hc'), isTrue);
    });

    test('rejects the vaults folder itself and anything that is not a file URI', () {
      expect(AppStorageVaultUri.isAppStorage('file:///data/user/0/$pkg/files/vaults'), isFalse);
      expect(AppStorageVaultUri.isAppStorage('file:///data/user/0/$pkg/files/vaults/'), isFalse);
      expect(AppStorageVaultUri.isAppStorage('content://com.android.externalstorage.documents/tree/primary%3AVault'), isFalse);
      expect(AppStorageVaultUri.isAppStorage('usb:/dev/bus/usb/001/002'), isFalse);
      expect(AppStorageVaultUri.isAppStorage('composite:abc'), isFalse);
      expect(AppStorageVaultUri.isAppStorage('/data/user/0/$pkg/files/vaults/a.hc'), isFalse);
      expect(AppStorageVaultUri.isAppStorage(''), isFalse);
    });

    test('rejects look-alikes outside the sandbox', () {
      // The app's *external* files dir also has files/vaults, but it is user-visible shared storage.
      expect(AppStorageVaultUri.isAppStorage('file:///storage/emulated/0/Android/data/$pkg/files/vaults/a.hc'), isFalse);
      expect(AppStorageVaultUri.isAppStorage('file:///storage/emulated/0/files/vaults/a.hc'), isFalse);
      expect(AppStorageVaultUri.isAppStorage('file:///sdcard/data/user/0/$pkg/files/vaults/a.hc'), isFalse);
    });

    test('rejects dot segments, even percent-encoded', () {
      expect(AppStorageVaultUri.isAppStorage('file:///data/user/0/$pkg/files/vaults/../../../x'), isFalse);
      expect(AppStorageVaultUri.isAppStorage('file:///data/user/0/$pkg/files/vaults/%2e%2e/x'), isFalse);
    });

    test('rejects a malformed percent sequence instead of throwing', () {
      expect(AppStorageVaultUri.isAppStorage('file:///data/user/0/$pkg/files/vaults/%E0%A4%A'), isFalse);
    });
  });

  group('fileName', () {
    test('decodes the last segment', () {
      expect(AppStorageVaultUri.fileName('file:///data/user/0/$pkg/files/vaults/My%20vault%20%281%29.hc'), 'My vault (1).hc');
      expect(AppStorageVaultUri.fileName('file:///data/user/0/$pkg/files/vaults/%D0%A4%D0%BE%D1%82%D0%BE'), 'Фото');
    });

    test('ignores a trailing slash and returns null for non-file URIs', () {
      expect(AppStorageVaultUri.fileName('file:///data/user/0/$pkg/files/vaults/Notes/'), 'Notes');
      expect(AppStorageVaultUri.fileName('content://x/y'), isNull);
      expect(AppStorageVaultUri.fileName('file://host/x'), isNull);
    });
  });
}
