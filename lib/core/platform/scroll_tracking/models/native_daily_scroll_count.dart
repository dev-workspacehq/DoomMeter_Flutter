import '../../../utils/calendar_date.dart';

class NativeDailyScrollCount {
  const NativeDailyScrollCount({
    required this.date,
    required this.youtubeCount,
    this.lastActivityAt,
  });

  final DateTime date;
  final int youtubeCount;
  final DateTime? lastActivityAt;

  factory NativeDailyScrollCount.fromMap(Map<Object?, Object?> map) {
    final key = map['date'];
    final date = key is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)
        ? DateTime.tryParse(key)
        : null;
    final count = map['youtubeCount'];
    final timestamp = map['lastActivityAt'];
    if (date == null ||
        date.year < 1 ||
        createDateKey(date) != key ||
        count is! int ||
        count < 0 ||
        (timestamp != null &&
            (timestamp is! int ||
                timestamp < 0 ||
                timestamp > 8640000000000000))) {
      throw const FormatException('Invalid native daily tracking record.');
    }
    return NativeDailyScrollCount(
      date: date,
      youtubeCount: count,
      lastActivityAt: timestamp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(timestamp as int),
    );
  }
}
