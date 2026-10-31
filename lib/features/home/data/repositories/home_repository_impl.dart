import 'package:injectable/injectable.dart';

import '../../domain/entities/daily_counts.dart';
import '../../domain/params/increment_social_count_params.dart';
import '../../domain/repositories/home_repository.dart';
import '../data_sources/home_data_source.dart';
import '../mappers/daily_counts_mapper.dart';

@LazySingleton(as: HomeRepository)
class HomeRepositoryImpl implements HomeRepository {
  HomeRepositoryImpl(this._dataSource);

  final HomeDataSource _dataSource;

  @override
  Future<DailyCounts> getDailyCounts(DateTime date) async {
    return (await _dataSource.getDailyCounts(date)).toEntity();
  }

  @override
  Future<DailyCounts> incrementSocialCount({
    required SocialPlatform platform,
    required DateTime date,
    required DateTime activityTime,
  }) async {
    return (await _dataSource.incrementSocialCount(
      platform: platform,
      date: date,
      activityTime: activityTime,
    )).toEntity();
  }
}
