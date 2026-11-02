import 'package:auto_route/auto_route.dart';
import 'package:doom_meter/core/app_images.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/injection.dart';
import '../../domain/params/increment_social_count_params.dart';
import '../blocs/home/home_bloc.dart';
import '../blocs/home/home_event.dart';
import '../blocs/home/home_state.dart';
import '../widgets/home_date_navigation.dart';
import '../widgets/social_counter.dart';
import '../widgets/youtube_tracking_section.dart';

@RoutePage()
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => getIt<HomeBloc>()..add(const HomeStarted()),
      child: const _HomeView(),
    );
  }
}

class _HomeView extends StatefulWidget {
  const _HomeView();

  @override
  State<_HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<_HomeView> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => context.read<HomeBloc>().add(const HomeResumed()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: BlocBuilder<HomeBloc, HomeState>(
              builder: (context, state) {
                final bloc = context.read<HomeBloc>();
                final counts = state.counts;
                return SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 32,
                  ),
                  child: Column(
                    children: [
                      HomeDateNavigation(
                        date: state.selectedDate,
                        onDateChanged: (date) =>
                            bloc.add(HomeDateChanged(date)),
                      ),
                      const SizedBox(height: 32),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Image.asset(
                          AppImages.brainIcon,
                          width: 300,
                          height: 300,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(height: 32),
                      if (state.isLoading)
                        const SizedBox(
                          height: 160,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (counts != null)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SocialCounter(
                                platform: SocialPlatform.instagram,
                                count: counts.instagramCount,
                                lastActivityAt: counts.lastInstagramActivityAt,
                                enabled: state.isToday,
                                onTap: () => bloc.add(
                                  const HomeSocialIncrementRequested(
                                    SocialPlatform.instagram,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 24),
                            Expanded(
                              child: SocialCounter(
                                platform: SocialPlatform.youtube,
                                count: counts.youtubeCount,
                                lastActivityAt: counts.lastYoutubeActivityAt,
                                enabled: state.canManuallyIncrementYouTube,
                                onTap: () => bloc.add(
                                  const HomeSocialIncrementRequested(
                                    SocialPlatform.youtube,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(state.errorMessage!, textAlign: TextAlign.center),
                        TextButton.icon(
                          onPressed: () => bloc.add(const HomeRetryRequested()),
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Reload counts'),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        state.isToday
                            ? state.isYouTubeTrackingEnabled
                                  ? 'YouTube is automatic · Tap Instagram to simulate a scroll'
                                  : 'Tap an available counter to simulate a scroll'
                            : 'Read only · Only today can be updated',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      YouTubeTrackingSection(
                        state: state,
                        onSettingsRequested: () =>
                            bloc.add(const HomeTrackingPermissionRequested()),
                        onRetry: () =>
                            bloc.add(const HomeNativeCountsSyncRequested()),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
