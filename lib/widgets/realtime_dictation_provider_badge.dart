import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../services/realtime_dictation_service.dart';

class RealtimeDictationProviderBadge extends StatelessWidget {
  final RealtimeDictationExecutionProvider? provider;
  final bool fallback;

  const RealtimeDictationProviderBadge({
    super.key,
    required this.provider,
    this.fallback = false,
  });

  @override
  Widget build(BuildContext context) {
    final provider = this.provider;
    if (provider == null) return const SizedBox.shrink();
    final accelerated = provider != RealtimeDictationExecutionProvider.cpu;
    final detail = fallback
        ? context.l10n.dictationExecutionProviderFallback
        : context.l10n.dictationExecutionProvider(provider.label);
    return Semantics(
      label: detail,
      child: ExcludeSemantics(
        child: Tooltip(
          message: detail,
          child: Container(
            key: const Key('realtime-dictation-provider-badge'),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: accelerated ? AppColors.softGreen : AppColors.canvas,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: accelerated
                    ? AppColors.moss.withValues(alpha: 0.22)
                    : AppColors.line,
              ),
            ),
            child: Text(
              provider.label,
              key: const Key('realtime-dictation-provider-badge-label'),
              maxLines: 1,
              style: TextStyle(
                color: accelerated ? AppColors.moss : AppColors.muted,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
