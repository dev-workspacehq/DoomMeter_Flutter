import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

/// Exposes the Hive instance initialized by bootstrap for constructor injection.
@module
abstract class StorageModule {
  @lazySingleton
  HiveInterface get hive => Hive;
}
