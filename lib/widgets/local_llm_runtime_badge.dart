import 'package:flutter/material.dart';

import '../app.dart';
import '../l10n/l10n.dart';
import '../models/local_llm.dart';

class LocalLlmRuntimeBadge extends StatelessWidget {
  final LocalLlmRuntimeSnapshot snapshot;
  final String modelId;
  final bool installed;

  const LocalLlmRuntimeBadge({
    super.key,
    required this.snapshot,
    required this.modelId,
    required this.installed,
  });

  @override
  Widget build(BuildContext context) {
    if (!installed) return const SizedBox.shrink();
    final status = _status(context);
    return Semantics(
      label: status.detail,
      child: ExcludeSemantics(
        child: Tooltip(
          message: status.detail,
          child: Container(
            key: const Key('local-llm-runtime-badge'),
            constraints: const BoxConstraints(minWidth: 38),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: status.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: status.border),
            ),
            child: Text(
              status.label,
              key: const Key('local-llm-runtime-badge-label'),
              textAlign: TextAlign.center,
              maxLines: 1,
              style: TextStyle(
                color: status.foreground,
                fontSize: 9,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ),
    );
  }

  _LocalLlmRuntimeStatus _status(BuildContext context) {
    final matchesModel = snapshot.model?.id == modelId;
    if (matchesModel && snapshot.state == LocalLlmEngineState.loading) {
      return _LocalLlmRuntimeStatus.neutral(
        label: context.l10n.modelRuntimeDetecting,
        detail: context.l10n.modelRuntimeDetecting,
      );
    }
    final backend = snapshot.activeBackend;
    if (matchesModel && backend != null) {
      final gpu = backend != LocalLlmBackend.cpu;
      final backendName = switch (backend) {
        LocalLlmBackend.cpu => 'CPU',
        LocalLlmBackend.openCl => 'OpenCL · GPU',
        LocalLlmBackend.vulkan => 'Vulkan · GPU',
        LocalLlmBackend.metal => 'Metal · GPU',
      };
      return _LocalLlmRuntimeStatus(
        label: gpu
            ? context.l10n.modelRuntimeGpu
            : context.l10n.modelRuntimeCpu,
        detail: context.l10n.modelRuntimeBackendDetail(backendName),
        background: gpu ? AppColors.softGreen : AppColors.canvas,
        foreground: gpu ? AppColors.moss : AppColors.muted,
        border: gpu ? AppColors.moss.withValues(alpha: 0.22) : AppColors.line,
      );
    }
    return _LocalLlmRuntimeStatus.neutral(
      label: context.l10n.modelRuntimeNotLoaded,
      detail: context.l10n.modelRuntimeNotLoaded,
    );
  }
}

class _LocalLlmRuntimeStatus {
  final String label;
  final String detail;
  final Color background;
  final Color foreground;
  final Color border;

  const _LocalLlmRuntimeStatus({
    required this.label,
    required this.detail,
    required this.background,
    required this.foreground,
    required this.border,
  });

  factory _LocalLlmRuntimeStatus.neutral({
    required String label,
    required String detail,
  }) => _LocalLlmRuntimeStatus(
    label: label,
    detail: detail,
    background: AppColors.canvas,
    foreground: AppColors.muted,
    border: AppColors.line,
  );
}
