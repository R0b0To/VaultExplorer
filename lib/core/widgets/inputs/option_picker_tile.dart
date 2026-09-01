import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/theme/app_theme.dart';

/// One choice in an [OptionPickerTile]'s picker dialog.
class SelectOption<T> {
  final T value;
  final String label;
  final String? subtitle;

  const SelectOption({
    required this.value,
    required this.label,
    this.subtitle,
  });
}

/// A settings row that opens a radio-button picker dialog on tap — the
/// shared "choose one of several options" control used across settings,
/// unlock, and container-creation screens.
///
/// Previously duplicated as a private `_buildSelectTile` + `_SelectOption<T>`
/// pair in several screens; this is that pattern's single canonical home.
class OptionPickerTile<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<SelectOption<T>> options;
  final ValueChanged<T> onChanged;
  final String? subtitle;
  final IconData? prefixIcon;
  final bool enabled;

  const OptionPickerTile({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.subtitle,
    this.prefixIcon,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = context.colors;
    final textTheme = context.typography;

    final currentOption = options.firstWhere(
      (opt) => opt.value == value,
      orElse: () => options.first,
    );

    return ListTile(
      enabled: enabled,
      leading: prefixIcon != null
          ? Icon(prefixIcon, size: AppIconSize.standard, color: cs.primary)
          : null,
      title: Text(
        label,
        style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Text(
          subtitle ?? currentOption.label,
          style: textTheme.bodySmall?.copyWith(
            color: cs.onSurfaceVariant,
            height: 1.25,
          ),
        ),
      ),
      onTap: enabled ? () => _showPicker(context) : null,
    );
  }

  void _showPicker(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final dialogTheme = Theme.of(dialogContext);
        final cs = dialogTheme.colorScheme;
        final mediaQuery = MediaQuery.of(dialogContext);
        final isLandscape = mediaQuery.orientation == Orientation.landscape;

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.sheet),
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 440,
              maxHeight: isLandscape
                  ? mediaQuery.size.height * 0.85
                  : mediaQuery.size.height * 0.75,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      label,
                      style: dialogTheme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: options.map((opt) {
                          final isSelected = opt.value == value;
                          return Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            child: RadioListTile<T>(
                              activeColor: cs.primary,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 0,
                              ),
                              value: opt.value,
                              groupValue: value,
                              title: Text(
                                opt.label,
                                style: dialogTheme.textTheme.bodyMedium
                                    ?.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.w500,
                                  color: isSelected ? cs.primary : null,
                                ),
                              ),
                              subtitle: opt.subtitle != null
                                  ? Text(
                                      opt.subtitle!,
                                      style: dialogTheme.textTheme.bodySmall
                                          ?.copyWith(
                                        color: cs.onSurfaceVariant,
                                      ),
                                    )
                                  : null,
                              onChanged: (T? newValue) {
                                if (newValue != null) {
                                  Navigator.of(dialogContext).pop();
                                  onChanged(newValue);
                                }
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
