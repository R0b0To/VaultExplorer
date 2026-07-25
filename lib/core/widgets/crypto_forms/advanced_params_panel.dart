import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
import 'package:vaultexplorer/core/widgets/common_widgets.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

/// The collapsible "Advanced parameters" (PIM / cipher / hash) panel —
/// previously hand-duplicated across the same three call sites as
/// [KeyfilesPicker]. [subtitle] is optional since only
/// `container_config_sheet.dart`'s top-level screen (not its dialogs) shows
/// one.
class AdvancedParamsPanel extends StatelessWidget {
  final TextEditingController? pimController;
  final int cipherId;
  final int hashId;
  final ValueChanged<int> onCipherChanged;
  final ValueChanged<int> onHashChanged;
  final bool enabled;
  final String? subtitle;

  /// Whether "Auto-detect" (id 255) is a valid choice in the cipher/hash
  /// selection dialogs. True for unlock flows (native can search); must be false
  /// for creation flows, where a concrete algorithm has to be picked up
  /// front — see create_container_sheet.dart.
  final bool includeAuto;

  /// Extra fields rendered between the PIM field and the cipher selector.
  /// Exists so create_container_sheet.dart's file-system selector can live
  /// inside this same panel instead of needing its own separate one.
  final List<Widget> extraFields;

  /// Optional overrides for the cipher/hash selection item lists. Defaults
  /// to the full `CipherAlgo`/`HashAlgo` catalog (via [includeAuto]) when
  /// null — pass a filtered list (e.g. `CipherAlgo.luks2Choices`) for
  /// callers that need to restrict the choices to a container-format
  /// specific subset, without affecting any other call site.
  final List<DropdownMenuItem<int>>? cipherItems;
  final List<DropdownMenuItem<int>>? hashItems;

  const AdvancedParamsPanel({
    super.key,
    this.pimController,
    required this.cipherId,
    required this.hashId,
    required this.onCipherChanged,
    required this.onHashChanged,
    this.enabled = true,
    this.subtitle,
    this.includeAuto = true,
    this.extraFields = const [],
    this.cipherItems,
    this.hashItems,
  });

  List<SelectOption<int>> _convertToSelectOptions(
      List<DropdownMenuItem<int>> items) {
    return items.map((item) {
      String label = '';
      if (item.child is Text) {
        label = (item.child as Text).data ?? '';
      } else {
        label = item.value?.toString() ?? '';
      }
      return SelectOption<int>(
        value: item.value ?? 255,
        label: label,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    final rawCipherItems =
        cipherItems ?? CipherAlgo.dropdownItems(includeAuto: includeAuto);
    final rawHashItems =
        hashItems ?? HashAlgo.dropdownItems(includeAuto: includeAuto);

    final cipherOptions = _convertToSelectOptions(rawCipherItems);
    final hashOptions = _convertToSelectOptions(rawHashItems);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: const RoundedRectangleBorder(),
        collapsedShape: const RoundedRectangleBorder(),
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        leading: Icon(Icons.tune_rounded, color: cs.primary),
        title: Text(
          'Advanced Parameters',
          style: textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
        ),
        subtitle: subtitle != null
            ? Text(subtitle!,
                style: textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant))
            : null,
        children: [
          Divider(
            height: 1,
            color: cs.outlineVariant.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 12),
          if (pimController != null) ...[
            TextField(
              controller: pimController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                filled: true,
                fillColor: cs.surfaceContainerHighest,
                labelText: 'PIM  (leave blank for default)',
                prefixIcon: const Icon(Icons.password_outlined,
                    size: AppIconSize.small),
              ),
            ),
            const SizedBox(height: 8),
          ],
          for (final field in extraFields) ...[
            field,
            const SizedBox(height: 8),
          ],
          OptionPickerTile<int>(
            label: 'Encryption Algorithm',
            value: cipherId,
            prefixIcon: Icons.security_rounded,
            options: cipherOptions,
            onChanged: onCipherChanged,
            enabled: enabled,
          ),
          OptionPickerTile<int>(
            label: 'Hash Algorithm',
            value: hashId,
            prefixIcon: Icons.tag_rounded,
            options: hashOptions,
            onChanged: onHashChanged,
            enabled: enabled,
          ),
        ],
      ),
    );
  }
}