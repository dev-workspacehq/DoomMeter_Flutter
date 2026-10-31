import '../../../../core/utils/calendar_date.dart';

class GetDailyCountsParams {
  GetDailyCountsParams({required DateTime date}) : date = normalizeDate(date);

  final DateTime date;
}
