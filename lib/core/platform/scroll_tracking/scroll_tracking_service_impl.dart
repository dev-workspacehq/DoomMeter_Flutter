import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import 'constants/scroll_tracking_channel_constants.dart';
import 'models/native_daily_scroll_count.dart';
import 'scroll_tracking_service.dart';

@LazySingleton(as: ScrollTrackingService)
class ScrollTrackingServiceImpl implements ScrollTrackingService {
  static const _channel = MethodChannel(ScrollTrackingChannelConstants.channel);

  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<Object?> _invoke(String method) async {
    try {
      return await _channel
          .invokeMethod<Object?>(method)
          .timeout(const Duration(seconds: 5));
    } on MissingPluginException {
      throw const ScrollTrackingException(
        'Tracking is unavailable. Install an Android build with tracking support.',
      );
    } on PlatformException {
      throw const ScrollTrackingException(
        'Android tracking could not be accessed. Please try again.',
      );
    } on TimeoutException {
      throw const ScrollTrackingException(
        'Android tracking did not respond. Please try again.',
      );
    }
  }

  @override
  Future<bool> isTrackingEnabled() async {
    if (!isSupported) return false;
    final result = await _invoke(ScrollTrackingChannelConstants.isEnabled);
    if (result is! bool) {
      throw const ScrollTrackingException('Invalid Android tracking status.');
    }
    return result;
  }

  @override
  Future<void> openAccessibilitySettings() async {
    if (!isSupported) {
      throw const ScrollTrackingException(
        'Automatic tracking is available on Android.',
      );
    }
    await _invoke(ScrollTrackingChannelConstants.openSettings);
  }

  @override
  Future<List<NativeDailyScrollCount>> getDetectedDailyCounts() async {
    if (!isSupported) return const [];
    final result = await _invoke(ScrollTrackingChannelConstants.dailyCounts);
    try {
      if (result is! List) throw const FormatException();
      final dates = <DateTime>{};
      return result
          .map((item) {
            if (item is! Map) throw const FormatException();
            final record = NativeDailyScrollCount.fromMap(
              Map<Object?, Object?>.from(item),
            );
            if (!dates.add(record.date)) throw const FormatException();
            return record;
          })
          .toList(growable: false);
    } on FormatException {
      throw const ScrollTrackingException(
        'Android returned invalid tracking data. Saved counts were kept.',
      );
    }
  }
}
