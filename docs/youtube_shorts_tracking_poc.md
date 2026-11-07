# Android YouTube Shorts tracking POC

## Current implementation status and product definition

Updated 7 November 2026. The Android-to-Flutter pipeline is implemented and has
been exercised on physical Samsung devices. This revision changes counting from
bidirectional interactions to **forward discovery**. The earlier measurements
remain below as historical evidence, including misses and false classifications.
They must not be read as acceptance results for the new counting rule.

> One YouTube Shorts count represents a successfully detected forward transition
> to a new Short that has not already been counted within the relevant tracking
> context.

```text
YouTube Shorts Daily Count
    = successfully detected forward transitions to new/unseen Shorts

NEW + FORWARD  → +1
BACKWARD       →  0
REWATCH        →  0 where the current feed position is recognizable
UNKNOWN        →  0
NEVER          → -1 because of navigation
```

The metric is neither an accessibility-event count, a raw swipe count, a current
page index, nor forward movement minus backward movement. In this POC, "new" is
approximated using the highest observed collection row within one uninterrupted
viewer context. There is **no stable video identity or daily uniqueness guarantee**.
The implementation can reject retracing the same row range; it cannot recognize
the same video at a different position or across every viewer/service restart.
Community posts can still be mistaken for Shorts, and rapid changes can be missed.

## Architecture

The pipeline is implemented: YouTube accessibility events → isolated Kotlin
viewer/transition detector → native SharedPreferences → MethodChannel → Flutter
platform service → sync use case → HomeRepository → existing Hive daily records
→ HomeBloc → Home. Instagram remains manual. There is no Dart background process,
usage-stats permission, foreground service, or polling worker.

```text
YouTube foreground UI
    │ accessibility events (Android dispatches them independently of Flutter)
    ▼
ScrollAccessibilityService
    ├─ package guard + event-triggered sample
    ├─ YouTubeShortsViewerReader: structure, geometry, settled row
    └─ ShortsTransitionDetector: direction → revisits → debounce → decision
                        │ COUNT only
                        ▼
ScrollTrackingStore: absolute daily count + last counted time
                        │ read on Flutter startup/resume/retry
                        ▼
ScrollTrackingChannel ↔ ScrollTrackingServiceImpl
                        ▼
SyncDetectedScrollCounts → HomeRepositoryImpl → HomeDataSource
                        ▼
existing daily_counts Hive box → DailyCounts → HomeBloc → HomePage
```

Flutter does not have to stay open to detect transitions. Android manages the
enabled AccessibilityService; `MainActivity` only attaches the Flutter channel.
Direction and revisit decisions stay native. The channel still returns absolute
daily records, so repositories, Hive schema, domain entities, and BLoC require no
direction-specific redesign.

## Accessibility events and observed event pattern

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
rely on the word Shorts, or collect a video title as its identity. Increasing rows
map to forward movement and decreasing rows to backward movement in the measured
viewer. The old detector counted both; the new detector counts only eligible
forward movement. Entry/re-entry establishes a baseline without incrementing.

These are **successive settled `collectionItemInfo.rowIndex` values**, not a
claim that `AccessibilityEvent.fromIndex` and `toIndex` describe old/new videos.
The investigated Shorts events did not provide a usable generic scroll-delta
signal. No positive/negative `scrollDeltaY` fallback is implemented. The later
A12 reverse test exposed 12 → 11 → 10 during downward gestures, corroborating the
direction mapping. Future YouTube/OEM variants must be measured separately.
The 2 November run also exposed occasional intermediate row 0 values during
upward navigation. The mapping applies to consistent feed positions; those
non-monotonic metadata samples remain a documented limitation.

## Android AccessibilityService and YouTube package detection

`ScrollAccessibilityService.onAccessibilityEvent` ignores null events and every
package except `com.google.android.youtube`, even though the XML also restricts
packages. The three subscribed event types are `TYPE_VIEW_SCROLLED`,
`TYPE_WINDOW_STATE_CHANGED`, and `TYPE_WINDOW_CONTENT_CHANGED`. Content changes
are essential for the measured YouTube viewer; restricting counting to scroll
events would miss the observed transitions.

`ScrollAccessibilityService` coalesces incoming events with an 80 ms delayed
sample. This callback exists only in response to events. It reads the current
root, and resets the detector outside the supported viewer. The reader rejects
small/collapsed viewers and picture-in-picture dimensions, and blocks visible
`results`/`watch_list` panels. During animation, an unsettled page does not erase
the previous settled row. Unknown/missing row metadata produces no count.

`ShortsTransitionDetector` rejects identical rows and uses a centralized 600 ms
minimum interval between counted transitions. Very fast real transitions can be
missed; this setting is deliberately isolated for further measurement.

`inspectViewer()` runs on the main looper, obtains `rootInActiveWindow`, reads a
structural snapshot, and feeds the pure detector using `SystemClock.elapsedRealtime()`.
Only `TransitionDecision.COUNT` calls `incrementYouTube(System.currentTimeMillis())`.
Every ignored decision bypasses persistence completely. Exceptions reset detector
memory and emit a debug diagnostic. Root/node references are recycled; interruption
or destruction cancels the pending callback and resets the detector.

## Shorts viewer detection

`YouTubeShortsViewerReader.read` requires the YouTube root package, visible
`reel_watch_fragment_root` and `reel_recycler`, and a sufficiently large viewport:

- At least 65% of the root window height and 80% of its width.
- At least 50% of the display height and 65% of its width.
- A single visible `reel_player_page_container` whose top and bottom are each
  within 3% of the viewport height of the recycler edges.
- A nonnegative `collectionItemInfo.rowIndex` for a settled page.

