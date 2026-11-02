import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/di/injection.dart';
import 'core/router/app_router.dart';

Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Hive.initFlutter();
  } catch (error, stackTrace) {
    _showStartupFailure('local storage initialization', error, stackTrace);
    return;
  }

  final AppRouter router;
  try {
    await configureDependencies();
    router = getIt<AppRouter>();
  } catch (error, stackTrace) {
    _showStartupFailure('dependency initialization', error, stackTrace);
    return;
  }
  runApp(App(appRouter: router));
}

void _showStartupFailure(String step, Object error, StackTrace stackTrace) {
  developer.log(
    'Startup failed during $step.',
    name: 'bootstrap',
    level: 1000,
    error: error,
    stackTrace: stackTrace,
  );
  // Both failures are fatal to normal startup. This screen needs no DI or Hive.
  runApp(
    const MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Unable to start Doom Meter.\nPlease close the app and try again.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
