import 'package:flutter/material.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';
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
  /// dropdowns. True for unlock flows (native can search); must be false
  /// for creation flows, where a concrete algorithm has to be picked up
  /// front — see create_container_sheet.dart.
  final bool includeAuto;

  /// Extra fields rendered between the PIM field and the cipher dropdown.
  /// Exists so create_container_sheet.dart's file-system selector can live
  /// inside this same panel instead of needing its own separate one.
  final List<Widget> extraFields;

  /// Optional overrides for the cipher/hash dropdown item lists. Defaults
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

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text(
          'Advanced parameters',
          style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface),
        ),
        subtitle: subtitle != null
            ? Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))
            : null,
        leading: Icon(Icons.tune_rounded, color: cs.primary),
        childrenPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        backgroundColor: cs.surfaceContainerLow,
        collapsedBackgroundColor: cs.surfaceContainerLow,
        children: [
          if (pimController != null) ...[
            TextField(
              controller: pimController,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'PIM  (leave blank for default)',
                prefixIcon: Icon(Icons.password_outlined, size: AppIconSize.small),
              ),
            ),
            const SizedBox(height: 16),
          ],
          for (final field in extraFields) ...[
            field,
            const SizedBox(height: 16),
          ],
          DropdownButtonFormField<int>(
            initialValue: cipherId,
            decoration: const InputDecoration(
              labelText: 'Encryption Algorithm',
              prefixIcon: Icon(Icons.security_rounded, size: AppIconSize.small),
            ),
            items: cipherItems ?? CipherAlgo.dropdownItems(includeAuto: includeAuto),
            onChanged: enabled
                ? (val) {
                    if (val != null) onCipherChanged(val);
                  }
                : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: hashId,
            decoration: const InputDecoration(
              labelText: 'Hash Algorithm',
              prefixIcon: Icon(Icons.tag_rounded, size: AppIconSize.small),
            ),
            items: hashItems ?? HashAlgo.dropdownItems(includeAuto: includeAuto),
            onChanged: enabled
                ? (val) {
                    if (val != null) onHashChanged(val);
                  }
                : null,
          ),
        ],
      ),
    );
  }
}
