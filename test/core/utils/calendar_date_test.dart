import 'package:doom_meter/core/utils/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('normalization and comparison use device-local calendar components', () {
    final utc = DateTime.utc(2026, 11, 2, 0, 30);
    final local = utc.toLocal();
    final expected = DateTime(local.year, local.month, local.day);
    expect(utc.normalizedDate, expected);
    expect(utc.normalizedDate.isUtc, isFalse);
    expect(utc.isSameCalendarDate(local), isTrue);
    expect(utc.dateKey, expected.dateKey);
    expect(
      utc.isSameCalendarDate(DateTime(local.year, local.month, local.day + 1)),
      isFalse,
    );
  });

  test('keys retain padding, leap days, and calendar rollover', () {
    expect(DateTime(2026, 1, 2, 23, 59).dateKey, '2026-01-02');
    expect(DateTime(2028, 2, 29).dateKey, '2028-02-29');
    expect(DateTime(2026, 12, 32).dateKey, '2027-01-01');
    expect(DateTime(42, 1, 2).dateKey, '0042-01-02');
  });
}
