class UsbDeviceInfo {
  final String deviceName;
  final String productName;
  final bool hasPermission;
  const UsbDeviceInfo({
    required this.deviceName,
    required this.productName,
    required this.hasPermission,
  });
}
