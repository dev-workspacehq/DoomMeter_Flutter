import 'package:doom_meter/core/platform/scroll_tracking/models/native_daily_scroll_count.dart';
import 'package:doom_meter/features/home/domain/params/increment_social_count_params.dart';
import 'package:doom_meter/features/home/domain/use_cases/increment_social_count.dart';
import 'package:doom_meter/features/home/domain/use_cases/sync_detected_scroll_counts.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_bloc.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_event.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../support/home_test_context.dart';

Future<HomeState> load(HomeBloc bloc, HomeEvent event) {
  final ready = bloc.stream
      .skipWhile((s) => !s.isLoading)
      .firstWhere((s) => !s.isLoading)
      .timeout(const Duration(seconds: 5));
  bloc.add(event);
  return ready;
}

void main() {
  late HomeTestContext context;
  setUp(() async {
    context = HomeTestContext();
    await context.initialize();
  });
  tearDown(() async {
    await context.dispose();
  });

  test(
    'absolute sync is repeatable and preserves Instagram and historical dates',
    () async {
      final now = context.clock.now();
      await context.increment(
        IncrementSocialCountParams(
          platform: SocialPlatform.instagram,
          date: now,
          activityTime: now,
        ),
      );
      context.tracking.records = [
        NativeDailyScrollCount(
          date: DateTime(2026, 10, 31),
          youtubeCount: 25,
          lastActivityAt: now,
        ),
        NativeDailyScrollCount(
          date: DateTime(2026, 10, 30),
          youtubeCount: 18,
          lastActivityAt: DateTime(2026, 10, 30, 18),
        ),
      ];
      final sync = SyncDetectedScrollCounts(
        context.tracking,
        context.repository,
      );
      for (var i = 0; i < 3; i++) {
        await sync(trackingEnabled: true);
      }
      final today = await context.repository.getDailyCounts(now);
      expect(today.youtubeCount, 25);
      expect(today.instagramCount, 1);
      expect(today.lastInstagramActivityAt, now);
      expect(today.lastYoutubeActivityAt, now);
      expect(
        (await context.repository.getDailyCounts(
          DateTime(2026, 10, 30),
        )).youtubeCount,
        18,
      );
      // Native is authoritative even if it is lower than a previous/manual total.
      await context.repository.syncYouTubeDetectedCount(
        date: now,
        detectedCount: 4,
        lastActivityAt: now,
        trackingEnabled: true,
      );
      expect((await context.repository.getDailyCounts(now)).youtubeCount, 4);
    },
  );

  test(
    'unchanged disabled snapshots preserve manual taps; new snapshots replace them',
    () async {
      final now = context.clock.now();
      Future<void> sync(int count, bool enabled) async {
        await context.repository.syncYouTubeDetectedCount(
          date: now,
          detectedCount: count,
          lastActivityAt: now,
          trackingEnabled: enabled,
        );
      }

      await sync(5, true);
      await context.increment(
        IncrementSocialCountParams(
          platform: SocialPlatform.youtube,
          date: now,
          activityTime: now,
        ),
      );
      await sync(5, false);
      expect((await context.repository.getDailyCounts(now)).youtubeCount, 6);
      await Hive.close();
      await sync(5, false);
      expect((await context.repository.getDailyCounts(now)).youtubeCount, 6);
      await sync(7, false);
      expect((await context.repository.getDailyCounts(now)).youtubeCount, 7);
      await sync(5, true);
      expect((await context.repository.getDailyCounts(now)).youtubeCount, 5);
    },
  );

  test(
    'sync and concurrent manual Instagram writes share one storage queue',
    () async {
      final now = context.clock.now();
      await Future.wait([
        for (var i = 0; i < 20; i++)
          context.increment(
            IncrementSocialCountParams(
              platform: SocialPlatform.instagram,
              date: now,
              activityTime: now,
            ),
          ),
        context.repository.syncYouTubeDetectedCount(
          date: now,
          detectedCount: 12,
          lastActivityAt: now,
          trackingEnabled: true,
        ),
      ]);
      final counts = await context.repository.getDailyCounts(now);
      expect(counts.instagramCount, 20);
      expect(counts.youtubeCount, 12);
    },
  );

  test(
    'automatic tracking blocks manual YouTube through the use case and Bloc',
    () async {
      context.tracking.enabled = true;
      final now = context.clock.now();
      await expectLater(
        context.increment(
          IncrementSocialCountParams(
            platform: SocialPlatform.youtube,
            date: now,
            activityTime: now,
          ),
        ),
        throwsA(isA<AutomaticYouTubeTrackingEnabled>()),
      );
      final bloc = context.createBloc();
      addTearDown(bloc.close);
      await load(bloc, const HomeStarted());
      bloc.add(const HomeSocialIncrementRequested(SocialPlatform.youtube));
      final state = await load(bloc, const HomeNativeCountsSyncRequested());
      expect(state.canManuallyIncrementYouTube, isFalse);
      expect(state.counts?.youtubeCount, 0);
    },
  );

  test(
    'startup and resume sync native history while keeping the selected date',
    () async {
      context.tracking.enabled = true;
      context.tracking.records = [
        NativeDailyScrollCount(date: DateTime(2026, 10, 31), youtubeCount: 10),
      ];
      final bloc = context.createBloc();
      addTearDown(bloc.close);
      expect((await load(bloc, const HomeStarted())).counts?.youtubeCount, 10);
      await load(bloc, HomeDateChanged(DateTime(2026, 10, 30)));
      context.tracking.records = [
        NativeDailyScrollCount(date: DateTime(2026, 10, 31), youtubeCount: 15),
        NativeDailyScrollCount(date: DateTime(2026, 10, 30), youtubeCount: 3),
      ];
      final resumed = await load(bloc, const HomeResumed());
      expect(resumed.selectedDate, DateTime(2026, 10, 30));
      expect(resumed.counts?.youtubeCount, 3);
      expect(
        (await context.repository.getDailyCounts(
          context.clock.now(),
        )).youtubeCount,
        15,
      );
      context.tracking.enabled = false;
      expect(
        (await load(bloc, const HomeResumed())).isYouTubeTrackingEnabled,
        isFalse,
      );
    },
  );

  test('status and sync errors retain saved counts and permit retry', () async {
    final now = context.clock.now();
    await context.increment(
      IncrementSocialCountParams(
        platform: SocialPlatform.instagram,
        date: now,
        activityTime: now,
      ),
    );
    context.tracking.failStatus = true;
    final bloc = context.createBloc();
    addTearDown(bloc.close);
    final failed = await load(bloc, const HomeStarted());
    expect(failed.counts?.instagramCount, 1);
    expect(failed.trackingErrorMessage, isNotNull);
    expect(failed.canManuallyIncrementYouTube, isFalse);
    context.tracking.failStatus = false;
    context.tracking.failSync = true;
    expect((await load(bloc, const HomeResumed())).counts?.instagramCount, 1);
    context.tracking.failSync = false;
    expect(
      (await load(bloc, const HomeRetryRequested())).trackingErrorMessage,
      isNull,
    );
  });
}
