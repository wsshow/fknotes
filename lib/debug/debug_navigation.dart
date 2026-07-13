import 'package:flutter/material.dart';

import 'app_diagnostics.dart';

List<NavigatorObserver> createDebugNavigatorObservers() => [
  _DebugNavigationObserver(),
];

class _DebugNavigationObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('route_pushed', route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('route_popped', route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AppDiagnostics.info(
      AppLogCategory.navigation,
      'route_replaced',
      data: {'route': _name(newRoute), 'previousRoute': _name(oldRoute)},
    );
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record('route_removed', route, previousRoute);
  }

  void _record(
    String event,
    Route<dynamic>? route,
    Route<dynamic>? previousRoute,
  ) {
    AppDiagnostics.info(
      AppLogCategory.navigation,
      event,
      data: {'route': _name(route), 'previousRoute': _name(previousRoute)},
    );
  }

  String _name(Route<dynamic>? route) {
    if (route == null) return '-';
    final configured = route.settings.name?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    return route.runtimeType.toString();
  }
}
