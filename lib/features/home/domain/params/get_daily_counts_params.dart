import '../../../../core/utils/calendar_date.dart';

class GetDailyCountsParams {
  GetDailyCountsParams({required DateTime date}) : date = date.normalizedDate;

  final DateTime date;
}
