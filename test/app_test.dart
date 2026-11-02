import 'package:doom_meter/app.dart';
import 'package:doom_meter/core/di/injection.dart';
import 'package:doom_meter/core/platform/scroll_tracking/scroll_tracking_service.dart';
import 'package:doom_meter/core/router/app_router.dart';
import 'package:doom_meter/core/storage/local_storage_service.dart';
import 'package:doom_meter/core/utils/local_clock.dart';
import 'package:doom_meter/features/home/domain/repositories/home_repository.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_bloc.dart';
import 'package:doom_meter/features/home/presentation/blocs/home/home_state.dart';
import 'package:doom_meter/features/home/presentation/widgets/home_date_navigation.dart';
import 'package:doom_meter/features/home/presentation/widgets/social_counter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'support/home_test_context.dart';
import 'support/fake_scroll_tracking_service.dart';

/// UI tests use synchronous-memory-backed persistence; real Hive I/O is covered
/// by the repository and Bloc integration suites without a simulated UI clock.
class _WidgetStorage extends LocalStorageService {
  _WidgetStorage() : super(Hive);
  final _boxes = <String, Map<String, Object?>>{};

  @override
  Future<T?> get<T>(String box, String key) async => _boxes[box]?[key] as T?;

  @override
  Future<void> put<T>(String box, String key, T value) async {
    (_boxes[box] ??= {})[key] = value;
  }
}

Future<void> waitForHome(
  WidgetTester tester,
  HomeBloc bloc,
  bool Function(HomeState) ready,
) async {
  await tester.pumpAndSettle();
  expect(
    ready(bloc.state),
    isTrue,
    reason: 'Unexpected Home state: ${bloc.state}',
  );
}

void main() {
  setUp(() async {
    await configureDependencies();
    await getIt.unregister<ScrollTrackingService>();
    getIt.registerSingleton<ScrollTrackingService>(FakeScrollTrackingService());
    // Test-only replacements; production registration is generated.
    await getIt.unregister<LocalClock>();
    getIt.registerSingleton<LocalClock>(
      TestClock(DateTime(2026, 10, 31, 15, 20)),
    );
    await getIt.unregister<LocalStorageService>();
    getIt.registerSingleton<LocalStorageService>(_WidgetStorage());
  });
  tearDown(() async {
    await getIt.reset();
  });

  test('DI creates Blocs and shares repository/storage instances', () async {
    final first = getIt<HomeBloc>();
    final second = getIt<HomeBloc>();
    addTearDown(first.close);
    addTearDown(second.close);
    expect(first, isNot(same(second)));
    expect(first.state.selectedDate, DateTime(2026, 10, 31));
    expect(getIt<HomeRepository>(), same(getIt<HomeRepository>()));
    expect(getIt<AppRouter>(), same(getIt<AppRouter>()));
    expect(getIt<LocalStorageService>(), same(getIt<LocalStorageService>()));
  });

  testWidgets(
    'taps persist, history disables editing, returning restores counts',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = getIt<AppRouter>();
      addTearDown(router.dispose);
      await tester.pumpWidget(App(appRouter: router));
      await tester.pump();
      final navigation = find.byType(HomeDateNavigation);
      final bloc = tester.element(navigation).read<HomeBloc>();
      await waitForHome(tester, bloc, (s) => s.counts != null && !s.isLoading);
      expect(router.current.name, HomeRoute.name);
      expect(find.text('0'), findsNWidgets(2));
      expect(find.text('No activity'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('instagram-counter')));
      await waitForHome(tester, bloc, (s) => s.counts?.instagramCount == 1);
      await tester.tap(find.byKey(const ValueKey('youtube-counter')));
      await waitForHome(tester, bloc, (s) => s.counts?.youtubeCount == 1);
      expect(find.text('1'), findsNWidgets(2));
      expect(find.textContaining('Last activity:'), findsNWidgets(2));

      await tester.tap(find.byTooltip('Previous day'));
      await waitForHome(
        tester,
        bloc,
        (s) => s.selectedDate == DateTime(2026, 10, 30) && !s.isLoading,
      );
      expect(
        tester
            .widgetList<SocialCounter>(find.byType(SocialCounter))
            .every((c) => !c.enabled),
        isTrue,
      );
      final disabled = tester.widget<InkWell>(
        find.byKey(const ValueKey('instagram-counter')),
      );
      expect(disabled.onTap, isNull);
      await tester.tap(find.byKey(const ValueKey('instagram-counter')));
      await tester.pumpAndSettle();
      expect(bloc.state.counts?.totalCount, 0);

      await tester.tap(find.byTooltip('Next day'));
      await waitForHome(
        tester,
        bloc,
        (s) => s.selectedDate == DateTime(2026, 10, 31) && !s.isLoading,
      );
      expect(find.text('1'), findsNWidgets(2));
      expect(
        tester
            .widgetList<SocialCounter>(find.byType(SocialCounter))
            .every((c) => c.enabled),
        isTrue,
      );
      await tester.tap(find.byTooltip('Next day'));
      await waitForHome(
        tester,
        bloc,
        (s) => s.selectedDate == DateTime(2026, 11, 1) && !s.isLoading,
      );
      expect(
        tester
            .widgetList<SocialCounter>(find.byType(SocialCounter))
            .every((c) => !c.enabled),
        isTrue,
      );

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(bloc.isClosed, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'settings require disclosure and resume refreshes tracking status',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final router = getIt<AppRouter>();
      addTearDown(router.dispose);
      final tracking =
          getIt<ScrollTrackingService>() as FakeScrollTrackingService;
      await tester.pumpWidget(App(appRouter: router));
      await tester.pumpAndSettle();
      final button = find.byKey(const ValueKey('youtube-tracking-settings'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(tracking.settingsOpened, 0);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(tracking.settingsOpened, 0);
      await tester.tap(button);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open Settings'));
      await tester.pumpAndSettle();
      expect(tracking.settingsOpened, 1);
      tracking.enabled = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Status: Active'), findsOneWidget);
      final youtube = tester
          .widgetList<SocialCounter>(find.byType(SocialCounter))
          .last;
      expect(youtube.enabled, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('Home remains usable on a narrow screen with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final router = getIt<AppRouter>();
    addTearDown(router.dispose);
    await tester.pumpWidget(App(appRouter: router));
    await tester.pump();
    final bloc = tester
        .element(find.byType(HomeDateNavigation))
        .read<HomeBloc>();
    await waitForHome(tester, bloc, (s) => s.counts != null && !s.isLoading);
    await tester.ensureVisible(find.text('YouTube'));
    await tester.pumpAndSettle();
    expect(find.text('Instagram'), findsOneWidget);
    expect(find.text('YouTube'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
