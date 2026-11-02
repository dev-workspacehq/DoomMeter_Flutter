extension CalendarDateX on DateTime {
  /// Converts an instant to its device-local calendar date.
  DateTime get normalizedDate {
    final local = toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  bool isSameCalendarDate(DateTime other) =>
      normalizedDate == other.normalizedDate;

  /// Locale-independent Hive key; times on the same local day share one record.
  String get dateKey {
    final local = normalizedDate;
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}
