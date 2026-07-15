import 'package:flutter/material.dart';

/// Prevents transient feedback from following users onto another page.
class AppFeedbackNavigatorObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (previousRoute != null) _dismissCurrentFeedback();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _dismissCurrentFeedback();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _dismissCurrentFeedback();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _dismissCurrentFeedback();
  }

  void _dismissCurrentFeedback() {
    final navigatorContext = navigator?.context;
    if (navigatorContext == null) return;
    final messenger = ScaffoldMessenger.maybeOf(navigatorContext);
    messenger
      ?..clearSnackBars()
      ..removeCurrentSnackBar();
  }
}
