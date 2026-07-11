import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../providers/app_lock_controller.dart';
import 'brand_mark.dart';

class AppLockGate extends StatelessWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppLockController>();
    if (controller.shouldAutomaticallyAuthenticate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.authenticateAutomatically();
      });
    }

    final protected =
        !controller.initialized || controller.locked || controller.obscured;
    return Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          excluding: protected,
          child: AbsorbPointer(absorbing: protected, child: child),
        ),
        if (protected)
          _AppLockScreen(
            initializing: !controller.initialized,
            locked: controller.locked,
            obscured: controller.obscured,
            authenticating: controller.authenticating,
            message: controller.message,
            onUnlock: controller.unlock,
          ),
      ],
    );
  }
}

class _AppLockScreen extends StatelessWidget {
  final bool initializing;
  final bool locked;
  final bool obscured;
  final bool authenticating;
  final String? message;
  final VoidCallback onUnlock;

  const _AppLockScreen({
    required this.initializing,
    required this.locked,
    required this.obscured,
    required this.authenticating,
    required this.message,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final privacyOnly = obscured && !locked;
    return ColoredBox(
      color: AppColors.canvas,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 36),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const BrandMark(size: 72),
                const SizedBox(height: 22),
                Text(
                  initializing || privacyOnly ? '非空笔记' : '非空笔记已锁定',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 9),
                Text(
                  initializing
                      ? '正在准备应用锁…'
                      : privacyOnly
                      ? '完全本地 · 私密可靠'
                      : message ?? '使用系统身份验证查看你的笔记',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.muted, height: 1.45),
                ),
                if (initializing || authenticating) ...[
                  const SizedBox(height: 24),
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  ),
                ] else if (!privacyOnly) ...[
                  const SizedBox(height: 26),
                  FilledButton.icon(
                    key: const Key('app-lock-unlock-button'),
                    onPressed: onUnlock,
                    icon: const Icon(Icons.fingerprint_rounded),
                    label: const Text('验证并解锁'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
