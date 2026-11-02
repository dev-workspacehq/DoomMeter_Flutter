import 'package:injectable/injectable.dart';

import '../../../../core/platform/scroll_tracking/scroll_tracking_service.dart';
import '../repositories/home_repository.dart';

@injectable
class SyncDetectedScrollCounts {
  SyncDetectedScrollCounts(this._tracking, this._repository);

  final ScrollTrackingService _tracking;
  final HomeRepository _repository;

  Future<void> call({required bool trackingEnabled}) async {
    final records = await _tracking.getDetectedDailyCounts();
    for (final record in records) {
      await _repository.syncYouTubeDetectedCount(
        date: record.date,
        detectedCount: record.youtubeCount,
        lastActivityAt: record.lastActivityAt,
        trackingEnabled: trackingEnabled,
      );
    }
  }
}
