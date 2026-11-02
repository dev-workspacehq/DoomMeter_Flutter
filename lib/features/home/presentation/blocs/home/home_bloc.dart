import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../../core/utils/calendar_date.dart';
import '../../../../../core/utils/local_clock.dart';
import '../../../domain/params/get_daily_counts_params.dart';
import '../../../domain/params/increment_social_count_params.dart';
import '../../../domain/use_cases/get_daily_counts.dart';
import '../../../domain/use_cases/increment_social_count.dart';
import 'home_event.dart';
import 'home_state.dart';

@injectable
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc(this._getDailyCounts, this._incrementSocialCount, this._clock)
    : super(_initialState(_clock.now())) {
    // One queue for reads, writes and navigation: never lose taps or apply a
    // saved count to a different day. Storage also serializes across Bloc callers.
    on<HomeEvent>(
      _onEvent,
      transformer: (events, mapper) => events.asyncExpand(mapper),
    );
  }

  final GetDailyCounts _getDailyCounts;
  final IncrementSocialCount _incrementSocialCount;
  final LocalClock _clock;

  static HomeState _initialState(DateTime now) =>
      HomeState(selectedDate: now.normalizedDate, today: now.normalizedDate);

  Future<void> _onEvent(HomeEvent event, Emitter<HomeState> emit) async {
    final now = _clock.now();
    final today = now.normalizedDate;
    if (event is HomeSocialIncrementRequested) {
      // Recheck even if the screen was left open across midnight.
      if (!state.selectedDate.isSameCalendarDate(today)) {
        emit(state.copyWith(today: today));
        return;
      }
      try {
        final counts = await _incrementSocialCount(
          IncrementSocialCountParams(
            platform: event.platform,
            date: state.selectedDate,
            activityTime: now,
          ),
        );
        if (emit.isDone) return;
        emit(
          state.copyWith(
            today: _clock.now().normalizedDate,
            counts: counts,
            errorMessage: null,
          ),
        );
      } on ReadOnlyCountDate {
        if (!emit.isDone) {
          emit(state.copyWith(today: _clock.now().normalizedDate));
        }
      } catch (_) {
        if (!emit.isDone) {
          emit(
            state.copyWith(
              today: _clock.now().normalizedDate,
              errorMessage: 'Could not save this activity. Please try again.',
            ),
          );
        }
      }
      return;
    }

    final date = switch (event) {
      HomeStarted() => today,
      HomeDateChanged(:final date) => date.normalizedDate,
      HomeResumed() => state.isToday ? today : state.selectedDate,
      _ => state.selectedDate,
    };
    emit(HomeState(selectedDate: date, today: today, isLoading: true));
    try {
      final counts = await _getDailyCounts(GetDailyCountsParams(date: date));
      if (emit.isDone) return;
      emit(
        HomeState(
          selectedDate: date,
          today: _clock.now().normalizedDate,
          counts: counts,
        ),
      );
    } catch (_) {
      if (emit.isDone) return;
      emit(
        HomeState(
          selectedDate: date,
          today: _clock.now().normalizedDate,
          errorMessage: 'Unable to load this day. Please try again.',
        ),
      );
    }
  }
}
