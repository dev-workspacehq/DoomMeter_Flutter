import 'models/native_daily_scroll_count.dart';

abstract interface class ScrollTrackingService {
  bool get isSupported;
  Future<bool> isTrackingEnabled();
  Future<void> openAccessibilitySettings();
  Future<List<NativeDailyScrollCount>> getDetectedDailyCounts();
}

class ScrollTrackingException implements Exception {
  const ScrollTrackingException(this.message);
  final String message;
  @override
  String toString() => message;
}
