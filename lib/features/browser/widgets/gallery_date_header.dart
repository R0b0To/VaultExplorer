import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:vaultexplorer/core/extensions/l10n_extension.dart';
import 'package:vaultexplorer/core/utils/raw_entry.dart';

class DateGroup<T> {
  final DateTime? date;
  final List<T> items;
  final List<int> globalIndices;

  DateGroup({
    required this.date,
    required this.items,
    required this.globalIndices,
  });
}

List<DateGroup<RawEntry>> computeDateGroups(
  List<RawEntry> items, {
  bool ascending = false,
}) {
  final Map<DateTime, DateGroup<RawEntry>> dayGroups = {};
  DateGroup<RawEntry>? undatedGroup;

  for (int i = 0; i < items.length; i++) {
    final entry = items[i];
    final secs = entry.modifiedSecs;
    if (secs > 0) {
      final dt = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
      final dayKey = DateTime(dt.year, dt.month, dt.day);
      final group = dayGroups.putIfAbsent(
        dayKey,
        () => DateGroup(date: dayKey, items: [], globalIndices: []),
      );
      group.items.add(entry);
      group.globalIndices.add(i);
    } else {
      undatedGroup ??= DateGroup(date: null, items: [], globalIndices: []);
      undatedGroup.items.add(entry);
      undatedGroup.globalIndices.add(i);
    }
  }

  final sortedKeys = dayGroups.keys.toList()
    ..sort((a, b) => ascending ? a.compareTo(b) : b.compareTo(a));

  final result = <DateGroup<RawEntry>>[
    for (final key in sortedKeys) dayGroups[key]!,
  ];
  if (undatedGroup != null) {
    result.add(undatedGroup);
  }
  return result;
}

String formatDateGroupHeader(DateTime? date, BuildContext context) {
  if (date == null) {
    return context.l10n.dateEarlier;
  }
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));
  final itemDay = DateTime(date.year, date.month, date.day);

  final locale = Localizations.localeOf(context).toString();
  if (itemDay == today) {
    return context.l10n.dateToday;
  } else if (itemDay == yesterday) {
    return context.l10n.dateYesterday;
  } else if (date.year == now.year) {
    return DateFormat('EEEE, MMMM d', locale).format(date);
  } else {
    return DateFormat('EEEE, MMMM d, y', locale).format(date);
  }
}

/// Height a [GalleryDateHeader] needs, for gallery layouts that reserve the
/// header's space up front instead of measuring it: its padding, one line of
/// the title style, and a little air above the first row of the day.
double galleryDateHeaderExtent(BuildContext context) {
  final style = Theme.of(context).textTheme.titleMedium;
  final line = MediaQuery.textScalerOf(
    context,
  ).scale((style?.fontSize ?? 16.0) * 1.5);
  return 16.0 + line + 8.0 + 4.0;
}

class GalleryDateHeader extends StatelessWidget {
  final String title;
  final int count;

  /// Inset of the title from each side. A header that sits inside a sliver
  /// which is already padded passes the difference to the 16 it wants from
  /// the screen edge.
  final double horizontalPadding;

  const GalleryDateHeader({
    super.key,
    required this.title,
    required this.count,
    this.horizontalPadding = 16.0,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;
    final isDark =
        theme.brightness == Brightness.dark || bg.computeLuminance() < 0.5;
    final titleColor = isDark ? Colors.white : const Color(0xFF1F1F1F);
    final countColor = isDark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xFF1F1F1F).withValues(alpha: 0.6);

    return Padding(
      padding: EdgeInsets.fromLTRB(horizontalPadding, 16, horizontalPadding, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: titleColor,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
