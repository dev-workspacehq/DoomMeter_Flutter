import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../../../core/utils/calendar_date.dart';
import '../../../domain/entities/daily_counts.dart';

part 'home_state.freezed.dart';

@freezed
abstract class HomeState with _$HomeState {
  const HomeState._();

  const factory HomeState({
    required DateTime selectedDate,
    required DateTime today,
    DailyCounts? counts,
    @Default(false) bool isLoading,
    String? errorMessage,
  }) = _HomeState;

  /// A UI snapshot; write authorization always rechecks the clock in the domain.
  bool get isToday => selectedDate.isSameCalendarDate(today);
}
