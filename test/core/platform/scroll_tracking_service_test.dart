import 'package:doom_meter/core/platform/scroll_tracking/constants/scroll_tracking_channel_constants.dart';
import 'package:doom_meter/core/platform/scroll_tracking/scroll_tracking_service.dart';
import 'package:doom_meter/core/platform/scroll_tracking/scroll_tracking_service_impl.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(ScrollTrackingChannelConstants.channel);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late ScrollTrackingServiceImpl service;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    service = ScrollTrackingServiceImpl();
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'one channel returns status and parses date keys and epoch milliseconds',
    () async {
      final time = DateTime(2026, 11, 1, 12).millisecondsSinceEpoch;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          ScrollTrackingChannelConstants.isEnabled => true,
          ScrollTrackingChannelConstants.dailyCounts => [
            {'date': '2026-11-01', 'youtubeCount': 25, 'lastActivityAt': time},
          ],
          _ => null,
        };
      });
      expect(await service.isTrackingEnabled(), isTrue);
      final record = (await service.getDetectedDailyCounts()).single;
      expect(record.date, DateTime(2026, 11, 1));
      expect(record.youtubeCount, 25);
      expect(record.lastActivityAt?.millisecondsSinceEpoch, time);
      await service.openAccessibilitySettings();
      expect(calls, [
        ScrollTrackingChannelConstants.isEnabled,
        ScrollTrackingChannelConstants.dailyCounts,
        ScrollTrackingChannelConstants.openSettings,
      ]);
    },
  );

  test(
    'rejects malformed records and duplicate dates before exposing a snapshot',
    () async {
      final valid = {
        'date': '2026-11-01',
        'youtubeCount': 25,
        'lastActivityAt': null,
      };
      for (final response in [
        null,
        true,
        [null],
        [
          {...valid, 'date': '2026-02-30'},
        ],
        [
          {...valid, 'youtubeCount': -1},
        ],
        [
          {...valid, 'youtubeCount': 2.5},
        ],
        [
          {...valid, 'lastActivityAt': -1},
        ],
        [
          {...valid, 'lastActivityAt': 'yesterday'},
        ],
        [valid, valid],
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async => response);
        await expectLater(
          service.getDetectedDailyCounts(),
          throwsA(isA<ScrollTrackingException>()),
        );
      }
    },
  );

  test(
    'missing channel and platform errors become controlled failures',
    () async {
      await expectLater(
        service.isTrackingEnabled(),
        throwsA(isA<ScrollTrackingException>()),
      );
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw PlatformException(code: 'storage'),
      );
      await expectLater(
        service.getDetectedDailyCounts(),
        throwsA(isA<ScrollTrackingException>()),
      );
    },
  );

  test('unsupported platforms do not invoke Android methods', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => fail('Unexpected native call'),
    );
    expect(service.isSupported, isFalse);
    expect(await service.isTrackingEnabled(), isFalse);
    expect(await service.getDetectedDailyCounts(), isEmpty);
    await expectLater(
      service.openAccessibilitySettings(),
      throwsA(isA<ScrollTrackingException>()),
    );
  });
}
