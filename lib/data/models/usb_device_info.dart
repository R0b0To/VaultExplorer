class UsbDeviceInfo {
  final String deviceName;
  final String productName;
  final bool hasPermission;

  /// One line under the name on desktop: size, bus and device path. Null on Android.
  final String? detail;

  /// "usb" | "nvme" | "sata" | "mmc" | "scsi" | "virtual" | "" (desktop disks); empty on Android.
  final String bus;

  /// A file system on the disk (or a partition of it) is mounted by the OS. Desktop only.
  final bool inUse;

  /// The disk carries the running operating system. Desktop only.
  final bool isSystem;

  /// "bitlocker" / "luks" signatures found at the start of a partition. Desktop only; VeraCrypt volumes have no
  /// signature to find until they are unlocked.
  final List<String> formats;

  const UsbDeviceInfo({
    required this.deviceName,
    required this.productName,
    required this.hasPermission,
    this.detail,
    this.bus = '',
    this.inUse = false,
    this.isSystem = false,
    this.formats = const [],
  });
}
