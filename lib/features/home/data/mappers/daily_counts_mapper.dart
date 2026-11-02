import '../../domain/entities/daily_counts.dart';
import '../models/daily_counts_model.dart';

extension DailyCountsMapper on DailyCountsModel {
  DailyCounts toEntity() => DailyCounts(
    date: date,
    instagramCount: instagramCount,
    youtubeCount: youtubeCount,
    lastInstagramActivityAt: lastInstagramActivityAt,
    lastYoutubeActivityAt: lastYoutubeActivityAt,
  );
}

extension DailyCountsModelMapper on DailyCounts {
  DailyCountsModel toModel() => DailyCountsModel(
    date: date,
    instagramCount: instagramCount,
    youtubeCount: youtubeCount,
    lastInstagramActivityAt: lastInstagramActivityAt,
    lastYoutubeActivityAt: lastYoutubeActivityAt,
  );
}
