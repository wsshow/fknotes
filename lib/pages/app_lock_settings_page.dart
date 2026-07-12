import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../providers/app_lock_controller.dart';
import '../services/app_lock_preferences_service.dart';
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
      appBar: AppBar(title: Text(context.l10n.appLock)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.softGreen,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: Icon(
                      Icons.fingerprint_rounded,
                      color: AppColors.moss,
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
    setState(() => _busy = true);
    final result = await context.read<AppLockController>().setEnabled(enabled);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!result.authenticated) {
      AppFeedback.error(
        context,
        _localizeLockMessage(context.l10n, result.message),
      );
    }
  }

  Future<void> _setTimeout(AppLockTimeout timeout) async {
    setState(() => _busy = true);
    final message = await context.read<AppLockController>().setTimeout(timeout);
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      AppFeedback.error(context, _localizeLockMessage(context.l10n, message));
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
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.line),
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
        ? const Icon(Icons.check_rounded, color: AppColors.moss)
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

String _localizeLockMessage(AppLocalizations l10n, String message) {
  // Controller error codes will replace these legacy strings when the native
  // authentication layer is migrated; keep current releases bilingual now.
  if (l10n.localeName.startsWith('zh')) return message;
  return switch (message) {
    '请先在系统设置中配置锁屏密码、指纹或人脸识别' =>
      'Set up a screen lock, fingerprint, or face unlock in system settings first.',
    '应用锁设置保存失败，请检查设备存储空间' =>
      'Could not save App lock settings. Check available storage.',
    _ => message,
  };
}
