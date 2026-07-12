import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../providers/app_lock_controller.dart';
import '../services/device_authentication_service.dart';
import 'brand_mark.dart';

class AppLockGate extends StatelessWidget {
  final Widget child;

  const AppLockGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppLockController>();
    final prompt = _authenticationPrompt(context.l10n);
    if (controller.shouldAutomaticallyAuthenticate) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        controller.authenticateAutomatically(prompt: prompt);
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
            messageId: controller.messageId,
            onUnlock: () => controller.unlock(prompt: prompt),
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
  final DeviceAuthenticationMessage messageId;
  final VoidCallback onUnlock;

  const _AppLockScreen({
    required this.initializing,
    required this.locked,
    required this.obscured,
    required this.waitingForAuthentication,
    required this.message,
    required this.messageId,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final privacyOnly = obscured && !locked;
    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: privacyOnly ? l10n.privacyProtection : l10n.appLock,
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
                                      messageId: messageId,
                                      onUnlock: onUnlock,
                                    ),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.shield_outlined,
                            size: 15,
                            color: AppColors.muted,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              l10n.systemAuthenticationPrivacyFooter,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
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
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      const BrandMark(size: 42),
      const SizedBox(width: 11),
      Flexible(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.appTitle,
              style: const TextStyle(
                color: AppColors.ink,
                fontFamily: 'serif',
                fontSize: 17,
                height: 1.2,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              context.l10n.appTagline,
              style: const TextStyle(
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
  final DeviceAuthenticationMessage messageId;
  final VoidCallback onUnlock;

  const _AuthenticationCard({
    required this.initializing,
    required this.waitingForAuthentication,
    required this.message,
    required this.messageId,
    required this.onUnlock,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final waiting = initializing || waitingForAuthentication;
    final localizedMessage = _localizedAuthenticationMessage(
      l10n,
      messageId,
      message,
    );
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
                    label: l10n.waitingForSystemAuthentication,
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
                ? l10n.preparingAppLock
                : waitingForAuthentication
                ? l10n.waitingForSystemVerification
                : l10n.appLocked,
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
                ? l10n.loadingLocalSecuritySettings
                : waitingForAuthentication
                ? l10n.completeSystemAuthentication
                : l10n.unlockAppDescription,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 13.5,
              height: 1.45,
            ),
          ),
          if (!waiting && localizedMessage.isNotEmpty) ...[
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
                      localizedMessage,
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
                label: Text(l10n.authenticateAndUnlock),
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
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const DecoratedBox(
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
        context.l10n.contentHidden,
        style: const TextStyle(
          color: AppColors.ink,
          fontFamily: 'serif',
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

DeviceAuthenticationPrompt _authenticationPrompt(AppLocalizations l10n) =>
    DeviceAuthenticationPrompt(
      reason: l10n.authenticateToContinue,
      cancelButton: l10n.cancel,
      fallbackTitle: l10n.useDevicePassword,
    );

String _localizedAuthenticationMessage(
  AppLocalizations l10n,
  DeviceAuthenticationMessage messageId,
  String? fallback,
) => switch (messageId) {
  DeviceAuthenticationMessage.none => fallback ?? '',
  DeviceAuthenticationMessage.canceled => l10n.authenticationCanceled,
  DeviceAuthenticationMessage.credentialsRequired =>
    l10n.authenticationCredentialsRequired,
  DeviceAuthenticationMessage.unavailable => l10n.authenticationUnavailable,
  DeviceAuthenticationMessage.lockedOut => l10n.authenticationLockedOut,
  DeviceAuthenticationMessage.inProgress => l10n.authenticationInProgress,
  DeviceAuthenticationMessage.uiUnavailable => l10n.authenticationUiUnavailable,
  DeviceAuthenticationMessage.temporarilyUnavailable =>
    l10n.authenticationTemporarilyUnavailable,
  DeviceAuthenticationMessage.appLockSaveFailed => l10n.appLockSaveFailed,
  DeviceAuthenticationMessage.autoLockSaveFailed => l10n.autoLockSaveFailed,
  DeviceAuthenticationMessage.failed => l10n.authenticationFailedRetry,
};
