import 'package:injectable/injectable.dart';

import '../../../../core/storage/local_storage_service.dart';
import '../../../../core/utils/calendar_date.dart';
import '../../../../core/utils/local_clock.dart';
import '../../domain/params/increment_social_count_params.dart';
import '../../domain/use_cases/increment_social_count.dart';
import '../models/daily_counts_model.dart';

const dailyCountsBoxName = 'daily_counts';

/// The single writer for daily records within the application isolate.
/// All callers (including future native adapters) must share this DI singleton.
@lazySingleton
class HomeDataSource {
  HomeDataSource(this._storage, this._clock);

  final LocalStorageService _storage;
  final LocalClock _clock;
  Future<void> _pendingWrite = Future<void>.value();

  Future<DailyCountsModel> getDailyCounts(DateTime date) async {
    // A read issued after a write should observe that completed write.
    await _pendingWrite;
    return _read(date);
  }

  Future<DailyCountsModel> _read(DateTime date) async {
    final map = await _storage.get<Map<dynamic, dynamic>>(
      dailyCountsBoxName,
      createDateKey(date),
    );
    if (map == null) {
      return DailyCountsModel(
        date: normalizeDate(date),
        instagramCount: 0,
        youtubeCount: 0,
      );
    }
    final model = DailyCountsModel.fromMap(map);
    if (!isSameDate(model.date, date)) {
      throw const FormatException('Daily counter key and date do not match.');
    }
    return model;
  }

  Future<DailyCountsModel> incrementSocialCount({
    required SocialPlatform platform,
    required DateTime date,
    required DateTime activityTime,
  }) {
    final operation = _pendingWrite.then((_) async {
      void validate() => validateCountDate(
        date: date,
        activityTime: activityTime,
        now: _clock.now(),
      );
      validate();
      final previous = await _read(date);
      final instagram = platform == SocialPlatform.instagram;
      final updated = DailyCountsModel(
        date: normalizeDate(date),
        instagramCount: previous.instagramCount + (instagram ? 1 : 0),
        youtubeCount: previous.youtubeCount + (instagram ? 0 : 1),
        lastInstagramActivityAt: instagram
            ? activityTime.toLocal()
            : previous.lastInstagramActivityAt,
        lastYoutubeActivityAt: instagram
            ? previous.lastYoutubeActivityAt
            : activityTime.toLocal(),
      );
      // A queued read may have crossed midnight. Never write yesterday's record.
      validate();
      await _storage.put(
        dailyCountsBoxName,
        createDateKey(date),
        updated.toMap(),
      );
      return updated;
    });
    // Failed writes reach their caller without poisoning the next operation.
    _pendingWrite = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
