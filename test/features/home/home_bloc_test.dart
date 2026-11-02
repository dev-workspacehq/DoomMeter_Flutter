import 'package:doom_meter/core/utils/calendar_date.dart';
import 'package:doom_meter/features/home/domain/params/increment_social_count_params.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_bloc.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_event.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/home_test_context.dart';

Future<HomeState> _load(HomeBloc bloc, HomeEvent event) {
  final loaded = bloc.stream
      .skipWhile((state) => !state.isLoading)
      .firstWhere((state) => !state.isLoading)
      .timeout(const Duration(seconds: 5));
  bloc.add(event);
  return loaded;
}

Future<HomeState> _increment(
  HomeBloc bloc,
  SocialPlatform platform,
  int total,
) {
  final saved = bloc.stream
      .firstWhere((state) => state.counts?.totalCount == total)
      .timeout(const Duration(seconds: 5));
  bloc.add(HomeSocialIncrementRequested(platform));
  return saved;
}

void main() {
  late HomeTestContext context;
  late HomeBloc bloc;
  setUp(() async {
    context = HomeTestContext();
    await context.initialize();
    bloc = context.createBloc();
  });
  tearDown(() async {
    await bloc.close();
    await context.dispose();
  });

  test(
    'fresh start, saved increments, and Bloc recreation restore today',
    () async {
      final initial = await _load(bloc, const HomeStarted());
      expect(initial.selectedDate, DateTime(2026, 10, 31));
      expect(initial.counts?.totalCount, 0);
      await _increment(bloc, SocialPlatform.instagram, 1);
      await _increment(bloc, SocialPlatform.instagram, 2);
      final saved = await _increment(bloc, SocialPlatform.youtube, 3);
      expect(saved.counts?.instagramCount, 2);
      expect(saved.counts?.youtubeCount, 1);
      expect(saved.counts?.lastInstagramActivityAt, context.clock.now());

      await bloc.close();
      bloc = context.createBloc();
      final restored = await _load(bloc, const HomeStarted());
      expect(restored.counts?.instagramCount, 2);
      expect(restored.counts?.youtubeCount, 1);
    },
  );

  test('15 rapid Instagram and 3 YouTube events lose no increments', () async {
    await _load(bloc, const HomeStarted());
    final finished = bloc.stream
        .firstWhere((s) => s.counts?.totalCount == 18)
        .timeout(const Duration(seconds: 5));
    for (var i = 0; i < 15; i++) {
      bloc.add(const HomeSocialIncrementRequested(SocialPlatform.instagram));
    }
    for (var i = 0; i < 3; i++) {
      bloc.add(const HomeSocialIncrementRequested(SocialPlatform.youtube));
    }
    final saved = await finished;
    expect(saved.counts?.instagramCount, 15);
    expect(saved.counts?.youtubeCount, 3);
  });

  test(
    'history/future are read-only and returning to today restores editability',
    () async {
      context.clock.time = DateTime(2026, 10, 30, 18);
      await _load(bloc, const HomeStarted());
      await _increment(bloc, SocialPlatform.instagram, 1);
      context.clock.time = DateTime(2026, 10, 31, 12);
      await _load(bloc, const HomeStarted());
      await _increment(bloc, SocialPlatform.youtube, 1);

      for (final date in [DateTime(2026, 10, 30), DateTime(2026, 11, 1)]) {
        final history = await _load(bloc, HomeDateChanged(date));
        expect(history.isToday, isFalse);
        bloc.add(const HomeSocialIncrementRequested(SocialPlatform.instagram));
        final refreshed = await _load(bloc, const HomeRetryRequested());
        expect(refreshed.counts?.totalCount, history.counts?.totalCount);
      }
      final today = await _load(bloc, HomeDateChanged(context.clock.now()));
      expect(today.isToday, isTrue);
      expect(today.counts?.youtubeCount, 1);
      await _increment(bloc, SocialPlatform.instagram, 2);
    },
  );

  test(
    'navigation queued between taps cannot apply writes to another day',
    () async {
      await _load(bloc, const HomeStarted());
      final finished = bloc.stream
          .firstWhere((s) => s.counts?.totalCount == 2)
          .timeout(const Duration(seconds: 5));
      bloc
        ..add(const HomeSocialIncrementRequested(SocialPlatform.instagram))
        ..add(HomeDateChanged(DateTime(2026, 10, 30)))
        ..add(const HomeSocialIncrementRequested(SocialPlatform.youtube))
        ..add(HomeDateChanged(context.clock.now()))
        ..add(const HomeSocialIncrementRequested(SocialPlatform.instagram));
      final saved = await finished;
      expect(saved.counts?.instagramCount, 2);
      expect(saved.counts?.youtubeCount, 0);
      expect(
        (await context.repository.getDailyCounts(
          DateTime(2026, 10, 30),
        )).totalCount,
        0,
      );
    },
  );

  test('a stale today screen cannot edit yesterday after midnight', () async {
    await _load(bloc, const HomeStarted());
    await _increment(bloc, SocialPlatform.instagram, 1);
    context.clock.time = DateTime(2026, 11, 1, 0, 1);
    final readOnly = bloc.stream.firstWhere((s) => !s.isToday);
    bloc.add(const HomeSocialIncrementRequested(SocialPlatform.instagram));
    expect((await readOnly).counts?.instagramCount, 1);
    expect(
      (await context.repository.getDailyCounts(
        DateTime(2026, 10, 31),
      )).instagramCount,
      1,
    );
  });

  test(
    'resume advances a today view to new day without resetting old data',
    () async {
      await _load(bloc, const HomeStarted());
      await _increment(bloc, SocialPlatform.instagram, 1);
      context.clock.time = DateTime(2026, 11, 1, 9);
      final resumed = await _load(bloc, const HomeResumed());
      expect(resumed.selectedDate, context.clock.now().normalizedDate);
      expect(resumed.counts?.totalCount, 0);
      expect(
        (await context.repository.getDailyCounts(
          DateTime(2026, 10, 31),
        )).instagramCount,
        1,
      );
      await _load(bloc, HomeDateChanged(DateTime(2026, 10, 30)));
      context.clock.time = DateTime(2026, 11, 2);
      expect(
        (await _load(bloc, const HomeResumed())).selectedDate,
        DateTime(2026, 10, 30),
      );
    },
  );
}
