import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../core/utils/calendar_date.dart';

part 'daily_counts_model.freezed.dart';

@freezed
abstract class DailyCountsModel with _$DailyCountsModel {
  const DailyCountsModel._();

  const factory DailyCountsModel({
    required DateTime date,
    required int instagramCount,
    required int youtubeCount,
    DateTime? lastInstagramActivityAt,
    DateTime? lastYoutubeActivityAt,
    // Native checkpoint metadata stays in the same atomic daily Hive record.
    int? lastSyncedYoutubeCount,
    DateTime? lastSyncedYoutubeActivityAt,
  }) = _DailyCountsModel;

  factory DailyCountsModel.fromMap(Map<dynamic, dynamic> map) {
    final dateValue = map['date'];

    final date = dateValue is String ? DateTime.tryParse(dateValue) : null;

    if (date == null || date.dateKey != dateValue) {
      throw const FormatException('Invalid daily counter date.');
    }

    return DailyCountsModel(
      date: date.normalizedDate,
      instagramCount: _readCount(map['instagramCount']),
      youtubeCount: _readCount(map['youtubeCount']),
      lastInstagramActivityAt: _readTime(map['lastInstagramActivityAt']),
      lastYoutubeActivityAt: _readTime(map['lastYoutubeActivityAt']),
      lastSyncedYoutubeCount: map['lastSyncedYoutubeCount'] == null
          ? null
          : _readCount(map['lastSyncedYoutubeCount']),
      lastSyncedYoutubeActivityAt: _readTime(
        map['lastSyncedYoutubeActivityAt'],
      ),
    );
  }

  Map<String, Object?> toMap() {
    return {
      'date': date.dateKey,
      'instagramCount': instagramCount,
      'youtubeCount': youtubeCount,
      'lastInstagramActivityAt': lastInstagramActivityAt
          ?.toLocal()
          .toIso8601String(),
      'lastYoutubeActivityAt': lastYoutubeActivityAt
          ?.toLocal()
          .toIso8601String(),
      'lastSyncedYoutubeCount': lastSyncedYoutubeCount,
      'lastSyncedYoutubeActivityAt': lastSyncedYoutubeActivityAt
          ?.toLocal()
          .toIso8601String(),
    };
  }

  static int _readCount(Object? value) {
    if (value is! int || value < 0) {
      throw const FormatException('Invalid daily counter value.');
    }

    return value;
  }

  static DateTime? _readTime(Object? value) {
    if (value == null) {
      return null;
    }

    final time = value is String ? DateTime.tryParse(value) : null;

    if (time == null) {
      throw const FormatException('Invalid activity timestamp.');
    }

    return time.toLocal();
  }
}
