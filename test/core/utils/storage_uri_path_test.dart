import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/utils/storage_uri_path.dart';

void main() {
  const authority = 'content://com.android.externalstorage.documents';

  group('readablePathFromUri', () {
    test('a plain path is returned as it is', () {
      expect(
        readablePathFromUri('/storage/emulated/0/Vaults/a.hc'),
        '/storage/emulated/0/Vaults/a.hc',
      );
    });

    test('a file URI loses its scheme', () {
      expect(
        readablePathFromUri('file:///storage/emulated/0/vault.hc'),
        '/storage/emulated/0/vault.hc',
      );
      expect(
        readablePathFromUri('file:///storage/emulated/0/My%20Vault.hc'),
        '/storage/emulated/0/My Vault.hc',
      );
    });

    test('a primary-volume tree URI maps to shared storage', () {
      expect(
        readablePathFromUri('$authority/tree/primary%3ADocs'),
        '/storage/emulated/0/Docs',
      );
      expect(
        readablePathFromUri('$authority/tree/primary%3ACloudStorage%2FVaults%2F'),
        '/storage/emulated/0/CloudStorage/Vaults',
      );
    });

    test('the root of the primary volume is the shared storage root', () {
      expect(
        readablePathFromUri('$authority/tree/primary%3A'),
        '/storage/emulated/0',
      );
    });

    test('a secondary volume maps to /storage/<volume>', () {
      expect(
        readablePathFromUri('$authority/tree/1234-ABCD%3A'),
        '/storage/1234-ABCD',
      );
      expect(
        readablePathFromUri('$authority/tree/1234-ABCD%3ABackups%2Fa.hc'),
        '/storage/1234-ABCD/Backups/a.hc',
      );
    });

    test('a document inside a tree is preferred over the tree itself', () {
      expect(
        readablePathFromUri(
          '$authority/tree/primary%3ADocs/document/primary%3ADocs%2Fvault.hc',
        ),
        '/storage/emulated/0/Docs/vault.hc',
      );
    });

    test('the home volume is the Documents folder', () {
      expect(
        readablePathFromUri('$authority/document/home%3ANotes'),
        '/storage/emulated/0/Documents/Notes',
      );
    });

    test('anything it cannot map comes back unchanged', () {
      for (final uri in [
        'usb:0bda-9210',
        'content://com.other.provider/tree/primary%3ADocs',
        '$authority/tree/nocolon',
        '$authority/root/primary',
        'not a uri at all',
        '',
      ]) {
        expect(readablePathFromUri(uri), uri, reason: uri);
      }
    });
  });
}
