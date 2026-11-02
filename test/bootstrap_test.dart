import 'dart:io';

import 'package:doom_meter/app.dart';
import 'package:doom_meter/bootstrap.dart';
import 'package:doom_meter/core/di/injection.dart';
import 'package:doom_meter/core/storage/local_storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Directory directory;

  setUp(() async {
    await getIt.reset();
    directory = await Directory.systemTemp.createTemp('doom_startup_');
    messenger.setMockMethodCallHandler(
      pathChannel,
      (_) async => directory.path,
    );
  });
  tearDown(() async {
    messenger.setMockMethodCallHandler(pathChannel, null);
    await getIt.reset();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  testWidgets('storage startup failure shows recovery screen before DI', (
    tester,
  ) async {
    messenger.setMockMethodCallHandler(pathChannel, (_) async {
      throw PlatformException(code: 'storage_unavailable');
    });
    await bootstrap();
    await tester.pumpAndSettle();

    expect(find.textContaining('Unable to start Doom Meter'), findsOneWidget);
    expect(find.byType(App), findsNothing);
    expect(getIt.isRegistered<LocalStorageService>(), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('DI failure never starts normal App with partial registrations', (
    tester,
  ) async {
    // Cause the real generated initializer to reject a duplicate registration.
    getIt.registerSingleton<LocalStorageService>(LocalStorageService(Hive));
    await bootstrap();
    await tester.pumpAndSettle();

    expect(find.textContaining('Unable to start Doom Meter'), findsOneWidget);
    expect(find.byType(App), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
