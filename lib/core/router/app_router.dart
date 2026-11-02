import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';

import '../../features/home/presentation/pages/home_page.dart';

part 'app_router.gr.dart';

@lazySingleton
@AutoRouterConfig(replaceInRouteName: 'Page,Route')
class AppRouter extends RootStackRouter {
  @override
  List<AutoRoute> get routes => [
    AutoRoute(page: HomeRoute.page, path: '/', initial: true),
  ];
}
