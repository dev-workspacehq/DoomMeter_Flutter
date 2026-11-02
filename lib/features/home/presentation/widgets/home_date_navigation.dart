import 'package:flutter/material.dart';

class HomeDateNavigation extends StatelessWidget {
  const HomeDateNavigation({
    required this.date,
    required this.onDateChanged,
    super.key,
  });

  final DateTime date;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final localizations = MaterialLocalizations.of(context);
    return Row(
      children: [
        IconButton.outlined(
          tooltip: 'Previous day',
          onPressed: () =>
              onDateChanged(DateTime(date.year, date.month, date.day - 1)),
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Semantics(
            liveRegion: true,
            label: localizations.formatFullDate(date),
            excludeSemantics: true,
            child: Column(
              children: [
                Text(
                  localizations.formatShortMonthDay(date),
                  key: const ValueKey('selected-date'),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  localizations.formatYear(date),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
        IconButton.outlined(
          tooltip: 'Next day',
          onPressed: () =>
              onDateChanged(DateTime(date.year, date.month, date.day + 1)),
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }
}
