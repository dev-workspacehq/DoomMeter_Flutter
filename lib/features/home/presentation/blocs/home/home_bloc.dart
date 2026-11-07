import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../../../../core/platform/scroll_tracking/scroll_tracking_service.dart';
import '../../../../../core/utils/calendar_date.dart';
import '../../../../../core/utils/local_clock.dart';
import '../../../domain/params/get_daily_counts_params.dart';
import '../../../domain/params/increment_social_count_params.dart';
import '../../../domain/use_cases/get_daily_counts.dart';
import '../../../domain/use_cases/increment_social_count.dart';
import '../../../domain/use_cases/sync_detected_scroll_counts.dart';
import 'home_event.dart';
import 'home_state.dart';

@injectable
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc(
    this._getDailyCounts,
    this._incrementSocialCount,
    this._clock,
    this._tracking,
    this._syncDetectedCounts,
  ) : super(_initialState(_clock.now(), _tracking.isSupported)) {
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
  final ScrollTrackingService _tracking;
  final SyncDetectedScrollCounts _syncDetectedCounts;

  static HomeState _initialState(DateTime now, bool supported) => HomeState(
    selectedDate: now.normalizedDate,
    today: now.normalizedDate,
    isTrackingSupported: supported,
  );

  Future<void> _onEvent(HomeEvent event, Emitter<HomeState> emit) async {
    final now = _clock.now();
    final today = now.normalizedDate;
    if (event is HomeTrackingPermissionRequested) {
      try {
        await _tracking.openAccessibilitySettings();
      } catch (error) {
        if (!emit.isDone) {
          emit(
            state.copyWith(
              trackingErrorMessage: error is ScrollTrackingException
                  ? error.message
                  : 'Could not open accessibility settings. Please try again.',
            ),
          );
        }
      }
      return;
    }
    if (event is HomeSocialIncrementRequested) {
      // Recheck even if the screen was left open across midnight.
      if (!state.selectedDate.isSameCalendarDate(today)) {
        emit(state.copyWith(today: today));
        return;
      }
      if (event.platform == SocialPlatform.youtube &&
          !state.canManuallyIncrementYouTube) {
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
      } on AutomaticYouTubeTrackingEnabled {
        if (!emit.isDone) {
          emit(
            state.copyWith(
              isYouTubeTrackingEnabled: true,
              isTrackingStatusKnown: true,
            ),
          );
        }
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
    emit(
      state.copyWith(
        selectedDate: date,
        today: today,
        counts: null,
        isLoading: true,
        errorMessage: null,
      ),
    );
    if (event is! HomeDateChanged) {
      await _refreshTracking(emit);
      if (emit.isDone) return;
    }
    try {
      final counts = await _getDailyCounts(GetDailyCountsParams(date: date));
      if (emit.isDone) return;
      emit(
        state.copyWith(
          selectedDate: date,
          today: _clock.now().normalizedDate,
          counts: counts,
          isLoading: false,
        ),
      );
    } catch (_) {
      if (emit.isDone) return;
      emit(
        state.copyWith(
          selectedDate: date,
          today: _clock.now().normalizedDate,
          errorMessage: 'Unable to load this day. Please try again.',
        ),
      );
    }
  }

  Future<void> _refreshTracking(Emitter<HomeState> emit) async {
    emit(
      state.copyWith(
        isTrackingStatusLoading: true,
        isTrackingStatusKnown: false,
        trackingErrorMessage: null,
      ),
    );
    try {
      final enabled = await _tracking.isTrackingEnabled();
      if (emit.isDone) return;
      emit(
        state.copyWith(
          isYouTubeTrackingEnabled: enabled,
          isTrackingStatusKnown: true,
          isTrackingStatusLoading: false,
          isSyncingNativeCounts: true,
        ),
      );
      // Read even after permission is disabled, to collect the final native writes.
      await _syncDetectedCounts(trackingEnabled: enabled);
    } catch (error) {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            trackingErrorMessage: error is ScrollTrackingException
                ? error.message
                : 'Could not sync detected counts. Showing saved counts; please retry.',
          ),
        );
      }
    } finally {
      if (!emit.isDone) {
        emit(
          state.copyWith(
            isTrackingStatusLoading: false,
            isSyncingNativeCounts: false,
          ),
        );
      }
    }
  }
}