Visible `results` or `watch_list` nodes mark the snapshot blocked. An absent
viewer returns null. Multiple/unaligned pages during animation yield a null row
without necessarily ending the viewer context. These checks reduce ordinary-feed,
panel, mini-player, and PiP false positives; they are heuristics, not exhaustive
layout support. The known community-post classification defect is still open.

The context token is `${viewer.windowId}:${recycler.hashCode()}`. It identifies
the current structural viewer for comparison; it is not a stable Short identifier.
Node replacement, window changes, and private YouTube implementation changes can
invalidate that context or change row numbering.

## Forward vs backward transition detection

All direction logic lives in `detectScrollDirection(fromRow, toRow)` in
`ShortsTransitionDetector.kt`. It returns the explicit `ScrollDirection` enum:

| Settled row relationship | Direction | Eligible to count? |
| --- | --- | --- |
| Either row missing/negative | `UNKNOWN` | No |
| Same row | `UNKNOWN` | No; duplicate notification |
| New row greater than previous row | `FORWARD` | Only after new-position and debounce checks |
| New row less than previous row | `BACKWARD` | No |

The function compares integers rather than subtracting them, avoiding overflow.
There is no direction inference from titles, finger coordinates, event timing,
or an unvalidated scroll-delta sign. Device gestures are used for testing the
mapping; they are not captured by a Flutter gesture detector in production.

## New Short definition and initial entry

Opening YouTube or entering Shorts does not count. The first valid settled row
becomes both `previousRow` and `highestObservedRow`. That initial Short is a
baseline, so returning to it later is not a discovery.

A count requires all of the following within the current structural context:

1. A supported, unblocked viewer with a valid settled row.
2. A previous settled row, and a strictly larger current row (`FORWARD`).
3. A current row strictly larger than the previous `highestObservedRow`.
4. At least 600 ms since the last accepted count, if one exists.

Exactly one increment is requested for an accepted transition, even if the row
jumps by more than one. Missing row positions are never converted into inferred
video counts. The detector cannot prove that a higher row contains a new video;
that remains the documented positional approximation.

| Action | Count change |
| --- | ---: |
| Open YouTube | 0 |
| Open Shorts | 0 |
| Swipe up to a detected new Short position | +1, subject to validation/debounce |
| Swipe down to a previous Short | 0 |
| Stay on the same Short | 0 |
| Duplicate accessibility notification | 0 |
| Scroll comments | 0 when viewer/panel detection succeeds |
| Scroll YouTube Home | 0 when viewer detection succeeds |
| Return backward to a previously counted Short | 0 |
| Move forward again through recognized positions | 0 |
| Move forward beyond the highest observed position | +1, subject to validation/debounce |
| Unknown direction or missing row | 0 |

## Previously viewed / rewatch handling

There is no privacy-safe stable video ID in the current inspected snapshot.
Resource IDs name reusable widgets, row numbers name positions, and the viewer
token names a context. None is a durable video identity. No titles, captions,
creator names, or comments are hashed or collected to manufacture one.

The implemented fallback retains only `previousRow`, `highestObservedRow`, the
viewer token, and `lastCountedAt` in memory. For each valid observed row, it updates
the previous row and the maximum observed row. Backward navigation updates the
comparison baseline but leaves the maximum, count, and counted timestamp unchanged.
A forward return to any row at or below the previous maximum is ignored with
`IGNORE_REVISITED_POSITION`.

Example within one stable viewer, with positions A=0 through E=4:

```text
Open A           baseline, total 0
A → B            FORWARD, new position, total 1
B → C            FORWARD, new position, total 2
C → D            FORWARD, new position, total 3
D → C → B        BACKWARD twice, total 3
B → C → D        FORWARD but revisited positions, total 3
D → E            FORWARD beyond previous maximum, total 4
```

For a starting total of 25, `UP, UP, DOWN, DOWN, UP, UP, UP` through the same
consecutive positions produces `26, 27, 27, 27, 27, 27, 28`, assuming the new
positions are observed and the counted transitions meet the debounce interval.
`A → B → C → D → E` adds four; viewing initial A adds nothing.

This is conservative range suppression, not an exact seen-video set. A skipped
or debounced position also falls below the maximum and will not count when
retraced later. If the feed inserts/reorders items without changing the context,
the same position may contain a different video, or the same video may appear at
a higher position. Those cases cannot be resolved by this implementation.

### Tracking context, daily uniqueness, and resets

The maximum is cleared on a null/blocked snapshot, changed viewer token, explicit
detector reset, sampling exception, service interruption, or destruction. The
next valid row becomes a fresh baseline. Null/negative row metadata within the
same unblocked context is an animation/unknown observation and retains history.

Opening a panel or leaving YouTube can cause a reset if the reader observes an
unsupported/blocked root. Flutter backgrounding alone does not explicitly reset
the detector. Only YouTube events are subscribed, so do not assume every app
switch necessarily produces a sampled exit.

After a reset/re-entry, a previously watched video can count again on a subsequent
eligible forward transition. History does not survive service/process recreation
and is not stored in SharedPreferences or Hive. There is no all-day deduplication.
Midnight changes the persistence date key, not the in-memory viewer context; a
rewatch of an old position in the same continuing context remains ignored.

The preferred future behavior is privacy-safe daily uniqueness if a stable video
identity is demonstrated. It is not currently implemented or claimed. Reliable
direction classification on the measured row pattern does not establish reliable
identity across all YouTube versions, feeds, or process lifetimes.

## Duplicate event handling and decision state machine

The detector keeps these responsibilities separate:

| Responsibility | Implemented signal/state |
| --- | --- |
| Direction | Compare previous and current settled rows |
| Duplicate notification | Same row as the previous observation |
| Previously traversed position | Forward destination at/below highest observed row |
| Temporal debounce | Less than 600 ms since the last `COUNT` |

