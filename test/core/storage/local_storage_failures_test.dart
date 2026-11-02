import 'package:doom_meter/core/storage/local_storage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class _StubHive implements HiveInterface {
  _StubHive(this.open);
  final Future<Box<dynamic>> Function() open;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #openBox) return open();
    return super.noSuchMethod(invocation);
  }
}

class _FailingBox implements Box<dynamic> {
  _FailingBox(this.error, this.stack);
  final Object error;
  final StackTrace stack;

  @override
  dynamic get(dynamic key, {dynamic defaultValue}) =>
      Error.throwWithStackTrace(error, stack);

  @override
  Future<void> put(dynamic key, dynamic value) => Future.error(error, stack);

  @override
  Future<void> delete(dynamic key) => Future.error(error, stack);

  @override
  Future<int> clear() => Future.error(error, stack);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> expectOriginalFailure(
  Future<void> Function() action,
  Object original,
  StackTrace origin,
) async {
  try {
    await action();
    fail('Storage failure was swallowed.');
  } catch (error, stack) {
    expect(error, same(original));
    expect(stack.toString(), contains(origin.toString()));
  }
}

void main() {
  final operations = <String, Future<void> Function(LocalStorageService)>{
    'get': (s) async {
      await s.get<String>('settings', 'key');
    },
    'put': (s) => s.put('settings', 'key', 'value'),
    'delete': (s) => s.delete('settings', 'key'),
    'clear': (s) => s.clear('settings'),
  };
  for (final operation in operations.entries) {
    test('${operation.key} preserves openBox error and stack trace', () async {
      final error = StateError('Box could not be opened');
      final stack = StackTrace.fromString('original openBox failure');
      final storage = LocalStorageService(
        _StubHive(() => Future.error(error, stack)),
      );
      await expectOriginalFailure(() => operation.value(storage), error, stack);
    });
    test(
      '${operation.key} preserves operation error and stack trace',
      () async {
        final error = StateError('Storage operation failed');
        final stack = StackTrace.fromString(
          'original ${operation.key} failure',
        );
        final storage = LocalStorageService(
          _StubHive(() async => _FailingBox(error, stack)),
        );
        await expectOriginalFailure(
          () => operation.value(storage),
          error,
          stack,
        );
      },
    );
  }
}
