# doom_meter

A new Flutter project.

## Local setup and generated code

Use the SDK declared in `pubspec.yaml` (Dart ^3.12.2, Flutter >=3.47.6).
Before analysis, tests, or a build on a fresh checkout, run:

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter run
```

Build runner generates Injectable, AutoRoute, Freezed, and FlutterGen sources.
The installed build_runner version ignores the obsolete
`--delete-conflicting-outputs` flag; `dart run build_runner build` also works.
Generated sources are build-time artifacts and are intentionally ignored by Git.
CI must run generation before analysis/builds; no tracked generated files were removed.

FlutterGen 5.15.0 is a development dependency configured to output `lib/gen/`.
Home uses `Assets.images.brainIcon.image(...)` from `assets.gen.dart` for the
existing PNG. Instagram and YouTube remain vector painters; no SVG integration
or runtime asset package is needed. Setup follows the
[FlutterGen build_runner documentation](https://pub.dev/packages/flutter_gen_runner).

Calendar operations use `date.normalizedDate`, `date.dateKey`, and
`date.isSameCalendarDate(other)`, converting UTC instants to device-local dates
before comparison/key generation. Existing Hive keys and record formats are unchanged.

Storage failures log the operation/box and original error/stack, then rethrow
without returning fallback values. Hive initialization and DI failures are fatal
to normal startup: bootstrap logs the failed stage and displays a dependency-free
recovery screen. Restart the app after resolving the underlying problem; startup
does not clear saved data or launch Home with partially initialized dependencies.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
- [Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Flutter learning resources](https://docs.flutter.dev/reference/learning-resources)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
