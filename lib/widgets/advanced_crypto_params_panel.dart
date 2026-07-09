import 'package:flutter/material.dart';
import '../models/crypto_algorithms.dart';

/// Shared "Advanced parameters" (PIM + cipher + hash) expansion panel.
/// Previously copy-pasted across unlock_sheet.dart, usb_unlock_sheet.dart,
/// container_config_sheet.dart, and create_container_sheet.dart's local
/// `_buildAdvancedTile`.
///
/// [includeAuto] controls whether "Auto-detect" appears in the dropdowns —
/// true for unlock flows (native can search), false for creation flows
/// (a concrete algorithm must be picked up front).
///
/// [extraFields] slots in between the PIM field and the cipher dropdown —
/// covers create_container_sheet's file-system selector without forcing
/// every other caller to know about it.
class AdvancedCryptoParamsPanel extends StatelessWidget {
  final TextEditingController pimController;
  final int cipherId;
  final int hashId;
  final ValueChanged<int> onCipherChanged;
  final ValueChanged<int> onHashChanged;
  final bool includeAuto;
  final bool enabled;
  final String? subtitle;
  final List<Widget> extraFields;

  const AdvancedCryptoParamsPanel({
    super.key,
    required this.pimController,
    required this.cipherId,
    required this.hashId,
    required this.onCipherChanged,
    required this.onHashChanged,
    this.includeAuto = true,
    this.enabled = true,
    this.subtitle,
    this.extraFields = const [],
  });

  InputDecoration _decoration(BuildContext context, {required String label, required IconData icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 20),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final fields = <Widget>[
      TextField(
        controller: pimController,
        enabled: enabled,
        keyboardType: TextInputType.number,
        decoration: _decoration(context, label: 'PIM  (leave blank for default)', icon: Icons.password_outlined),
      ),
      ...extraFields,
      DropdownButtonFormField<int>(
        initialValue: cipherId,
        decoration: _decoration(context, label: 'Encryption Algorithm', icon: Icons.security_rounded),
        items: CipherAlgo.dropdownItems(includeAuto: includeAuto),
        onChanged: enabled ? (val) { if (val != null) onCipherChanged(val); } : null,
      ),
      DropdownButtonFormField<int>(
        initialValue: hashId,
        decoration: _decoration(context, label: 'Hash Algorithm', icon: Icons.tag_rounded),
        items: HashAlgo.dropdownItems(includeAuto: includeAuto),
        onChanged: enabled ? (val) { if (val != null) onHashChanged(val); } : null,
      ),
    ];

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: Text('Advanced parameters',
            style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, color: cs.onSurface)),
        subtitle: subtitle != null
            ? Text(subtitle!, style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant))
            : null,
        leading: Icon(Icons.tune_rounded, color: cs.primary),
        childrenPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        backgroundColor: cs.surfaceContainerLow,
        collapsedBackgroundColor: cs.surfaceContainerLow,
        children: [
          for (int i = 0; i < fields.length; i++) ...[
            fields[i],
            if (i != fields.length - 1) const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}