# Doom Meter — Daily social counters

Home keeps its date navigation, brain image, and social counter layout. Tapping
Instagram simulates one Reel scroll; tapping YouTube simulates one Short scroll.
Only the device's current local calendar day is editable. Historical and future
dates are read-only. No native detection or background services are implemented.

## Environment and dependencies

`pubspec.yaml` retains Dart `^3.12.2`, Flutter `>=3.47.6`, and all requested
package constraints. Validation uses the installed Flutter **3.47.6**, which
bundles Dart **3.13.5** (within `^3.12.2`). The default Flutter on this machine
is 3.44.9 and does not meet the project's minimum. Select the matching SDK:

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"
flutter --version
```

Hive is `^2.2.3` and hive_flutter is `^1.1.0`. Both are null-safe releases;
[Dart's compatibility rule](https://dart.dev/resources/dart-3-migration#dart-3-backwards-compatibility)
permits their `>=2.12.0 <3.0.0` constraints on Dart 3. They resolve with this SDK.

### Generator compatibility

Keep `pubspec.lock` under version control. All requested caret constraints are
unchanged, but their exact minimum releases cannot resolve together:

- AutoRoute generator 10.6.0 requires `lean_builder ^1.2.0`.
- Injectable generator 3.0.2 requires `lean_builder ^0.1.10`.
- Stable Freezed 3.2.5 requires analyzer `<11.0.0`, incompatible with the
  analyzer dependencies of AutoRoute generator 10.6.0 and lean_builder 1.x.

The compatible lockfile uses **injectable_generator 3.1.0** and
**freezed 3.2.6-dev.1** within the requested ranges. The Freezed prerelease is a
known limitation of this combination. Using stable Freezed would require
revisiting the requested generator constraints. The resolved dependency graph
requires Dart >=3.13.0; use the matching Flutter SDK for this lockfile.

No additional direct supporting dependencies were added. Existing
`flutter_lints` is retained; unused starter `cupertino_icons` was removed.
Provider, JSON annotations, path_provider, and Material UI appear transitively
because requested packages depend on them. Application code uses no additional
state management or serialization library.

## Existing feature structure

```text
lib/features/home/
├── data/
│   ├── data_sources/home_data_source.dart
│   ├── models/daily_counts_model.dart
│   ├── mappers/daily_counts_mapper.dart
│   └── repositories/home_repository_impl.dart
├── domain/
│   ├── entities/
│   │   ├── daily_counts.dart
│   │   └── social_platform.dart
│   ├── params/
│   │   ├── get_daily_counts_params.dart
│   │   └── increment_social_count_params.dart
│   ├── repositories/home_repository.dart
│   └── use_cases/
│       ├── get_daily_counts.dart
│       └── increment_social_count.dart
└── presentation/
    ├── pages/home_page.dart
    ├── widgets/
    │   ├── home_date_navigation.dart
    │   └── social_counter.dart
    └── blocs/home/
        ├── home_bloc.dart
        ├── home_event.dart
        ├── home_state.dart
        └── home_state.freezed.dart # generated
```

DI and routing remain in `lib/core/di/` and `lib/core/router/`. Shared local-date
helpers and the injectable device clock are in `lib/core/utils/`.

## Data and domain flow

Manual tap → HomeSocialIncrementRequested → HomeBloc → IncrementSocialCount →
HomeRepository → HomeRepositoryImpl → HomeDataSource → LocalStorageService → Hive.

Date navigation dispatches HomeDateChanged and uses GetDailyCounts through the
same repository. Widgets only dispatch events and format presentation values.
Models serialize primitive maps; mappers convert between models and entities.
No additional packages, Hive adapters, or JSON generators are required.

The `daily_counts` box has one `yyyy-MM-dd` key per local date. Each value stores
`date`, `instagramCount`, `youtubeCount`, `lastInstagramActivityAt`, and
`lastYoutubeActivityAt`. Activity times retain local ISO-8601 precision. Each
increment changes only the requested platform and its timestamp. `totalCount`
is derived, never persisted. Missing dates return zeros and null timestamps;
viewing them does not create records. Malformed records surface an error rather
than being silently replaced with zeros.

## Safety, ordering, and day changes

IncrementSocialCount checks the requested day against the injectable LocalClock,
not against a caller-supplied timestamp. Activity time must belong to that day.
The data source repeats this validation inside its write queue, including after
the read, to protect direct repository calls and operations queued at midnight.
Past/future writes throw ReadOnlyCountDate without touching the record.

HomeBloc processes all events sequentially. HomeDataSource is a lazy singleton
with its own read/increment/save queue, so separate Blocs or future native
adapters cannot lose increments by reading the same old count. Failed operations
report errors to their callers without poisoning the queue. UI counts update only
after Hive confirms the write; save failures retain the last displayed counts.
Reloading after an error reads Hive rather than replaying a possibly saved event.

HomeStarted loads the current local day from Hive. Each increment rechecks the
clock, including when the screen was left open across midnight. HomeResumed
refreshes on foregrounding: a previously current-day view follows the new day,
while a deliberately selected historical view remains selected. There are no
midnight timers or reset jobs; a new date key naturally begins at zero. A screen
left idle in the foreground refreshes on its next interaction or resume.

The UI shows per-platform last activity in the device's time format, or
"No activity". Dates outside today have disabled counters and a read-only label.

## Future detection integration

A future platform-event adapter can constructor-inject IncrementSocialCount and
call it with a SocialPlatform, local date, and activity time. For example:

```dart
await incrementSocialCount(IncrementSocialCountParams(
  platform: SocialPlatform.instagram,
  date: activityTime,
  activityTime: activityTime,
));
```

The operation is independent of widgets and BLoC. All writers must use the same
DI-managed repository/data-source instance in the application isolate. Future
background-isolate producers must forward events to that writer; this queue is
not a cross-process database transaction. Historical/backfilled native events
remain rejected under the current today-only rule. Native detection, platform
channels, subscriptions for externally produced UI updates, and deduplication of
native events are future work, not part of this manual-input phase.

## Initialization and dependency injection

Bootstrap initializes Flutter, awaits Hive.initFlutter(), then configures
Injectable/GetIt before runApp. HomeDataSource, HomeRepository, LocalClock,
LocalStorageService, and AppRouter are lazy singletons. Use cases and HomeBloc
are factories. BlocProvider owns and closes each page's Bloc. The page also
owns/disposes its lifecycle listener. Tests inject a controllable clock; the
production clock uses DateTime.now(). No production registrations are handwritten.

## Generate, check, and run

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
flutter devices
flutter run -d <device-id>
```

During development:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

build_runner 2.15.1 accepts but ignores the legacy
`--delete-conflicting-outputs` flag with a warning. The shorter `build` and
`watch` commands also work. Generated files come only from build_runner;
regenerate after changing routes, DI annotations, or Freezed declarations.
Do not edit them manually.

Tests use isolated real Hive files to exercise persistence after reopening,
rapid mixed-platform writes, timestamp independence, date guards, midnight
transitions, queue recovery, corrupt records, Bloc recreation, and UI editing.
Native APK/IPA packaging is separate from these checks.

Verified with Flutter 3.47.6 / Dart 3.13.5: `flutter pub get`, build_runner
generation, `flutter analyze` (no issues), and `flutter test` (23 tests passed).
