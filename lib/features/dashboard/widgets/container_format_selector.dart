import 'package:flutter/material.dart';
import 'package:vaultexplorer/data/models/crypto_algorithms.dart';

/// The VeraCrypt/LUKS1/LUKS2 segmented picker shown at the top of both
/// [CreateContainerSheet] and [UsbCreateContainerSheet]. The two screens'
/// copies of this were identical except for what "busy" meant to each
/// (`_loading` locally vs. `_creating || _requestingPermission` for USB,
/// since selecting a device adds a permission-request step) -- that
/// difference is why [busy] is a plain parameter rather than something
/// this widget decides for itself.
class ContainerFormatSelector extends StatelessWidget {
  const ContainerFormatSelector({
    super.key,
    required this.selected,
    required this.busy,
    required this.onChanged,
  });

  final CreateFormat selected;
  final bool busy;
  final ValueChanged<CreateFormat> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<CreateFormat>(
      segments: const [
        ButtonSegment(
          value: CreateFormat.veracrypt,
          label: Text(
            'VeraCrypt',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
          icon: Icon(Icons.lock_rounded),
        ),
        ButtonSegment(
          value: CreateFormat.luks1,
          label: Text(
            'LUKS1',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
          icon: Icon(Icons.security_rounded),
        ),
        ButtonSegment(
          value: CreateFormat.luks2,
          label: Text(
            'LUKS2',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
          icon: Icon(Icons.shield_rounded),
        ),
      ],
      selected: {selected},
      onSelectionChanged:
          busy ? null : (sel) => onChanged(sel.first),
    );
  }
}
