# Android YouTube Shorts tracking POC

The pipeline is implemented: YouTube accessibility events → isolated Kotlin
viewer/transition detector → native SharedPreferences → MethodChannel → Flutter
platform service → sync use case → HomeRepository → existing Hive daily records
→ HomeBloc → Home. Instagram remains manual. There is no Dart background process,
usage-stats permission, foreground service, or polling worker.

## Observed event pattern

Investigation on 1 November 2026 used a Samsung SM-A127F, Android 13, YouTube
21.34.243. The logger was installed before the detector was implemented.

- Ten confirmed Home gestures produced 90 `TYPE_VIEW_SCROLLED` events, 89 from
  `com.google.android.youtube:id/results` and one with a null source.
- A confirmed standard-video comments sample produced 36 scroll events from
  `results`, with no `reel_recycler` changes.
- Three confirmed forward Shorts gestures produced 62 content-change events,
  three from `reel_recycler`, and **no** `TYPE_VIEW_SCROLLED` events.
- Shorts exposed `reel_watch_fragment_root`, `reel_recycler`, and
  `reel_player_page_container`. The page's `collectionItemInfo.rowIndex`
  advanced 11 → 12 → 13 → 14. Repeated notifications preserved the row.
- Home retained a `reel_time_bar` after leaving Shorts, and contains Shorts text
  in both navigation and feed headings. Neither signal identifies the viewer.
- Some navigation attempts were obstructed by overlays or ended on a different
  screen. Those samples were excluded from negative-control/accuracy results.

The detector therefore reads collection-row changes after checking multiple
viewer resource IDs and page geometry. It does **not** count each scroll event,
rely on the word Shorts, or collect a video title as its identity. Both increasing
and decreasing rows represent transitions. Entry/re-entry establishes a baseline.

`ScrollAccessibilityService` coalesces incoming events with an 80 ms delayed
sample. This callback exists only in response to events. It reads the current
root, and resets the detector outside the supported viewer. The reader rejects
small/collapsed viewers and picture-in-picture dimensions, and blocks visible
`results`/`watch_list` panels. During animation, an unsettled page does not erase
the previous settled row. Unknown/missing row metadata produces no count.

`ShortsTransitionDetector` rejects identical rows and uses a centralized 600 ms
minimum interval between counted transitions. Very fast real transitions can be
missed; this setting is deliberately isolated for further measurement.

## Changed structure and file inventory

New native files are all under
`android/app/src/main/kotlin/com/example/doom_meter/tracking/`:

```text
tracking/
├── AccessibilityEventLogger.kt       debug-only, redacted event metadata
├── AccessibilityUtils.kt             exact enabled-service check
├── DateKeyUtils.kt                   local yyyy-MM-dd keys
├── ScrollAccessibilityService.kt     event observation and sampling
├── ShortsTransitionDetector.kt       pure row-transition state machine
├── YouTubeShortsViewerReader.kt      Android node-tree interpretation
├── ScrollTrackingStore.kt            serialized durable native persistence
└── ScrollTrackingChannel.kt          Flutter bridge and Settings action
```

Other new Android files:

```text
android/app/src/main/res/xml/scroll_accessibility_service.xml
android/app/src/main/res/values/strings.xml
android/app/src/test/kotlin/com/example/doom_meter/tracking/ShortsTransitionDetectorTest.kt
android/app/src/test/kotlin/com/example/doom_meter/tracking/DateKeyUtilsTest.kt
```

Modified Android files:

- `MainActivity.kt`: installs/disposes the channel with the Flutter engine;
  no detector or storage logic is placed in the Activity.
- `AndroidManifest.xml`: registers `.tracking.ScrollAccessibilityService`,
  protected by `BIND_ACCESSIBILITY_SERVICE`, with its service XML metadata.
- `android/app/build.gradle.kts`: enables BuildConfig for debug logging and adds
  JUnit 4.13.2 for native unit tests.

The XML observes only `com.google.android.youtube`, with scrolled/window-state/
window-content events, report-view-IDs, retrieval of window content, a 100 ms
notification timeout, and `isAccessibilityTool="false"`. Strings supply a visible
service label and an experimental/local-storage disclosure.

New Flutter files:

```text
lib/core/platform/scroll_tracking/
├── constants/scroll_tracking_channel_constants.dart
├── models/native_daily_scroll_count.dart
├── scroll_tracking_service.dart
└── scroll_tracking_service_impl.dart
lib/features/home/domain/use_cases/sync_detected_scroll_counts.dart
lib/features/home/presentation/widgets/youtube_tracking_section.dart
```

