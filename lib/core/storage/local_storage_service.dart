import 'dart:async';
import 'dart:developer' as developer;

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

  Future<void> put<T>(String box, String key, T value) =>
      _withBox('put', box, (storage) => storage.put(key, value));

  /// Returns null for a missing key; throws if the stored value is not a [T].
  Future<T?> get<T>(String box, String key) =>
      _withBox('get', box, (storage) => storage.get(key) as T?);

  Future<void> delete(String box, String key) =>
      _withBox('delete', box, (storage) => storage.delete(key));

  Future<void> clear(String box) => _withBox('clear', box, (storage) async {
    await storage.clear();
  });

  Future<T> _withBox<T>(
    String operation,
    String box,
    FutureOr<T> Function(Box<dynamic> storage) action,
  ) async {
    var stage = 'openBox';
    try {
      final storage = await _hive.openBox<dynamic>(box);
      stage = operation;
      return await action(storage);
    } catch (error, stackTrace) {
      developer.log(
        'Hive $stage failed for box "$box" during $operation.',
        name: 'LocalStorageService',
        level: 1000,
        error: error,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
