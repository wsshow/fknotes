import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../providers/app_lock_controller.dart';
import '../services/app_lock_preferences_service.dart';
import '../services/device_authentication_service.dart';
import '../widgets/app_feedback.dart';

class AppLockSettingsPage extends StatefulWidget {
  const AppLockSettingsPage({super.key});

  @override
  State<AppLockSettingsPage> createState() => _AppLockSettingsPageState();
}

class _AppLockSettingsPageState extends State<AppLockSettingsPage> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppLockController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.appLock),
        toolbarHeight: 64,
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.large),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.all(
                      Radius.circular(AppRadius.small),
                    ),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.fingerprint_rounded,
                      color: AppColors.muted,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.l10n.systemAuthentication,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        context.l10n.systemAuthenticationDescription,
                        style: const TextStyle(
                          color: AppColors.muted,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _SettingsCard(
            child: SwitchListTile.adaptive(
              key: const Key('app-lock-enabled-switch'),
              value: controller.enabled,
              onChanged: _busy ? null : _setEnabled,
              title: Text(
                context.l10n.enableAppLock,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                controller.enabled
                    ? context.l10n.appLockEnabledDescription
                    : context.l10n.appLockDisabledDescription,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
            ),
          ),
          if (controller.enabled) ...[
            const SizedBox(height: 24),
            Text(
              context.l10n.autoLockAfterLeaving,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            _SettingsCard(
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < AppLockTimeout.values.length;
                    index++
                  ) ...[
                    _TimeoutTile(
                      value: AppLockTimeout.values[index],
                      selected:
                          controller.timeout == AppLockTimeout.values[index],
                      onTap: _busy
                          ? null
                          : () => _setTimeout(AppLockTimeout.values[index]),
                    ),
                    if (index < AppLockTimeout.values.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              key: const Key('app-lock-lock-now-button'),
              onPressed: _busy ? null : controller.lockNow,
              icon: const Icon(Icons.lock_outline_rounded),
              label: Text(context.l10n.lockNow),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            context.l10n.appLockLimitDescription,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setEnabled(bool enabled) async {
    final l10n = context.l10n;
    setState(() => _busy = true);
    final result = await context.read<AppLockController>().setEnabled(
      enabled,
      prompt: DeviceAuthenticationPrompt(
        reason: enabled
            ? l10n.authenticateToEnableAppLock
            : l10n.authenticateToDisableAppLock,
        cancelButton: l10n.cancel,
        fallbackTitle: l10n.useDevicePassword,
      ),
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.authenticated) {
      AppFeedback.error(context, _localizeLockResult(context.l10n, result));
    }
  }

  Future<void> _setTimeout(AppLockTimeout timeout) async {
    setState(() => _busy = true);
    final message = await context.read<AppLockController>().setTimeout(timeout);
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      AppFeedback.error(context, context.l10n.autoLockSaveFailed);
    }
  }
}

class _SettingsCard extends StatelessWidget {
  final Widget child;

  const _SettingsCard({required this.child});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.large),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

class _TimeoutTile extends StatelessWidget {
  final AppLockTimeout value;
  final bool selected;
  final VoidCallback? onTap;

  const _TimeoutTile({
    required this.value,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    title: Text(_timeoutLabel(context.l10n, value)),
    trailing: selected
        ? const Icon(Icons.check_rounded, color: AppColors.accent)
        : null,
  );
}

String _timeoutLabel(AppLocalizations l10n, AppLockTimeout timeout) =>
    switch (timeout) {
      AppLockTimeout.immediately => l10n.lockImmediately,
      AppLockTimeout.oneMinute => l10n.lockAfterOneMinute,
      AppLockTimeout.fiveMinutes => l10n.lockAfterFiveMinutes,
      AppLockTimeout.fifteenMinutes => l10n.lockAfterFifteenMinutes,
    };

String _localizeLockResult(
  AppLocalizations l10n,
  DeviceAuthenticationResult result,
) => switch (result.messageId) {
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
  DeviceAuthenticationMessage.none => switch (result.status) {
    DeviceAuthenticationStatus.canceled => l10n.authenticationCanceled,
    DeviceAuthenticationStatus.unavailable => l10n.authenticationUnavailable,
    DeviceAuthenticationStatus.lockedOut => l10n.authenticationLockedOut,
    DeviceAuthenticationStatus.failed => l10n.authenticationFailedRetry,
    DeviceAuthenticationStatus.authenticated => '',
  },
};