Modified Flutter files:

```text
lib/features/home/
├── data/data_sources/home_data_source.dart
├── data/models/daily_counts_model.dart
├── data/repositories/home_repository_impl.dart
├── domain/repositories/home_repository.dart
├── domain/use_cases/increment_social_count.dart
├── presentation/blocs/home/home_bloc.dart
├── presentation/blocs/home/home_event.dart
├── presentation/blocs/home/home_state.dart
└── presentation/pages/home_page.dart
```

Generated through build_runner, never edited manually:

```text
lib/core/di/injection.config.dart
lib/features/home/data/models/daily_counts_model.freezed.dart
lib/features/home/presentation/blocs/home/home_state.freezed.dart
```

New Flutter tests:

```text
test/core/platform/scroll_tracking_service_test.dart
test/features/home/native_counts_sync_test.dart
test/support/fake_scroll_tracking_service.dart
```

Existing `test/support/home_test_context.dart` and `test/app_test.dart` now inject
a fake tracking service; widget tests cover disclosure, settings dispatch, resume,
and manual editing restrictions. Existing unrelated README edits are preserved.

## Persistence and source authority

Native preferences file: `scroll_tracking`. Keys:

```text
youtube_count_yyyy-MM-dd          Long absolute count
youtube_last_activity_yyyy-MM-dd  Long milliseconds since epoch
```

One process-wide store owns a single executor. Both count/timestamp are committed
in the same edit off the main thread. Reads use the same queue, so they observe
previously queued increments. The event's local date is captured before queueing.
A failed write is surfaced on subsequent channel reads until a write succeeds;
it is never reported to Flutter as a successful empty snapshot.

The channel `com.example.doom_meter/scroll_tracking` exposes:

- `isAccessibilityTrackingEnabled`: compares the exact service component against
  AccessibilityManager's enabled services.
- `openAccessibilitySettings`: opens `Settings.ACTION_ACCESSIBILITY_SETTINGS`.
  Permission is always enabled by the user in Android Settings.
- `getDetectedDailyCounts`: returns maps with `date`, `youtubeCount`, and nullable
  `lastActivityAt`. The Flutter implementation validates the entire response,
  rejects duplicate/invalid dates, negative counts and malformed timestamps, and
  turns missing-plugin/platform/time-out failures into controlled errors.

The existing Hive `daily_counts` box remains the only Flutter history database.
Native synchronization uses the same serialized write queue as manual increments.
It replaces the absolute YouTube total and timestamp, preserving Instagram data.
It never adds a native total to the existing Hive value or takes their maximum.
Records update their own date keys, even when Home displays another day.

Two optional metadata fields are added to each existing daily map:
`lastSyncedYoutubeCount` and `lastSyncedYoutubeActivityAt`. Old maps remain readable.
These fields are checkpoints, not additional displayed daily counters.

- Tracking enabled: native values are authoritative, including when lower than
  manual test counts. Manual YouTube taps are blocked in both BLoC and use case.
- Tracking disabled: the final/new native snapshot is still imported. Re-reading
  an unchanged checkpoint preserves subsequent manual test taps, including after
  app restart. A changed native snapshot replaces the manual YouTube test total.
- Re-enabling tracking reasserts native authority. Instagram is unaffected.
- Status unavailable: manual YouTube editing stays disabled until status can be
  checked, avoiding a silent mixture of sources.

## Flutter state, DI, and lifecycle

`ScrollTrackingServiceImpl` is an Injectable lazy singleton;
`SyncDetectedScrollCounts` and `HomeBloc` follow the existing factory convention.
The domain use case uses only the platform interface, never MethodChannel.

New events: `HomeTrackingPermissionRequested`, `HomeTrackingStatusRequested`, and
`HomeNativeCountsSyncRequested`. Existing `HomeStarted`, `HomeResumed`, and retry
check status and sync before reading the selected Hive day. Navigation alone
reads the requested day. The existing single `AppLifecycleListener` dispatches
resume, including returns from Accessibility Settings.

State adds supported/enabled/known/loading/syncing flags and a separate tracking
error. Counts remain in `DailyCounts`. A sync failure still loads saved data.
The Home section displays status, explanation, retry, and Enable/Manage tracking.
A Cancel/Open Settings disclosure precedes every settings launch. No widget
calls the native channel directly. Unsupported platforms retain manual counters.

