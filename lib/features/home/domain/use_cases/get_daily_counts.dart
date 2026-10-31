import 'package:injectable/injectable.dart';

import '../entities/daily_counts.dart';
import '../params/get_daily_counts_params.dart';
import '../repositories/home_repository.dart';

@injectable
class GetDailyCounts {
  GetDailyCounts(this._repository);

  final HomeRepository _repository;

  Future<DailyCounts> call(GetDailyCountsParams params) {
    return _repository.getDailyCounts(params.date);
  }
}
