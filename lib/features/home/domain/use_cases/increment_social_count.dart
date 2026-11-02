import 'package:injectable/injectable.dart';

import '../../../../core/platform/scroll_tracking/scroll_tracking_service.dart';

import '../../../../core/utils/calendar_date.dart';
import '../../../../core/utils/local_clock.dart';
import '../entities/daily_counts.dart';
import '../params/increment_social_count_params.dart';
import '../repositories/home_repository.dart';

/// A domain rejection: the requested day is read-only.
class ReadOnlyCountDate implements Exception {
  const ReadOnlyCountDate();
}

class AutomaticYouTubeTrackingEnabled implements Exception {
  const AutomaticYouTubeTrackingEnabled();
}

/// Shared by domain validation and the storage boundary's midnight recheck.
void validateCountDate({
  required DateTime date,
  required DateTime activityTime,
  required DateTime now,
}) {
  if (!isSameDate(date, now)) throw const ReadOnlyCountDate();
  if (!isSameDate(date, activityTime)) {
    throw ArgumentError(
      'Activity time must belong to the requested local day.',
    );
  }
}

/// Entry point for manual taps. Native absolute totals use the sync use case.
@injectable
class IncrementSocialCount {
  IncrementSocialCount(this._repository, this._clock, this._tracking);

  final HomeRepository _repository;
  final LocalClock _clock;
  final ScrollTrackingService _tracking;

  Future<DailyCounts> call(IncrementSocialCountParams params) async {
    if (params.platform == SocialPlatform.youtube &&
        await _tracking.isTrackingEnabled()) {
      throw const AutomaticYouTubeTrackingEnabled();
    }
    validateCountDate(
      date: params.date,
      activityTime: params.activityTime,
      now: _clock.now(),
    );
    return _repository.incrementSocialCount(
      platform: params.platform,
      date: params.date,
      activityTime: params.activityTime,
    );
  }
}