## Build and code generation

Use this project's compatible SDK, not an older Flutter on PATH:

```bash
export PATH="$HOME/fvm/versions/3.47.6/bin:$PATH"
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test
(cd android && ./gradlew :app:testDebugUnitTest)
flutter build apk --debug
flutter run -d <physical-device-id>
```

Build_runner 2.15.1 warns that `--delete-conflicting-outputs` is obsolete and
ignored. No `flutter clean` was needed. Existing AGP/Kotlin template deprecation
warnings remain; they do not fail the APK build or unit tests.

For a diagnostic update that preserves app data and avoids Flutter run's
force-stop step:

```bash
adb -s <device> install -r build/app/outputs/flutter-apk/app-debug.apk
adb -s <device> shell am start -n com.example.doom_meter/.MainActivity
```

Do not uninstall, clear app data, or force-stop the package during persistence
tests. On the investigation phone an IDE reinstall/force-stop cleared the enabled
service setting. An accessibility shortcut can also toggle the service off.
The floating Flutter shortcut is not an app-launch button. Verify the **main
service switch**, not just its shortcut assignment, after an IDE restart.

## Device validation

The final debug APK was tested on 2026-11-01 on Samsung SM-A127F (Galaxy A12),
Android 13, YouTube 21.34.243. Its installed APK hash matched the local build,
including the small-viewer/PiP guard and date-validation refinements. These are
controlled device gestures, not a statistically representative accuracy study.
Screens were inspected before/after samples and native counts compared with
debug transition logs. A gesture is not necessarily a successful page transition,
especially during rapid navigation.

| Check | Result |
| --- | --- |
| Flutter channel/status | Active; exact service enabled, initial native/Flutter total 0 |
| Home feed: 10 gestures | 0 → 0; no false increments in this sample |
| Standard-video comments: 5 gestures | 14 → 14 |
| Standard-video description: 3 gestures | 14 → 14 |
| Standard-video recommendations: 5 gestures | 14 → 14 |
| Short-video comments: 5 gestures | 19 → 19 |
| Community-post comments inside Shorts feed: 5 gestures | 10 → 10 |
| Fast Shorts feed: 10 gestures, 120 ms swipe, no added pause | 4 → 8 (+4); settled rows 5 → 6 → 8 → 11 → 12, skipping intermediate positions |
| Slower Shorts feed: 5 gestures, 450 ms swipe, 2-second pauses | 10 → 14 (+4); rows 10 → 11 → 12 → 13 → 15, missing row 14 |
| Backward feed: 2 gestures | 8 → 10 (+2); rows 12 → 11 → 10; row 10 was a community photo post, a false classification for video-only counting |
| Resume into Flutter | Home displayed native total 14 and last activity time; Instagram remained 0 |
| Flutter Activity closed, then 5 gestures with 3-second pauses | Activity absent from Android's activity records; native 14 → 19; reopening Flutter displayed 19 with Active status |
| Flutter in recent apps, then 5 gestures with 3-second pauses | Activity retained in STOPPED state; native 19 → 24; rows 20 → 21 → 22 → 23 → 24 → 25; resume displayed 24, Active, and updated activity time |
| App restart and repeated sync | Activity recreation retained/synced 19; after reaching 24, three further background/resume cycles left native and Flutter at 24 |
| Date rollover | Native unit test covers local midnight and timezone; device clock not changed |
| Historic selected day | Selecting Oct 31 displayed 0; background/resume preserved Oct 31 and 0; returning to Nov 1 restored 24 |
| Disabled/enable disclosure and resume | Flutter widget tests; manual Android enablement observed during investigation |

An earlier comments-labelled batch navigated to the Shorts viewer before its
gestures. Its 0 → 4 increase is excluded from comments/accuracy conclusions.
The verified standard-video comments sample above was repeated on the correct
screen. No raw screen content, screenshots, or device logs are committed here.
The phone was returned to Doom Meter on Nov 1, showing YouTube 24, Instagram 0,
and Active status. Those totals include the diagnostic gestures and the known
community-post false classification; test data was not cleared.

Earlier integrated testing on Samsung SM-A207F, Android 11, YouTube 21.43.523
recorded ten slower gestures at native 6 → 16, then Flutter displaying 16. That
device's initial slow launch hit the channel timeout; saved counts remained visible
and retry recovered. Those results do not establish accuracy on the A12. On the
A12, one Activity recreation exceeded `am start -W`'s launch wait, but Flutter
subsequently rendered successfully and synchronized 19.

