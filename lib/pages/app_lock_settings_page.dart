import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../providers/app_lock_controller.dart';
import '../services/app_lock_preferences_service.dart';

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
      appBar: AppBar(title: const Text('应用锁')),
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
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DecoratedBox(
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
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '使用系统身份验证',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        '通过设备已有的指纹、人脸识别或锁屏密码解锁。非空笔记不会读取或保存你的生物特征。',
                        style: TextStyle(
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
              title: const Text(
                '启用应用锁',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                controller.enabled ? '打开应用时会验证设备身份' : '默认关闭，不影响现有数据',
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
              '离开应用后自动锁定',
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
              label: const Text('立即锁定'),
            ),
          ],
          const SizedBox(height: 18),
          const Text(
            '应用锁用于阻止他人在已解锁设备上直接查看内容，不会加密数据库、附件或已经导出的备份。',
            style: TextStyle(color: AppColors.muted, fontSize: 12, height: 1.5),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(result.message)));
    }
  }

  Future<void> _setTimeout(AppLockTimeout timeout) async {
    setState(() => _busy = true);
    final message = await context.read<AppLockController>().setTimeout(timeout);
    if (!mounted) return;
    setState(() => _busy = false);
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
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
    title: Text(value.label),
    trailing: selected
        ? const Icon(Icons.check_rounded, color: AppColors.moss)
        : null,
  );
}
