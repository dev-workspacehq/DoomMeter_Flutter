/// Converts an instant to its device-local calendar date.
DateTime normalizeDate(DateTime date) {
  final local = date.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool isSameDate(DateTime first, DateTime second) =>
    normalizeDate(first) == normalizeDate(second);

/// Locale-independent Hive key; times on the same local day share one record.
String createDateKey(DateTime date) {
  final local = normalizeDate(date);
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}
