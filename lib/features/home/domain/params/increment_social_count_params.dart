import '../../../../core/utils/calendar_date.dart';

enum SocialPlatform { instagram, youtube }

class IncrementSocialCountParams {
  IncrementSocialCountParams({
    required this.platform,
    required DateTime date,
    required DateTime activityTime,
  }) : date = normalizeDate(date),
       activityTime = activityTime.toLocal();

  final SocialPlatform platform;
  final DateTime date;
  final DateTime activityTime;
}
