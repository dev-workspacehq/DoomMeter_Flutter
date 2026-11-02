import 'package:doom_meter/features/home/domain/params/increment_social_count_params.dart';

import '../entities/daily_counts.dart';

abstract interface class HomeRepository {
  Future<DailyCounts> getDailyCounts(DateTime date);

  Future<DailyCounts> syncYouTubeDetectedCount({
    required DateTime date,
    required int detectedCount,
    required DateTime? lastActivityAt,
    required bool trackingEnabled,
  });

  Future<DailyCounts> incrementSocialCount({
    required SocialPlatform platform,
    required DateTime date,
    required DateTime activityTime,
  });
}
