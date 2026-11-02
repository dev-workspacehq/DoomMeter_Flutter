import 'package:doom_meter/core/platform/scroll_tracking/models/native_daily_scroll_count.dart';
import 'package:doom_meter/core/platform/scroll_tracking/scroll_tracking_service.dart';

class FakeScrollTrackingService implements ScrollTrackingService {
  @override
  bool isSupported = true;
  bool enabled = false;
  bool failStatus = false;
  bool failSync = false;
  int settingsOpened = 0;
  int reads = 0;
  List<NativeDailyScrollCount> records = [];

  @override
  Future<bool> isTrackingEnabled() async {
    if (failStatus) throw const ScrollTrackingException('Tracking unavailable');
    return enabled;
  }

  @override
  Future<void> openAccessibilitySettings() async {
    settingsOpened++;
  }

  @override
  Future<List<NativeDailyScrollCount>> getDetectedDailyCounts() async {
    reads++;
    if (failSync) throw const ScrollTrackingException('Sync unavailable');
    return records;
  }
}
