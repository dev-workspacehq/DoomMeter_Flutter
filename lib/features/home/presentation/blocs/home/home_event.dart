import 'package:doom_meter/features/home/domain/params/increment_social_count_params.dart';

sealed class HomeEvent {
  const HomeEvent();
}

final class HomeStarted extends HomeEvent {
  const HomeStarted();
}

final class HomeDateChanged extends HomeEvent {
  const HomeDateChanged(this.date);
  final DateTime date;
}

final class HomeSocialIncrementRequested extends HomeEvent {
  const HomeSocialIncrementRequested(this.platform);
  final SocialPlatform platform;
}

final class HomeRetryRequested extends HomeEvent {
  const HomeRetryRequested();
}

/// Refresh on foregrounding, without timers or scheduled resets.
final class HomeResumed extends HomeEvent {
  const HomeResumed();
}
