import 'package:flutter/material.dart';

import '../app.dart';

enum AppFeedbackTone { info, success, error }

class AppFeedback {
  AppFeedback._();

  static final Expando<_RecentFeedback> _recent = Expando<_RecentFeedback>();

  static void show(
    BuildContext context,
    String message, {
    AppFeedbackTone tone = AppFeedbackTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? duration,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null || message.trim().isEmpty) return;

    final now = DateTime.now();
    final recent = _recent[messenger];
    if (recent != null &&
        recent.message == message &&
        now.difference(recent.shownAt) < const Duration(milliseconds: 800)) {
      return;
    }
    _recent[messenger] = _RecentFeedback(message, now);

    final colors = _FeedbackColors.forTone(tone);
    messenger
      ..clearSnackBars()
      ..removeCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          key: const Key('app-feedback'),
          behavior: SnackBarBehavior.floating,
          elevation: 0,
          dismissDirection: DismissDirection.horizontal,
          showCloseIcon: true,
          closeIconColor: colors.foreground,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          duration:
              duration ??
              (tone == AppFeedbackTone.error
                  ? const Duration(seconds: 4)
                  : const Duration(milliseconds: 2200)),
          backgroundColor: colors.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: colors.border),
          ),
          content: Row(
            children: [
              Icon(colors.icon, size: 19, color: colors.foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: colors.foreground,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(
                  label: actionLabel,
                  textColor: colors.foreground,
                  onPressed: onAction,
                ),
        ),
      );
  }

  static void dismiss(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..clearSnackBars()
      ..removeCurrentSnackBar();
  }

  static void success(BuildContext context, String message) =>
      show(context, message, tone: AppFeedbackTone.success);

  static void error(BuildContext context, String message) =>
      show(context, message, tone: AppFeedbackTone.error);

  static void action(
    BuildContext context,
    String message, {
    required String actionLabel,
    required VoidCallback onAction,
  }) => show(
    context,
    message,
    actionLabel: actionLabel,
    onAction: onAction,
    duration: const Duration(seconds: 5),
  );
}

class _RecentFeedback {
  final String message;
  final DateTime shownAt;

  const _RecentFeedback(this.message, this.shownAt);
}

class _FeedbackColors {
  final Color background;
  final Color foreground;
  final Color border;
  final IconData icon;

  const _FeedbackColors({
    required this.background,
    required this.foreground,
    required this.border,
    required this.icon,
  });

  static _FeedbackColors forTone(AppFeedbackTone tone) => switch (tone) {
    AppFeedbackTone.info => const _FeedbackColors(
      background: AppColors.surface,
      foreground: AppColors.ink,
      border: AppColors.line,
      icon: Icons.info_outline_rounded,
    ),
    AppFeedbackTone.success => const _FeedbackColors(
      background: AppColors.softGreen,
      foreground: AppColors.moss,
      border: AppColors.line,
      icon: Icons.check_circle_outline_rounded,
    ),
    AppFeedbackTone.error => const _FeedbackColors(
      background: AppColors.softCoral,
      foreground: AppColors.coral,
      border: AppColors.coral,
      icon: Icons.error_outline_rounded,
    ),
  };
}
