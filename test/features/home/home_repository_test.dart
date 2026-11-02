import 'dart:async';

import 'package:doom_meter/core/storage/local_storage_service.dart';
import 'package:doom_meter/core/utils/calendar_date.dart';
import 'package:doom_meter/features/home/data/data_sources/home_data_source.dart';
import 'package:doom_meter/features/home/data/mappers/daily_counts_mapper.dart';
import 'package:doom_meter/features/home/data/models/daily_counts_model.dart';
import 'package:doom_meter/features/home/data/repositories/home_repository_impl.dart';
import 'package:doom_meter/features/home/domain/params/increment_social_count_params.dart';
import 'package:doom_meter/features/home/domain/use_cases/increment_social_count.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../../support/home_test_context.dart';

class _ControlledStorage extends LocalStorageService {
  _ControlledStorage() : super(Hive);
  bool failWrite = false;
  Completer<void>? readGate;
  @override
  Future<T?> get<T>(String box, String key) async {
    final value = await super.get<T>(box, key);
    await readGate?.future;
    return value;
  }

  @override
  Future<void> put<T>(String box, String key, T value) async {
    if (failWrite) {
      failWrite = false;
      throw StateError('disk unavailable');
    }
    await super.put(box, key, value);
  }
}

void main() {
  late HomeTestContext context;
  setUp(() async {
    context = HomeTestContext();
    await context.initialize();
  });
  tearDown(() => context.dispose());

  Future<void> increment(SocialPlatform platform) async {
    await context.increment(
      IncrementSocialCountParams(
        platform: platform,
        date: context.clock.now(),
        activityTime: context.clock.now(),
      ),
    );
  }

  test(
    'missing dates return zero/null and viewing creates no record',
    () async {
      for (final date in [
        DateTime(2026, 10, 30),
        context.clock.now(),
        DateTime(2026, 11, 1),
      ]) {
        final counts = await context.repository.getDailyCounts(date);
        expect(counts.totalCount, 0);
        expect(counts.lastInstagramActivityAt, isNull);
        expect(counts.lastYoutubeActivityAt, isNull);
      }
      expect(Hive.box<dynamic>(dailyCountsBoxName).isEmpty, isTrue);
    },
  );

  test(
    'platform timestamps are exact, independent, and survive reopening Hive',
    () async {
      final instagramTime = context.clock.now();
      await increment(SocialPlatform.instagram);
      context.clock.time = DateTime(2026, 10, 31, 16, 25, 10, 789, 12);
      final youtubeTime = context.clock.now();
      await increment(SocialPlatform.youtube);
      await increment(SocialPlatform.youtube);
      final before = await context.repository.getDailyCounts(
        context.clock.now(),
      );
      expect(before.instagramCount, 1);
      expect(before.youtubeCount, 2);
      expect(before.lastInstagramActivityAt, instagramTime);
      expect(before.lastYoutubeActivityAt, youtubeTime);
      expect(Hive.box<dynamic>(dailyCountsBoxName).keys, ['2026-10-31']);
      final raw =
          Hive.box<dynamic>(dailyCountsBoxName).get('2026-10-31') as Map;
      expect(raw['lastInstagramActivityAt'], instagramTime.toIso8601String());
      expect(raw.containsKey('totalCount'), isFalse);

      await Hive.close();
      Hive.init(context.directory.path);
      final recreated = HomeRepositoryImpl(
        HomeDataSource(LocalStorageService(Hive), context.clock),
      );
      final restored = await recreated.getDailyCounts(context.clock.now());
      expect(restored.instagramCount, 1);
      expect(restored.youtubeCount, 2);
      expect(restored.lastInstagramActivityAt, instagramTime);
      expect(restored.lastYoutubeActivityAt, youtubeTime);
      final roundTrip = restored.toModel().toEntity();
      expect(roundTrip.lastInstagramActivityAt, instagramTime);
      expect(roundTrip.totalCount, 3);
    },
  );

  test(
    'concurrent callers share one atomic read-increment-write queue',
    () async {
      await Future.wait(
        List.generate(5, (_) => increment(SocialPlatform.instagram)),
      );
      await Future.wait([
        ...List.generate(10, (_) => increment(SocialPlatform.instagram)),
        ...List.generate(3, (_) => increment(SocialPlatform.youtube)),
      ]);
      final counts = await context.repository.getDailyCounts(
        context.clock.now(),
      );
      expect(counts.instagramCount, 15);
      expect(counts.youtubeCount, 3);
    },
  );

  test(
    'past/future writes are rejected by both use case and repository boundary',
    () async {
      for (final date in [DateTime(2026, 10, 30), DateTime(2026, 11, 1)]) {
        await expectLater(
          context.increment(
            IncrementSocialCountParams(
              platform: SocialPlatform.instagram,
              date: date,
              activityTime: date,
            ),
          ),
          throwsA(isA<ReadOnlyCountDate>()),
        );
        await expectLater(
          context.repository.incrementSocialCount(
            platform: SocialPlatform.youtube,
            date: date,
            activityTime: context.clock.now(),
          ),
          throwsA(isA<ReadOnlyCountDate>()),
        );
      }
      await increment(SocialPlatform.instagram);
      expect(Hive.box<dynamic>(dailyCountsBoxName).keys, ['2026-10-31']);
    },
  );

  test('mismatched activity day cannot alter today', () async {
    await expectLater(
      context.increment(
        IncrementSocialCountParams(
          platform: SocialPlatform.instagram,
          date: context.clock.now(),
          activityTime: DateTime(2026, 10, 30),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      (await context.repository.getDailyCounts(context.clock.now())).totalCount,
      0,
    );
  });

  test(
    'new calendar day naturally starts empty and retains yesterday',
    () async {
      await increment(SocialPlatform.instagram);
      final yesterday = context.clock.now();
      context.clock.time = DateTime(2026, 11, 1, 0, 1);
      expect(
        (await context.repository.getDailyCounts(
          context.clock.now(),
        )).totalCount,
        0,
      );
      await increment(SocialPlatform.youtube);
      expect(
        (await context.repository.getDailyCounts(yesterday)).instagramCount,
        1,
      );
      expect(
        (await context.repository.getDailyCounts(
          context.clock.now(),
        )).youtubeCount,
        1,
      );
    },
  );

  test('failed write does not poison queue or invent an increment', () async {
    final storage = _ControlledStorage()..failWrite = true;
    final source = HomeDataSource(storage, context.clock);
    Future<DailyCountsModel> write() => source.incrementSocialCount(
      platform: SocialPlatform.instagram,
      date: context.clock.now(),
      activityTime: context.clock.now(),
    );
    await expectLater(write(), throwsStateError);
    expect((await write()).instagramCount, 1);
  });

  test('rechecks today when a pending read crosses midnight', () async {
    final storage = _ControlledStorage()..readGate = Completer<void>();
    final source = HomeDataSource(storage, context.clock);
    final pending = source.incrementSocialCount(
      platform: SocialPlatform.instagram,
      date: context.clock.now(),
      activityTime: context.clock.now(),
    );
    final rejected = expectLater(pending, throwsA(isA<ReadOnlyCountDate>()));
    await pumpEventQueue();
    context.clock.time = DateTime(2026, 11, 1);
    storage.readGate!.complete();
    await rejected;
    expect(Hive.box<dynamic>(dailyCountsBoxName).isEmpty, isTrue);
  });

  test(
    'corrupt data is surfaced and never silently reset/overwritten',
    () async {
      await context.storage.put(dailyCountsBoxName, '2026-10-31', {
        'date': '2026-10-31',
        'instagramCount': 'invalid',
        'youtubeCount': 2,
      });
      await expectLater(
        increment(SocialPlatform.instagram),
        throwsFormatException,
      );
      final raw = await context.storage.get<Map>(
        dailyCountsBoxName,
        '2026-10-31',
      );
      expect(raw?['instagramCount'], 'invalid');
    },
  );

  test('date keys normalize hours and preserve calendar boundaries', () {
    expect(DateTime(2026, 10, 31, 10).dateKey, '2026-10-31');
    expect(DateTime(2026, 10, 31, 23).dateKey, '2026-10-31');
    expect(DateTime(2028, 2, 29).dateKey, '2028-02-29');
    expect(DateTime(2026, 12, 32).dateKey, '2027-01-01');
  });
}