```text
Structural snapshot
    ├─ not Shorts / blocked → reset context → IGNORE_NOT_SHORTS
    └─ supported viewer
         ├─ changed context → reset, establish baseline
         ├─ invalid/missing row → IGNORE_UNKNOWN_DIRECTION
         ├─ first settled row → baseline → IGNORE_UNKNOWN_DIRECTION
         ├─ same row → IGNORE_DUPLICATE
         └─ changed row → determine direction
                ├─ BACKWARD → IGNORE_BACKWARD
                ├─ UNKNOWN → IGNORE_UNKNOWN_DIRECTION
                └─ FORWARD
                     ├─ within previous observed range → IGNORE_REVISITED_POSITION
                     ├─ inside debounce interval → IGNORE_DEBOUNCE
                     └─ COUNT → queue native +1 and activity timestamp
```

The pure detector returns `ShortsTransitionResult(fromRow, toRow, direction,
decision)`. `TransitionDecision` is an internal native enum, not MethodChannel
business data. Repeated row notifications are ignored at any age; waiting does
not turn a duplicate into a count. The maximum is advanced even for debounced
new positions, preventing a later notification/rewatch from backfilling that miss.
Ignored movement never advances `lastCountedAt`; the 600 ms window is measured
from the last accepted count using a monotonic elapsed clock.

`COUNT` means accepted for a queued storage write, not proof that the write has
committed. On a write failure, the service logs an error and the store surfaces
the failure on reads. Detector history is not rolled back to retry that position.
Durability failures can therefore still cause missed counts.

## Changed structure and file inventory

Native implementation files are under
`android/app/src/main/kotlin/com/example/doom_meter/tracking/`:

```text
tracking/
├── AccessibilityEventLogger.kt       debug-only, redacted event metadata
├── AccessibilityUtils.kt             exact enabled-service check
├── DateKeyUtils.kt                   local yyyy-MM-dd keys
├── ScrollAccessibilityService.kt     event observation and sampling
├── ShortsTransitionDetector.kt       direction, positional history, debounce, decisions
├── YouTubeShortsViewerReader.kt      Android node-tree interpretation
├── ScrollTrackingStore.kt            serialized durable native persistence
└── ScrollTrackingChannel.kt          Flutter bridge and Settings action
```

Other Android configuration and test files:

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

Flutter tracking-specific files:

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

Flutter tracking-specific tests:

```text
test/core/platform/scroll_tracking_service_test.dart
test/features/home/native_counts_sync_test.dart
test/support/fake_scroll_tracking_service.dart
```

Existing `test/support/home_test_context.dart` and `test/app_test.dart` now inject
a fake tracking service; widget tests cover disclosure, settings dispatch, resume,
and manual editing restrictions. Existing unrelated README edits are preserved.

### Files changed for the 2 November forward-only revision

| File | Revision responsibility |
| --- | --- |
| `android/app/src/main/kotlin/com/example/doom_meter/tracking/ShortsTransitionDetector.kt` | Explicit direction/result/decision types, forward-only acceptance, highest-observed-row revisit suppression |
| `android/app/src/main/kotlin/com/example/doom_meter/tracking/ScrollAccessibilityService.kt` | Persist only `COUNT`; debug direction and ignored-decision reasons |
| `android/app/src/test/kotlin/com/example/doom_meter/tracking/ShortsTransitionDetectorTest.kt` | Forward/backward, retracing, ambiguity, debounce, range, and reset regression coverage |
| `android/app/src/main/res/values/strings.xml` | Android disclosure describes forward-only counting and limited repeat-visit recognition |
| `lib/features/home/presentation/widgets/youtube_tracking_section.dart` | Matching Home explanation and disclosure |
| `docs/youtube_shorts_tracking_poc.md` | Full technical reference, historical evidence, and current-rule validation |

No new dependencies, detector-specific Flutter entities, channels, history boxes,
background jobs, or generated-code changes are required for this revision.
`ScrollDirection`, `TransitionDecision`, and `ShortsTransitionResult` live in the
existing detector file, not hypothetical additional files.

The existing Home feature also uses `domain/entities/daily_counts.dart`,
`domain/params/get_daily_counts_params.dart`,
`domain/params/increment_social_count_params.dart`,
`domain/use_cases/get_daily_counts.dart`, and
`data/mappers/daily_counts_mapper.dart`. The mapper keeps the display entity
separate from Hive checkpoint metadata. `core/storage/local_storage_service.dart`
owns Flutter persistence; `core/utils/calendar_date.dart` and `local_clock.dart`
support date keys and testable manual/lifecycle time checks.

## Permission flow

Accessibility is a special Android setting, not a normal runtime permission.
The Home tracking section displays `Active`, `Disabled`, `Checking…`,
`Status unavailable`, or `Available on Android`, as appropriate. Its button opens
a disclosure explaining the observed app, metric, local storage, limitations,
native count authority, and how to disable access.

```text
Enable/Manage tracking
    → disclosure: Cancel / Open Settings
    → HomeTrackingPermissionRequested
    → ScrollTrackingService.openAccessibilitySettings
    → MethodChannel → Settings.ACTION_ACCESSIBILITY_SETTINGS
    → user manually enables Android's main service switch
    → Flutter resumes → status check + native sync + selected-day reload
```

Cancel does nothing. The app never toggles the service itself.
`AccessibilityUtils` compares the exact service `ComponentName` against
`AccessibilityManager.getEnabledAccessibilityServiceList(FEEDBACK_ALL_MASK)`.
Global accessibility enablement or another service being enabled is insufficient.
The Settings shortcut switch is separate from the main service switch; a floating
accessibility shortcut can toggle tracking off. `Active` means the service is
enabled, not a guarantee of perfect detection or immunity to OEM process limits.

