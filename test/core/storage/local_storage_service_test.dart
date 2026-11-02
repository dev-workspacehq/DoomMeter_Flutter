import 'dart:io';

import 'package:doom_meter/core/storage/local_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  late Directory directory;
  late LocalStorageService storage;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('doom_meter_storage_');
    Hive.init(directory.path);
    storage = LocalStorageService(Hive);
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('reads a missing key from an unopened box', () async {
    expect(await storage.get<String>('settings', 'missing'), isNull);
  });

  test('persists values across closing and reopening Hive', () async {
    await storage.put<String>('settings', 'theme', 'dark');
    await Hive.close();
    Hive.init(directory.path);

    expect(await storage.get<String>('settings', 'theme'), 'dark');
    await storage.delete('settings', 'theme');
    expect(await storage.get<String>('settings', 'theme'), isNull);
    await storage.delete('settings', 'missing');
  });

  test('supports concurrent writes and mixed values in one box', () async {
    await Future.wait([
      storage.put<String>('settings', 'theme', 'dark'),
      storage.put<int>('settings', 'count', 3),
      storage.put<bool>('settings', 'enabled', true),
    ]);

    expect(await storage.get<String>('settings', 'theme'), 'dark');
    expect(await storage.get<int>('settings', 'count'), 3);
    expect(await storage.get<bool>('settings', 'enabled'), isTrue);
  });

  test('clear persists and leaves other boxes untouched', () async {
    await storage.put('settings', 'theme', 'dark');
    await storage.put('history', 'count', 3);
    await storage.clear('settings');
    await Hive.close();
    Hive.init(directory.path);

    expect(await storage.get<String>('settings', 'theme'), isNull);
    expect(await storage.get<int>('history', 'count'), 3);
  });

  test(
    'surfaces a mismatched read type instead of hiding corrupt data',
    () async {
      await storage.put<int>('settings', 'count', 3);
      await expectLater(
        storage.get<String>('settings', 'count'),
        throwsA(isA<TypeError>()),
      );
    },
  );
}
