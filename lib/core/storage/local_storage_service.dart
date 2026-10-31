import 'package:hive/hive.dart';
import 'package:injectable/injectable.dart';

/// Shared persistence for repositories. Hive must be initialized at startup.
///
/// Operations open boxes on demand. Values must be Hive-supported primitives,
/// lists/maps of supported values, or types with registered adapters.
@lazySingleton
class LocalStorageService {
  LocalStorageService(this._hive);

  final HiveInterface _hive;

  Future<void> put<T>(String box, String key, T value) async {
    final storage = await _hive.openBox<dynamic>(box);
    await storage.put(key, value);
  }

  /// Returns null for a missing key; throws if the stored value is not a [T].
  Future<T?> get<T>(String box, String key) async {
    final storage = await _hive.openBox<dynamic>(box);
    return storage.get(key) as T?;
  }

  Future<void> delete(String box, String key) async {
    final storage = await _hive.openBox<dynamic>(box);
    await storage.delete(key);
  }
}