Native tests cover row deduplication, forward/backward direction, animation gaps,
viewer exit/re-entry, blocked panels, debounce, and local-date validity/midnight.
Flutter tests cover channel validation/errors/unsupported platforms, absolute and
repeat sync, migration checkpoints across Hive reopen, concurrent Instagram writes,
manual guards, selected history, lifecycle/status refresh, and disclosure.

Final local checks: **34 Flutter tests passed, 8 native tests passed**,
`flutter analyze` reported no issues, `git diff --check` passed, and the final
debug APK built successfully. The device results above expose missed feed
transitions and a community-post false classification: the detector is still
experimental and is not considered stable.

Repeat this release-check sequence on each supported YouTube/device variant:

1. Disable the service manually; Home should show Disabled after resume.
2. Enable through the disclosure and Android's main switch; return to see Active.
3. Confirm Home feed, then scroll ten times; native/Hive delta must be zero.
4. Confirm a standard video; scroll recommendations, description, and comments;
   all must leave the Shorts total unchanged.
5. Record a starting total, enter Shorts, and perform ten slow then ten fast
   transitions. Record actual transitions and detected deltas separately.
6. Move forward/backward; each supported settled transition counts once.
7. Open Shorts comments and scroll them; expect zero.
8. Close the Flutter Activity without force-stop; perform five Shorts transitions;
   reopen and compare native persistence with Home.
9. Repeat with Flutter in recent apps; returning should sync immediately.
10. Restart Home and repeat sync; totals must not multiply.
11. Exercise a new local date and a selected historical date. Use automated clock
    tests instead of changing the user's real clock without authorization.

## Diagnostics and limitations

```bash
adb devices -l
adb -s <device> shell settings get secure enabled_accessibility_services
adb -s <device> shell dumpsys accessibility
adb -s <device> logcat -v threadtime -s DoomScrollTracking:D '*:S'
adb -s <device> shell dumpsys package com.google.android.youtube
# Debug builds only, for local persistence comparison:
adb -s <device> shell run-as com.example.doom_meter cat shared_prefs/scroll_tracking.xml
```

Debug logging includes event/source metadata and settled row transitions. Arbitrary
content descriptions are redacted except for a small allowlist of generic controls.
No event text, titles, usernames, or comments are persisted or transmitted. Temporary
screen/tree inspection is local; do not commit device dumps or logs. Release builds
disable detailed logs. Only daily counts/timestamps persist in native storage/Hive.

Observed accuracy defects on the final A12 build:

- Rapid gestures exposed only rows 6, 8, 11, and 12 after baseline 5. The detector
  counts each observed row change once, so it misses intermediate positions.
  The same issue occurred at slower speed for row 14. This is not evidence that
  reducing the 600 ms debounce alone will fix the misses.
- Community photo posts can occupy `reel_player_page_container` rows and pass the
  existing viewer guard. Entering one incremented the total. A video-specific
  structural signal is needed before this can be described as video-only counting.
- Do not convert a skipped row distance directly into a video count without
  validating posts, ads, and feed reindexing. The measured 4/10 fast gesture yield
  is not a general accuracy percentage or proof of ten completed transitions.

Known limits: YouTube can change its private resource IDs/collection metadata;
missing metadata intentionally causes missed counts. Programmatic page changes,
ads, alternative player layouts, transient tree failures, rapid gestures inside
the debounce window, and unusual navigation can still cause misses or mistaken
classifications. A row index is a heuristic, not an official video-change API.
Picture-in-picture, landscape, and multi-window accuracy are not established.
No 100% accuracy or general absence of false positives is claimed. Native write
failures cannot guarantee durable counting. Reinstall/force-stop and OEM service
management may stop tracking. Data is local and does not migrate between phones.

Before production distribution: complete the remaining device matrix and accuracy
measurements; review the privacy policy, prominent disclosure, explicit consent,
disable flow, and current Play accessibility policy. This app does not claim to
be an accessibility tool.

API references: [Android accessibility services](https://developer.android.com/guide/topics/ui/accessibility/views/service),
[enabled service list](https://developer.android.com/reference/android/view/accessibility/AccessibilityManager#getEnabledAccessibilityServiceList(int)),
[SharedPreferences commit](https://developer.android.com/reference/android/content/SharedPreferences.Editor#commit()).
