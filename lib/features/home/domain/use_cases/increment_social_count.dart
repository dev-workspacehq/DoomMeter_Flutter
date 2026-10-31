import 'package:injectable/injectable.dart';

import '../../../../core/utils/calendar_date.dart';
import '../../../../core/utils/local_clock.dart';
import '../entities/daily_counts.dart';
import '../params/increment_social_count_params.dart';
import '../repositories/home_repository.dart';

/// A domain rejection: the requested day is read-only.
class ReadOnlyCountDate implements Exception {
  const ReadOnlyCountDate();
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

/// Reusable entry point for manual taps or future native event adapters.
@injectable
class IncrementSocialCount {
  IncrementSocialCount(this._repository, this._clock);

  final HomeRepository _repository;
  final LocalClock _clock;

  Future<DailyCounts> call(IncrementSocialCountParams params) async {
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
