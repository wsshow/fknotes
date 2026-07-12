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
            waitingForAuthentication:
                controller.authenticating ||
                controller.shouldAutomaticallyAuthenticate,
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
  final bool waitingForAuthentication;
  final String? message;
  final VoidCallback onUnlock;

  const _AppLockScreen({
    required this.initializing,
    required this.locked,
    required this.obscured,
    required this.waitingForAuthentication,
    required this.message,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final privacyOnly = obscured && !locked;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: privacyOnly ? '隐私保护' : '应用锁',
      child: Material(
        color: AppColors.canvas,
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - 42).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: _LockBrandHeader(),
                      ),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 390),
                              child: privacyOnly
                                  ? const _PrivacyOnlyState()
                                  : _AuthenticationCard(
                                      initializing: initializing,
                                      waitingForAuthentication:
                                          waitingForAuthentication,
                                      message: message,
                                      onUnlock: onUnlock,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            size: 15,
                            color: AppColors.muted,
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              '系统身份验证 · 本地内容保持私密',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.muted,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LockBrandHeader extends StatelessWidget {
  const _LockBrandHeader();

  @override
  Widget build(BuildContext context) => const Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      BrandMark(size: 42),
      SizedBox(width: 11),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '非空笔记',
              style: TextStyle(
                color: AppColors.ink,
                fontFamily: 'serif',
                fontSize: 17,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 2),
            Text(
              '完全本地 · 私密可靠',
              style: TextStyle(
                color: AppColors.muted,
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _AuthenticationCard extends StatelessWidget {
  final bool initializing;
  final bool waitingForAuthentication;
  final String? message;
  final VoidCallback onUnlock;

  const _AuthenticationCard({
    required this.initializing,
    required this.waitingForAuthentication,
    required this.message,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final waiting = initializing || waitingForAuthentication;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.line),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: .045),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: AppColors.softGreen,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: waiting
                ? Semantics(
                    label: '正在等待系统身份验证',
                    liveRegion: true,
                    child: const SizedBox(
                      width: 27,
                      height: 27,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                  )
                : const Icon(
                    Icons.lock_outline_rounded,
                    size: 31,
                    color: AppColors.moss,
                  ),
          ),
          const SizedBox(height: 20),
          Text(
            initializing
                ? '正在准备应用锁'
                : waitingForAuthentication
                ? '等待系统验证'
                : '应用已锁定',
            key: const Key('app-lock-state-title'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.ink,
              fontFamily: 'serif',
              fontSize: 23,
              height: 1.25,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            initializing
                ? '正在载入本地安全设置'
                : waitingForAuthentication
                ? '请在系统弹窗中完成身份验证'
                : '验证设备身份后继续使用非空笔记',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          if (!waiting && message?.isNotEmpty == true) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: AppColors.softAmber,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.muted,
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      message!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!waiting) ...[
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('app-lock-unlock-button'),
                onPressed: onUnlock,
                icon: const Icon(Icons.fingerprint_rounded, size: 21),
                label: const Text('验证并解锁'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PrivacyOnlyState extends StatelessWidget {
  const _PrivacyOnlyState();

  @override
  Widget build(BuildContext context) => const Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.softGreen,
          shape: BoxShape.circle,
        ),
        child: Padding(
          padding: EdgeInsets.all(19),
          child: Icon(
            Icons.visibility_off_outlined,
            size: 31,
            color: AppColors.moss,
          ),
        ),
      ),
      SizedBox(height: 18),
      Text(
        '内容已隐藏',
        style: TextStyle(
          color: AppColors.ink,
          fontFamily: 'serif',
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}
