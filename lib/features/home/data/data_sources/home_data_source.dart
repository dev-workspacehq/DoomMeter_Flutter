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
      date.dateKey,
    );
    if (map == null) {
      return DailyCountsModel(
        date: date.normalizedDate,
        instagramCount: 0,
        youtubeCount: 0,
      );
    }
    final model = DailyCountsModel.fromMap(map);
    if (!model.date.isSameCalendarDate(date)) {
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
      final updated = previous.copyWith(
        date: date.normalizedDate,
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
      await _storage.put(dailyCountsBoxName, date.dateKey, updated.toMap());
      return updated;
    });
    // Failed writes reach their caller without poisoning the next operation.
    _pendingWrite = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  /// Native records may update history. Their own date keys determine storage,
  /// independent of the selected Home date and the manual today-only guard.
  Future<DailyCountsModel> syncYouTubeDetectedCount({
    required DateTime date,
    required int detectedCount,
    required DateTime? lastActivityAt,
    required bool trackingEnabled,
  }) {
    final operation = _pendingWrite.then((_) async {
      if (detectedCount < 0 ||
          date.year < 1 ||
          date.year > 9999 ||
          (lastActivityAt != null &&
              lastActivityAt.millisecondsSinceEpoch < 0)) {
        throw const FormatException('Invalid detected daily count.');
      }
      final previous = await _read(date);
      final unchangedSnapshot =
          previous.lastSyncedYoutubeCount == detectedCount &&
          previous.lastSyncedYoutubeActivityAt == lastActivityAt?.toLocal();
      // After disabling tracking, rereading the same native snapshot must not
      // erase subsequent manual test taps. A new native snapshot is authoritative.
      if (unchangedSnapshot && !trackingEnabled) return previous;
      final updated = previous.copyWith(
        youtubeCount: detectedCount,
        lastYoutubeActivityAt: lastActivityAt?.toLocal(),
        lastSyncedYoutubeCount: detectedCount,
        lastSyncedYoutubeActivityAt: lastActivityAt?.toLocal(),
      );
      if (updated != previous) {
        await _storage.put(dailyCountsBoxName, date.dateKey, updated.toMap());
      }
      return updated;
    });
    _pendingWrite = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }
}
