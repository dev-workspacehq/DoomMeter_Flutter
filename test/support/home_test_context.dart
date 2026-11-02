import 'dart:io';

import 'package:doom_meter/core/storage/local_storage_service.dart';
import 'package:doom_meter/core/utils/local_clock.dart';
import 'package:doom_meter/features/home/data/data_sources/home_data_source.dart';
import 'package:doom_meter/features/home/data/repositories/home_repository_impl.dart';
import 'package:doom_meter/features/home/domain/use_cases/get_daily_counts.dart';
import 'package:doom_meter/features/home/domain/use_cases/increment_social_count.dart';
import 'package:doom_meter/features/home/domain/use_cases/sync_detected_scroll_counts.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_bloc.dart';
import 'package:hive/hive.dart';

import 'fake_scroll_tracking_service.dart';

class TestClock extends LocalClock {
  TestClock(this.time);
  DateTime time;
  @override
  DateTime now() => time;
}

class HomeTestContext {
  final tracking = FakeScrollTrackingService();
  final clock = TestClock(DateTime(2026, 10, 31, 15, 20, 42, 123, 456));
  late Directory directory;
  late LocalStorageService storage;
  late HomeDataSource source;
  late HomeRepositoryImpl repository;

  Future<void> initialize() async {
    directory = await Directory.systemTemp.createTemp('doom_meter_counts_');
    Hive.init(directory.path);
    storage = LocalStorageService(Hive);
    source = HomeDataSource(storage, clock);
    repository = HomeRepositoryImpl(source);
  }

  IncrementSocialCount get increment =>
      IncrementSocialCount(repository, clock, tracking);
  HomeBloc createBloc() => HomeBloc(
    GetDailyCounts(repository),
    increment,
    clock,
    tracking,
    SyncDetectedScrollCounts(tracking, repository),
  );

  Future<void> dispose() async {
    await Hive.close();
    await directory.delete(recursive: true);
  }
}
