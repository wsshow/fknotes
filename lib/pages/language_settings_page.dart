import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app.dart';
import '../l10n/generated/app_localizations.dart';
import '../l10n/l10n.dart';
import '../providers/app_locale_controller.dart';
import '../widgets/app_feedback.dart';

class LanguageSettingsPage extends StatefulWidget {
  const LanguageSettingsPage({super.key});

  @override
  State<LanguageSettingsPage> createState() => _LanguageSettingsPageState();
}

class _LanguageSettingsPageState extends State<LanguageSettingsPage> {
  AppLanguage? _saving;

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppLocaleController>();
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chooseLanguage),
        toolbarHeight: 64,
        titleTextStyle: Theme.of(context).textTheme.titleLarge,
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            Text(
              l10n.languageDescription,
              style: const TextStyle(color: AppColors.muted, height: 1.5),
            ),
            const SizedBox(height: 18),
            Material(
              color: AppColors.surface,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.large),
              ),
              child: Column(
                children: [
                  for (
                    var index = 0;
                    index < AppLanguage.values.length;
                    index++
                  ) ...[
                    _LanguageRow(
                      language: AppLanguage.values[index],
                      selected:
                          controller.language == AppLanguage.values[index],
                      saving: _saving == AppLanguage.values[index],
                      enabled: _saving == null,
                      onTap: () =>
                          _select(controller, AppLanguage.values[index]),
                    ),
                    if (index != AppLanguage.values.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _select(
    AppLocaleController controller,
    AppLanguage language,
  ) async {
    if (_saving != null || controller.language == language) return;
    setState(() => _saving = language);
    try {
      await controller.setLanguage(language);
    } catch (_) {
      if (mounted) AppFeedback.error(context, context.l10n.languageSaveFailed);
    } finally {
      if (mounted) setState(() => _saving = null);
    }
  }
}

class _LanguageRow extends StatelessWidget {
  final AppLanguage language;
  final bool selected;
  final bool saving;
  final bool enabled;
  final VoidCallback onTap;

  const _LanguageRow({
    required this.language,
    required this.selected,
    required this.saving,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      key: Key('app-language-${language.name}'),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      enabled: enabled,
      leading: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? AppColors.accentSoft : AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.small),
        ),
        child: Padding(
          padding: const EdgeInsets.all(9),
          child: Icon(
            _appLanguageIcon(language),
            size: 20,
            color: selected ? AppColors.accent : AppColors.muted,
          ),
        ),
      ),
      title: Text(
        _appLanguageTitle(l10n, language),
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(_appLanguageDescription(l10n, language)),
      trailing: saving
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : selected
          ? const Icon(Icons.check_circle_rounded, color: AppColors.accent)
          : const Icon(Icons.chevron_right_rounded, color: AppColors.subtle),
      onTap: enabled ? onTap : null,
    );
  }
}

String _appLanguageTitle(AppLocalizations l10n, AppLanguage language) =>
    switch (language) {
      AppLanguage.system => l10n.languageSystem,
      AppLanguage.simplifiedChinese => l10n.languageSimplifiedChinese,
      AppLanguage.english => l10n.languageEnglish,
    };

String _appLanguageDescription(AppLocalizations l10n, AppLanguage language) =>
    switch (language) {
      AppLanguage.system => l10n.languageSystemDescription,
      AppLanguage.simplifiedChinese =>
        l10n.languageSimplifiedChineseDescription,
      AppLanguage.english => l10n.languageEnglishDescription,
    };

IconData _appLanguageIcon(AppLanguage language) => switch (language) {
  AppLanguage.system => Icons.settings_suggest_outlined,
  AppLanguage.simplifiedChinese => Icons.translate_rounded,
  AppLanguage.english => Icons.language_rounded,
};
