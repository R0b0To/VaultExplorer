import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/container_format.dart';

/// Compact, non-trademarked identifiers for each container/vault format
/// VaultExplorer can mount — plain initials rather than any project's
/// actual logo. Open-source code licenses (VeraCrypt's, Cryptomator's,
/// etc.) cover the code, not the brand assets, so this deliberately
/// avoids reproducing anyone's real mark.
class ContainerFormatIcon extends StatelessWidget {
  final ContainerFormat format;
  final Color color;
  final double size;

  static const Map<ContainerFormat, String> _initials = {
    ContainerFormat.veracrypt: 'VC',
    ContainerFormat.luks1: 'L1',
    ContainerFormat.luks2: 'L2',
    ContainerFormat.cryptomator: 'CM',
    ContainerFormat.gocryptfs: 'GC',
    ContainerFormat.cryfs: 'CF',
    ContainerFormat.bitlocker: 'BL',
  };

  const ContainerFormatIcon({
    super.key,
    required this.format,
    required this.color,
    this.size = 26,
  });

  @override
  Widget build(BuildContext context) {
    final initials = _initials[format];
    // 'directory_vault' (this app's own plain, non-crypto folder vault)
    // and any unrecognized/future format keep the original folder look
    // rather than showing an unfamiliar two-letter code.
    if (initials == null) {
      return Icon(Icons.folder_zip_rounded, size: size, color: color);
    }
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: color,
            fontSize: size * 0.66,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1,
          ),
        ),
      ),
    );
  }
}
