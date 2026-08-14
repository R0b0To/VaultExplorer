import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/widgets/sheets/app_bottom_sheet.dart';
import 'package:vaultexplorer/core/widgets/sheets/sheet_option_tile.dart';

/// The standard two-option "device or vault" action sheet used by every
/// tool that lets the user choose between an on-device location and a
/// mounted vault for a single action (adding crypto sources, picking a
/// save destination, exporting a manifest, ...).
///
/// Previously each call site (single_file_crypto_sheet.dart's source and
/// destination pickers, hash_verifier_sheet.dart's source picker and
/// manifest-export destination picker) built its own copy of this same
/// ~25-line [showModalBottomSheet] + two [SheetOptionTile]s. Title,
/// subtitle, and icon copy stay caller-supplied since "pick a source"
/// and "pick a destination" read differently even though the layout is
/// identical.
///
/// Returns `true` if the device option was chosen, `false` for the
/// vault option, or `null` if the sheet was dismissed without a choice.
Future<bool?> showDeviceOrVaultChooserSheet({
  required BuildContext context,
  required String sheetTitle,
  required String deviceTitle,
  required String deviceSubtitle,
  required String vaultTitle,
  required String vaultSubtitle,
  IconData deviceIcon = Icons.sd_storage_outlined,
  bool showVaultOption = true,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => AppBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              sheetTitle,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          SheetOptionTile(
            icon: deviceIcon,
            title: deviceTitle,
            subtitle: deviceSubtitle,
            onTap: () => Navigator.pop(ctx, true),
          ),
          if (showVaultOption)
            SheetOptionTile(
              icon: Icons.lock_open_rounded,
              iconColor: Theme.of(ctx).colorScheme.tertiary,
              title: vaultTitle,
              subtitle: vaultSubtitle,
              onTap: () => Navigator.pop(ctx, false),
            ),
        ],
      ),
    ),
  );
}