### Accessibility capability audit (2 November 2026)

The service does not call `performAction`, `performGlobalAction`, or
`dispatchGesture`. Gesture injection was already disabled by default; the XML now
declares `android:canPerformGestures="false"` explicitly. This documents the
existing restriction rather than removing a previously granted capability.
`canRetrieveWindowContent="true"` is still required to read the viewer hierarchy,
resource IDs, geometry, and collection rows used by this detector. Removing it
would stop reliable structural detection. The YouTube package/event filters remain.

Android's **View and perform actions** disclosure is system-controlled, not a
separate runtime permission that this app can remove. Disabling gesture injection
does not create a platform-enforced read-only accessibility service: node/global
action APIs are separate, and this implementation does not use them. Both the app
disclosure and service description now explain the app's observational behavior
without claiming that Android's broader permission grant has disappeared.

References: [Android accessibility service configuration](https://developer.android.com/guide/topics/ui/accessibility/service),
[capability API](https://developer.android.com/reference/android/accessibilityservice/AccessibilityServiceInfo),
and [Android's system disclosure layout](https://android.googlesource.com/platform/frameworks/base/+/refs/heads/main/core/res/res/layout/accessibility_enable_service_warning.xml).

## Native SharedPreferences storage

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

`ScrollTrackingStore.getInstance(applicationContext)` owns the serialized queue.
`incrementYouTube` accepts a timestamp, derives its local date key, validates the
stored count, guards `Long.MAX_VALUE`, then commits `current + 1` and the timestamp
together. It contains no decrement operation and receives no backward delta.
`readDailyCounts` sorts count keys, validates date/count/time types, and returns
absolute records. A missing date has no native record until the first increment.

### Last activity timestamp

For newly recorded activity, `youtube_last_activity_<date>` represents the time
of the latest **successfully persisted new forward transition accepted by the
detector**. Backward movement, a duplicate, a recognized revisit, unknown metadata,
and a debounced transition do not enqueue writes or update that timestamp.

For example, count 30/time T followed by five backward transitions remains
30/time T. A later accepted new forward transition becomes 31/time T2. Wall-clock
time is used for calendar keys and displayed activity; elapsed time is used only
for debounce. Changing the wall clock is not required for date unit testing.

## Daily counter behavior and migration boundary

During automatic tracking, each day's native count only stays unchanged or
increases by one for an accepted transition. Backward movement never subtracts
from native storage, Hive, HomeBloc, or daily history. Sync propagates unchanged
absolute values after ignored movement, so no reverse-navigation update is needed.

Native keys use the local calendar day at detection. A newly encountered day
starts at zero; older keys remain intact. Manual taps remain restricted to today,
while native sync imports records under their own dates even when viewing history.
Date rollover does not need a reset timer or background Flutter task.

The rule change applies to subsequent detections. Existing aggregate totals and
timestamps are retained, including earlier bidirectional test counts; no per-video
history exists from which to recompute them. The schema does not version the
metric. A day spanning an upgrade can contain both definitions. Do not relabel
historical totals as exact unique discoveries.

Monotonic navigation behavior does not change the existing source-authority rule:
enabling automatic tracking may replace a larger manual test total in Hive with
the smaller native absolute total. That reconciliation is not a backward decrement.
No `max(Hive, native)` workaround is introduced, because it would preserve manual
test inflation and stop Hive from reflecting the authoritative native count.

## Flutter MethodChannel

The channel `com.example.doom_meter/scroll_tracking` exposes:

- `isAccessibilityTrackingEnabled`: compares the exact service component against
  AccessibilityManager's enabled services.
- `openAccessibilitySettings`: opens `Settings.ACTION_ACCESSIBILITY_SETTINGS`.
  Permission is always enabled by the user in Android Settings.
- `getDetectedDailyCounts`: returns maps with `date`, `youtubeCount`, and nullable
  `lastActivityAt`. The Flutter implementation validates the entire response,
  rejects duplicate/invalid dates, negative counts and malformed timestamps, and
  turns missing-plugin/platform/time-out failures into controlled errors.

Example response shape (illustrative values):

```text
[
  {date: "2026-11-02", youtubeCount: 30, lastActivityAt: <epoch milliseconds>}
]
```

`ScrollTrackingChannel` handles each call, queues storage reads, and posts results
back to the main looper. `dispose()` removes the handler and pending result
callbacks when the Flutter engine is cleaned up. The independently managed native
service and persisted totals are not disposed with the channel. Errors use
`tracking_storage` or `tracking_unavailable`; unknown methods are not implemented.
There is no event stream or method exposing viewing history/direction to Flutter.

## Flutter native tracking service

`ScrollTrackingService` exposes `isSupported`, `isTrackingEnabled()`,
`openAccessibilitySettings()`, and `getDetectedDailyCounts()`.
`ScrollTrackingServiceImpl` owns the MethodChannel, using the constants in
`scroll_tracking_channel_constants.dart`. Its native calls have a five-second
timeout and convert `MissingPluginException`, `PlatformException`, and timeout
failures into `ScrollTrackingException` messages suitable for recovery UI.

Support is Android and non-web only. Unsupported platforms return false/empty
counts without invoking Android, and opening Android settings reports an error.
`NativeDailyScrollCount.fromMap` validates a strict, round-tripped `yyyy-MM-dd`
date, nonnegative integer count, and nullable timestamp within Dart's supported
epoch range. Duplicate dates or any malformed item reject the entire native list
before the sync use case starts writing records.

## Hive synchronization and source authority

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

`SyncDetectedScrollCounts.call(trackingEnabled: ...)` reads the validated list
then awaits `HomeRepository.syncYouTubeDetectedCount` for each record.
`HomeRepositoryImpl` delegates to the single injected `HomeDataSource` and maps
the resulting model to `DailyCounts`. Within `HomeDataSource`, reads await pending
writes; both native sync and manual increments share the same write chain. A failed
operation is returned to its caller without poisoning later operations.

Idempotency example: native 50, Hive 45 → sync writes 50 → repeat sync remains 50.
Backward navigation with native 50 → resume/sync still leaves 50 and the existing
activity time. Direction decisions are never reimplemented as Flutter increments.
Instagram count/time and other dates are preserved by model `copyWith`.
Per-day writes are serialized, but importing many dates is not one cross-record
transaction: an error after earlier dates were saved can leave a partial import.
Retrying absolute snapshots is safe.

## BLoC integration and dependency injection

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

`HomeEvent` processing uses a single `asyncExpand` queue, so navigation, manual
increments, status checks, and sync do not race within a BLoC. `HomeDateChanged`
normalizes and reads the selected date without starting native sync. The other
load/refresh events resolve status and sync first, then load that selected day.
Tracking errors and daily-load errors have separate state fields and retry UI.

The actual added state fields are `isYouTubeTrackingEnabled`,
`isTrackingStatusKnown`, `isTrackingSupported`, `isTrackingStatusLoading`,
`isSyncingNativeCounts`, and `trackingErrorMessage`. The domain count remains in
`DailyCounts`; no parallel displayed total is introduced. Manual YouTube editing
requires today, known status, tracking disabled, and no status/sync work. Both
BLoC and `IncrementSocialCount` guard automatic tracking; the data source also
rechecks the manual date before its queued write to handle midnight.

`core/di/injection.dart` invokes the generated GetIt initializer. The tracking
platform implementation, repository, and data source are shared services;
`HomeBloc` is a factory. Widgets receive callbacks or dispatch events, never read
SharedPreferences/Hive directly, and never construct a second channel.

## Application lifecycle

`HomePage` creates its BLoC and sends `HomeStarted`. Its stateful view owns one
`AppLifecycleListener`, dispatches `HomeResumed` from `onResume`, and disposes the
listener with the view. Returning from YouTube or Accessibility Settings triggers
the same status/sync/read path; there is no continuously running Flutter timer.

If Home was showing today before rollover, resume moves to the new today. An
explicitly selected historical day remains selected. Sync still applies all
native records by their own date keys, then reads the displayed day.

Closing/recreating the Flutter Activity does not intentionally stop native
tracking. Service/process recreation retains committed native daily counts but
loses positional rewatch memory and pending uncommitted detections. Force-stop,
data clearing, uninstall, OEM restrictions, and some IDE reinstall workflows are
different lifecycle events and can stop tracking or clear settings/data. Existing
Hive remains available when native sync fails; the UI offers retry.

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

For this native-focused revision, the exact additional Gradle validation/build
command was run from `android/`:

```bash
./gradlew :app:testDebugUnitTest :app:assembleDebug
```

When using that direct Gradle build, install its actual output from the repository
root rather than assuming a previous Flutter CLI APK copy has been refreshed:

```bash
adb -s <device> install -r build/app/outputs/apk/debug/app-debug.apk
```

The forward-only revision did not change Injectable/Freezed declarations, so
regenerating those files was unnecessary. The full generation sequence above
remains the reference for future schema or DI edits.

Do not uninstall, clear app data, or force-stop the package during persistence
tests. On the investigation phone an IDE reinstall/force-stop cleared the enabled
service setting. An accessibility shortcut can also toggle the service off.
The floating Flutter shortcut is not an app-launch button. Verify the **main
service switch**, not just its shortcut assignment, after an IDE restart.

## Validated behavior: historical 1 November bidirectional build

The previous debug APK was tested on 2026-11-01 on Samsung SM-A127F (Galaxy A12),
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
| Backward feed: 2 gestures (old rule, superseded) | 8 → 10 (+2); rows 12 → 11 → 10; row 10 was a community photo post, a false classification for video-only counting. Under the new rule these backward rows must add zero. |
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

Local checks for that earlier build: **34 Flutter tests passed, 8 native tests passed**,
`flutter analyze` reported no issues, `git diff --check` passed, and the final
debug APK built successfully. The device results above expose missed feed
transitions and a community-post false classification. The new direction filter
does not resolve either underlying issue; the detector remains experimental.

## Current revision validation: 2 November

Automated validation for the forward-only revision:

| Check | Result |
| --- | --- |
| Native unit tests | 21 passed: 18 detector tests and 3 date-key tests; zero failures/errors/skips |
| Flutter tests | All 34 passed, including absolute/idempotent sync, lifecycle, history, manual guards, error recovery, and disclosure |
| Flutter static analysis | No issues found |
| Android debug build | `:app:assembleDebug` succeeded |
| Patch/document consistency | `git diff --check` passed; existing reference sections and historical measurements retained |
| Physical-device setup | Updated build installed with `adb install -r` on Samsung SM-A207F, Android 11, YouTube 21.43.523; user manually enabled the exact service, verified through Android settings and new decision logs |
| New-rule physical acceptance | Backward and positional-rewatch samples preserved both count and timestamp; new forward discovery counted. Forward acquisition still has row-metadata misses; see measured results below. |

### Physical measurements on 2 November

The new build was tested after manual enablement. The initial native Nov 2 record
was absent (count 0, timestamp null). Screen inspection confirmed Home and Shorts
before their respective samples. Inputs used 450 ms swipes with two-second pauses
unless stated otherwise; command/animation overhead adds to those timings.

| Sample | Native result | Timestamp / decision evidence |
| --- | --- | --- |
| Home: 10 upward gestures, 0.5-second pauses | 0 → 0 | Timestamp stayed null; `IGNORE_NOT_SHORTS` |
| Open Shorts at initial page | 0 → 0 | Timestamp stayed null; baseline only |
| Forward: 10 upward gestures | 0 → 9 | Accepted rows 1–6, 8–10; an intermediate page exposed row 0 and was classified backward |
| Backward: 5 downward gestures | 9 → 9 | Timestamp remained exactly `1793604666486`; backward and revisited-position decisions only |
| Rewatch: 5 upward retraces | 9 → 9 | Same timestamp `1793604666486`; forward returns to rows 6, 8, 9, 10 were `IGNORE_REVISITED_POSITION` |
| One new forward page beyond that range | 9 → 10 | `COUNT`; timestamp advanced to `1793604764065` |
| Slower forward: 20 gesture attempts | 10 → 28 (+18) | Observed rows advanced from 11 to 30, with `14 → 0 → 16`; 18 `COUNT` decisions and no debounce rejection |
| Faster forward: 20 attempts, 120 ms swipes, no added pause | 28 → 46 (+18) | Observed rows advanced from 30 to 49, with `30 → 0 → 32`; 18 `COUNT` decisions and no debounce rejection. ADB input overhead still spaces gestures. |
| Short-video comments: 5 gestures within the panel | 46 → 46 | Timestamp stayed exactly `1793604913398` |
| Flutter cold launch and recovery | Native 46 imported as Flutter 46 after resume | Initial slow launch displayed status unavailable/saved 0; normal background/resume recovered Active and 46 without reinstall or data reset |
| Flutter Activity closed: new, new, backward, rewatch, new | 46 → 47 → 48 → 48 → 48 → 49 | Activity absent from Android activity records; settled rows 49 → 50 → 51 → 50 → 51 → 52; backward/rewatch retained timestamp `1793605116468`, final new page advanced it to `1793605128352` |
| Reopen Flutter after the closed-Activity sample | Flutter displayed 49 and Active | Last activity displayed 13:08; native timestamp `1793605128352` |
| Three further background/resume cycles | Native and Flutter stayed 49 | No duplicated count or timestamp refresh; Instagram remained 0 |

The trace is important: upward navigation produced
`0 → 1 → 2 → 3 → 4 → 5 → 6 → 0 → 8 → 9 → 10`. The intermediate row 0 is not a
reliable feed-wide position. During backward traversal, returning from that row 0
to row 6 was numerically forward but was suppressed by the already-traversed
range. Thus these samples validate the **combined** direction/history decision,
not an unconditional claim that every YouTube collection row correctly describes
physical direction. No stable video identity was obtained, and the unknown item
type behind that anomalous row was not inferred from titles or content.

The initial forward sample's 9 counts for 10 attempted gestures is a measured
yield, not a general accuracy percentage. The new rule has not fixed unreliable
row metadata, skipped snapshots, or non-video item classification.

The phone was left on Doom Meter's Nov 2 Home page with YouTube 49, Instagram 0,
and Active status. These include test-generated counts; data was not cleared.
Temporary screenshots and the diagnostic capture were removed after recording
aggregate results. No service toggle, force-stop, reinstall, or code modification
was performed during these measurements.

This run verifies the listed same-context rewatch/backward, timestamp, Home,
Shorts-comment, Activity-closed, and synchronization scenarios. It does not complete
the entire matrix: search/subscriptions and standard-video surfaces need a new-rule
retest; service/process recreation, feed reordering, daily identity, and additional
devices/layouts remain unverified. Historical standard-video results are retained
separately and are not relabelled as current-build measurements.

The detector tests assert exact decisions for entry, unknown/negative metadata,
duplicates, ten new forward rows, five backward rows, rapid alternation, full
history retracing, movement below the entry position, animation gaps, blocked
panels, viewer changes, explicit reset, skipped rows, and the 600 ms boundary.
Ignored backward/rewatch observations do not move the last accepted-count time.
Twenty synthetic slow rows all count. Twenty synthetic rows spaced 100 ms apart
count only rows 1, 7, 13, and 19, deliberately exposing the retained debounce
limitation rather than claiming that rapid events cannot be lost.

These pure tests prove decisions for supplied structural snapshots; they do not
prove that every real YouTube page exposes that snapshot or has video identity.
Native date tests cover local midnight/timezone and strict historical date keys.
Flutter tests exercise the actual repository/Hive and BLoC synchronization paths.

## Merged Flutter regression and device validation: 7 November

The merged code initially failed two existing Flutter tests. Native record
validation compared `date.normalizedDate` (a `DateTime`) to the string key, rejecting
every valid native record. It now compares `date.dateKey`. The Home BLoC had also
lost its `HomeTrackingPermissionRequested` branch, so accepting the disclosure
reloaded counts without opening Settings. The handler is restored with controlled
error reporting. No detector rules, storage formats, or native channel methods changed.

Validation used Flutter 3.47.6 and the existing locked dependencies:

| Check | Result |
| --- | --- |
| `flutter test` | All 47 passed after the fixes, including the two previously failing tests |
| `flutter analyze` | No issues found |
| `:app:testDebugUnitTest --rerun` | 21 tests executed afresh; zero failures/errors/skips |
| `:app:assembleDebug` | Succeeded; existing Gradle/Kotlin/SDK warnings remain |
| Physical installation | Updated APK installed with `adb install -r`; no data clearing or uninstall |
| Accessibility capabilities | Service rebound and stayed enabled; `capabilities=1` (window content), no gesture-injection capability |

The physical run used Samsung SM-A127F, Android 13, YouTube 21.34.243. On Nov 7,
the native preference file was initially absent and Flutter showed zero counts.
Gestures used 450 ms swipes with roughly two-second pauses. Redacted structural
logs and native preferences were checked alongside screen captures.

| Sample | Observed result |
| --- | --- |
| Enter Shorts | Row 0 established a baseline; no increment |
| Five forward gestures | Rows 0 → 1 → 2 → 3 → 4 → 5; native count 0 → 5 |
| Three backward attempts | Two settled changes, 5 → 4 → 3; count stayed 5 and timestamp stayed `1794042318378` |
| Three upward gestures after going backward | Rows 3 → 4 → 5 were rejected as revisits; 5 → 6 was new and counted, giving 6 |
| Three Shorts-comments scrolls | 6 → 6; timestamp stayed `1794042356902`; zero COUNT decisions |
| Return to Flutter | YouTube 6, Instagram 0, Active; last YouTube activity displayed 2:35 PM |
| Manual counter guards | Instagram tap changed 0 → 1; YouTube tap left automatic count at 6 |
| Date navigation | Nov 6 showed 0/0 and read-only text; Nov 7 restored 1/6 |
| Disclosure → Open Settings | Updated explanation rendered; Android Accessibility Settings opened successfully |
| Three confirmed Home-feed swipes | 6 → 6; timestamp unchanged; 37 non-Shorts decisions and zero COUNT decisions |
| Three background/resume cycles | Each displayed Instagram 1, YouTube 6, Active; native count/timestamp unchanged |

An earlier feed/navigation attempt ended on a channel page and is excluded from
the confirmed Home sample. Three backward input attempts did not produce three
settled row changes; the subsequent third upward gesture reached a genuinely new
position. Results therefore distinguish input attempts from observed transitions.

The phone was returned to Doom Meter with **Instagram 1 / YouTube 6** for Nov 7.
These are test-generated values and were not reset. Existing saved data was not
cleared, and the service was not toggled during the run. This validates the listed
pipeline and regression scenarios on this device. Standard-video/search surfaces,
service/process recreation, midnight rollover on hardware, and cross-session
video identity were not retested here; earlier documented POC limitations remain.

## POC test matrix for the forward-only rule

For each physical sample, record device/Android/YouTube/build, enabled service,
confirmed screen, initial native count and timestamp, actual successful page
changes, logged settled rows/decisions, final native values, and resumed Flutter
values. Separate gesture attempts from observed transitions. Keep skipped or
obstructed samples out of accuracy conclusions. Do not clear the user's data or
change the device clock to make a test easier.

| Test | Sequence | Required result / interpretation |
| --- | --- | --- |
| Initial entry | Open YouTube, then Shorts at A | Count/time unchanged; A establishes baseline |
| Forward only | 10 confirmed new upward transitions | Target +10; report missed observations/debounce separately |
| Backward only | 5 confirmed downward transitions | +0; timestamp byte-for-byte unchanged; no decrement |
| Alternating | A → B → A → B | +1 within stable context; backward and return forward add zero |
| Forward sequence | A → B → C → D → E | +4, with no increment for initial A |
| Multiple backward | A → B → C → D, then D → C → B → A | First part +3; second part +0 |
| Rewatch then discovery | A → B → C → D, D → C → B, B → C → D, D → E | +3, +0, +0, +1 in the same context |
| Product example | Start 25; UP, UP, DOWN, DOWN, UP, UP, UP | Target 28 through stable consecutive positions |
| Fast forward | 20 fast gestures, manually record successful new pages | Measure count/misses; no guessed increments from row distance |
| Slow forward | 20 slow confirmed new pages | Target +20; investigate missing rows separately |
| Rapid alternation | UP, DOWN, UP, DOWN, UP, DOWN | DOWN never counts; recognized repeats never count; rapid new discovery may be debounced |
| Duplicate/idle | Remain on one Short during repeated events | +0 and no timestamp refresh |
| Missing metadata | No settled row / ambiguous direction | +0; retain baseline if viewer context still valid |
| Home/search/subscriptions | Scroll each confirmed non-viewer surface | +0; new revision physical retest required |
| Normal video | Scroll description/recommendations/comments | +0 |
| Shorts comments | Open and scroll the comments panel | +0; note if opening it resets rewatch context |
| Flutter closed | New, new, backward, recognized revisit, new | Target +3; reopen and compare native/Hive/UI |
| Flutter background/resume | Same sequence with Activity in recent apps | Same native result; resume imports once |
| Repeated sync | Native 50, Hive 45; sync repeatedly | Hive/UI 50, never 100/150 |
| Service recreation | Save total, manually disable/enable service, establish new baseline | Daily total survives; positional memory resets; cross-reset rewatch may count again |
| Process recreation | Restart only through an appropriate controlled lifecycle test | Committed total survives; no promise for pending writes or positional history |
| Midnight/history | Test date utilities and Hive/BLoC clock cases; selected historical date on device | New key starts separately; history selection/data preserved |
| Community posts/ads | Enter non-video items within Shorts feed | Known classification risk; direction filtering alone is not a fix |
| Context/feed changes | Exit/re-enter, replace/reorder feed, change viewer window | New baseline; document limits, do not claim daily identity |

State-machine tests cover the row-based core of these scenarios. Surface
classification, actual gesture mapping, persistence timestamps, and service
recreation also require physical tests. Never automatically toggle accessibility
to satisfy the service-restart test; the user must operate the switch.

Repeat this release-check sequence on each supported YouTube/device variant:

1. Disable the service manually; Home should show Disabled after resume.
2. Enable through the disclosure and Android's main switch; return to see Active.
3. Confirm Home feed, then scroll ten times; native/Hive delta must be zero.
4. Confirm a standard video; scroll recommendations, description, and comments;
   all must leave the Shorts total unchanged.
5. Record a starting total, enter Shorts, and perform ten slow then ten fast
   transitions. Record actual transitions and detected deltas separately.
6. Move backward and then forward through the same positions; both add zero.
   A subsequent new forward position is eligible for +1. Check timestamps too.
7. Open Shorts comments and scroll them; expect zero.
8. Close the Flutter Activity without force-stop; perform five Shorts transitions;
   reopen and compare native persistence with Home.
9. Repeat with Flutter in recent apps; returning should sync immediately.
10. Restart Home and repeat sync; totals must not multiply.
11. Exercise a new local date and a selected historical date. Use automated clock
    tests instead of changing the user's real clock without authorization.

## Debug logging and diagnostics

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

The raw event logger records event type/time/package/class, `fromIndex`, `toIndex`,
item count, scroll coordinates/maxima/deltas (where supported), source class/view
ID, change type, and a redacted description. It does not log `event.text`.
`ScrollAccessibilityService` logs the coalesced detector result independently:

```text
shortsViewer=true blocked=false fromRow=5 toRow=6 direction=FORWARD duplicate=false revisit=false action=COUNT
shortsViewer=true blocked=false fromRow=6 toRow=5 direction=BACKWARD duplicate=false revisit=false action=IGNORE_BACKWARD
shortsViewer=true blocked=false fromRow=5 toRow=6 direction=FORWARD duplicate=false revisit=true action=IGNORE_REVISITED_POSITION
shortsViewer=true blocked=false fromRow=6 toRow=6 direction=UNKNOWN duplicate=true revisit=false action=IGNORE_DUPLICATE
shortsViewer=true blocked=false fromRow=6 toRow=null direction=UNKNOWN duplicate=false revisit=false action=IGNORE_UNKNOWN_DIRECTION
```

These are illustrative formats, not invented device-test evidence. Other actions
are `IGNORE_DEBOUNCE` and `IGNORE_NOT_SHORTS`. `revisit` means the positional
suppression decision, not recognition of a stable video ID. `COUNT` precedes the
asynchronous commit; inspect persisted count/time and write-failure logs to verify
durability. Several raw accessibility events can contribute to one sampled
decision, so do not correlate them as one event equals one swipe.

For a count mismatch, check in order: exact service enabled/bound; correct YouTube
screen; required viewer nodes/geometry; settled row availability; context reset;
direction; repeated position; debounce; store write; channel read; Hive/UI sync.
Avoid changing debounce merely because the final count differs: missing snapshots
and non-video feed entries require different fixes.

## Privacy

Tracking is restricted to YouTube. No video-title/channel/comment/caption history,
search history, stable video-ID set, or identity hash is stored. Rewatch memory
contains only a viewer token, two integer row positions, and elapsed-count time;
it is discarded on the documented resets. Native preferences/Hive persist daily
aggregates and activity/checkpoint timestamps. Nothing in this tracking pipeline
uploads accessibility data to a server.

Temporary screenshots/tree inspection during development are local diagnostics,
not application features or datasets. Do not commit them; remove them when no
longer needed. Debug metadata is gated with `BuildConfig.DEBUG`. If a future
identity hash is proposed, document the exact input, need, retention, and reset
policy first; hashing titles/usernames is not an acceptable shortcut to a claim
of privacy-safe unique-video tracking.

## Known limitations

The 2 November forward-only run exposed occasional non-monotonic row metadata:
an upward move could report row 0 between higher feed positions. Such a sample
is numerically classified backward and does not count. Returning from row 0 can
be numerically forward even during a physical backward sequence; in the measured
sample, the highest-position guard suppressed it. Direction alone must not be
treated as reliable for every item layout. The slower and faster 20-gesture runs
each produced 18 counts; neither had a debounce rejection. The slow Flutter cold
launch also hit a status timeout, with normal resume recovering the native total.

Observed accuracy defects on the historical A12 build, still relevant to the
unchanged viewer sampling/classification in this revision:

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
Positional rewatch suppression is limited to the current structural context;
service resets, panel/viewer exits, repeated videos at different rows, and silent
feed reindexing prevent exact session-wide or daily unique-video counting.
No 100% accuracy or general absence of false positives is claimed. Native write
failures cannot guarantee durable counting. Reinstall/force-stop and OEM service
management may stop tracking. Data is local and does not migrate between phones.

Before production distribution: complete the remaining device matrix and accuracy
measurements; review the privacy policy, prominent disclosure, explicit consent,
disable flow, and current Play accessibility policy. This app does not claim to
be an accessibility tool.

## Future improvements and Instagram support

Priorities are to validate the new direction/rewatch rule on physical devices,
separate video pages from community posts/ads using measured structural signals,
investigate missed settled rows and event coalescing, and measure debounce across
slow/fast navigation. Preserve the conservative unknown-direction behavior and
retest non-Shorts surfaces after every detector refinement.

A stable, minimal, non-sensitive video identifier would enable stronger rewatch
recognition. No such identifier has been established here. Before adding a seen-ID
set or persistent daily deduplication, prove its stability across recycling,
reordering, viewer changes, and service recreation; define retention and migration.
Do not reinterpret existing aggregates as exact daily unique-video history.

Instagram automation is future work only. It needs its own observed event patterns,
viewer/direction/identity rules, disclosure, and tests. The isolated native reader
and detector can support a future per-platform adapter while keeping the same
storage → bridge → repository → BLoC structure. The current XML/package guard
remains YouTube-only, and Instagram remains a manual counter. No Instagram
accessibility listener or background service is added by this revision.

API references: [Android accessibility services](https://developer.android.com/guide/topics/ui/accessibility/views/service),
[enabled service list](https://developer.android.com/reference/android/view/accessibility/AccessibilityManager#getEnabledAccessibilityServiceList(int)),
[SharedPreferences commit](https://developer.android.com/reference/android/content/SharedPreferences.Editor#commit()).
