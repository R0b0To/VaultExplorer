import 'package:flutter_test/flutter_test.dart';
import 'package:vaultexplorer/core/engine/desktop/desktop_storage.dart';

void main() {
  test('Linux: keeps real drives and network mounts, drops system mounts', () {
    const mounts = '''
/dev/nvme0n1p2 / ext4 rw,relatime 0 0
/dev/nvme0n1p1 /boot/efi vfat rw 0 0
/dev/nvme0n1p3 /home ext4 rw 0 0
tmpfs /run/user/1000 tmpfs rw 0 0
/dev/sdb1 /run/media/ann/BACKUP\\040DISK exfat rw 0 0
/dev/sdc1 /mnt/data ext4 rw 0 0
/dev/loop3 /snap/core/1 squashfs ro 0 0
//nas/share /mnt/nas cifs rw 0 0
/dev/nvme0n1p2 /var/lib/docker/x ext4 rw 0 0
/dev/nvme0n1p2 /mnt/subvol btrfs rw 0 0
''';

    final volumes = DesktopStorage.linuxVolumesFromMounts(mounts, {
      '/dev/sdb1': 'Backup',
    });

    expect(volumes.map((v) => v['path']), [
      '/',
      '/run/media/ann/BACKUP DISK',
      '/mnt/data',
      '/mnt/nas',
      '/mnt/subvol',
    ]);
    expect(volumes.map((v) => v['description']), [
      'File system',
      'Backup',
      'data',
      'nas',
      'subvol',
    ]);
    // Every entry carries what the app's volume filter looks for.
    for (final v in volumes) {
      expect(v['state'], 'mounted');
      expect(v['isPrimary'], isFalse);
      expect(v['isRemovable'], isTrue);
    }
  });

  test('df output gives each listed drive its total and free bytes', () {
    const df = '''
Filesystem          1024-blocks      Used Available Capacity Mounted on
/dev/nvme0n1p2        999000000 828000000 171000000      83% /
/dev/sdb1             976760832 100000000 876760832      11% /run/media/ann/BACKUP DISK
''';
    final volumes = DesktopStorage.withDfSizes([
      {'path': '/', 'description': 'File system'},
      {'path': '/run/media/ann/BACKUP DISK', 'description': 'Backup'},
      {'path': '/mnt/not-in-df', 'description': 'x'},
    ], df);

    expect(volumes[0]['totalBytes'], 999000000 * 1024);
    expect(volumes[0]['freeBytes'], 171000000 * 1024);
    expect(volumes[1]['freeBytes'], 876760832 * 1024);
    // A drive df says nothing about keeps no size rather than a wrong one.
    expect(volumes[2].containsKey('totalBytes'), isFalse);
  });
}
