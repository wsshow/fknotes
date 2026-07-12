import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/local_model.dart';
import '../services/local_model_manager.dart';
import '../services/realtime_dictation_preferences_service.dart';
import '../widgets/editor_context_menu.dart';

class ModelManagementPage extends StatefulWidget {
  final String? focusModelId;
  const ModelManagementPage({super.key, this.focusModelId});

  @override
  State<ModelManagementPage> createState() => _ModelManagementPageState();
}

class _ModelManagementPageState extends State<ModelManagementPage> {
  final _manager = LocalModelManager.instance;
  final _dictationPreferences = RealtimeDictationPreferencesService.instance;
  RealtimeDictationPreferences _preferences =
      const RealtimeDictationPreferences();

  @override
  void initState() {
    super.initState();
    _manager.addListener(_changed);
    // Model files may have been replaced by an app upgrade or removed outside
    // this page. Always validate the on-disk runtime instead of showing a
    // possibly stale singleton snapshot.
    unawaited(_manager.initialize(force: true));
    unawaited(_loadDictationPreferences());
  }

  Future<void> _loadDictationPreferences() async {
    final preferences = await _dictationPreferences.load();
    if (mounted) setState(() => _preferences = preferences);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _manager.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = _manager.models
        .where((model) => model.category == LocalModelCategory.language)
        .toList();
    final speech = _manager.models
        .where((model) => model.category == LocalModelCategory.speech)
        .toList();
    final vision = _manager.models
        .where((model) => model.category == LocalModelCategory.vision)
        .toList();
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        title: const Text(
          '本地模型',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            _ModelSummary(
              installedCount: _manager.installedCount,
              installedSizeBytes: _manager.installedSizeBytes,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(15),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 19,
                    color: AppColors.moss,
                  ),
                  SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      '只有下载模型时需要联网。笔记、图片、音频和识别结果不会上传。模型不进入笔记备份。',
                      style: TextStyle(color: AppColors.muted, height: 1.55),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            _sectionTitle('语言模型'),
            const SizedBox(height: 6),
            const Text(
              '由用户下载并选择本地助手使用的模型，默认上下文为 4096。',
              style: TextStyle(color: AppColors.muted, height: 1.45),
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < language.length; index++) ...[
              _ModelCard(
                definition: language[index],
                installation: _manager.installationOf(language[index].id),
                transfer: _manager.transferOf(language[index].id),
                emphasized: language[index].id == widget.focusModelId,
                selectedForAssistant:
                    language[index].id == _manager.selectedAssistantModelId,
                onDownload: () => _confirmDownload(language[index]),
                onImport: () => _manager.import(language[index].id),
                onCancel: () => _manager.cancel(language[index].id),
                onRemove: () => _confirmRemove(language[index]),
                onSelect: () => _selectForAssistant(language[index]),
                onDetails: () => _showDetails(language[index]),
              ),
              if (index != language.length - 1) const SizedBox(height: 12),
            ],
            const SizedBox(height: 26),
            _sectionTitle('实时听写设置'),
            const SizedBox(height: 12),
            _HotwordsCard(preferences: _preferences, onTap: _editHotwords),
            const SizedBox(height: 12),
            _TwoPassCard(
              enabled: _preferences.twoPassEnabled,
              onChanged: _setTwoPassEnabled,
            ),
            const SizedBox(height: 12),
            _NoiseSuppressionCard(
              enabled: _preferences.noiseSuppressionEnabled,
              modelInstalled: _manager
                  .installationOf(LocalModelManager.speechDenoiserId)
                  .installed,
              onChanged: _setNoiseSuppressionEnabled,
            ),
            const SizedBox(height: 26),
            _sectionTitle('语音模型'),
            const SizedBox(height: 12),
            for (var index = 0; index < speech.length; index++) ...[
              _ModelCard(
                definition: speech[index],
                installation: _manager.installationOf(speech[index].id),
                transfer: _manager.transferOf(speech[index].id),
                emphasized: speech[index].id == widget.focusModelId,
                selectedForLiveDictation:
                    speech[index].id == _manager.selectedLiveDictationModelId,
                onDownload: () => _confirmDownload(speech[index]),
                onImport: () => _manager.import(speech[index].id),
                onCancel: () => _manager.cancel(speech[index].id),
                onRemove: () => _confirmRemove(speech[index]),
                onSelect: () => _selectForLiveDictation(speech[index]),
                onDetails: () => _showDetails(speech[index]),
              ),
              if (index != speech.length - 1) const SizedBox(height: 12),
            ],
            if (vision.isNotEmpty) ...[
              const SizedBox(height: 26),
              _sectionTitle('视觉模型'),
              const SizedBox(height: 12),
              for (var index = 0; index < vision.length; index++) ...[
                _ModelCard(
                  definition: vision[index],
                  installation: _manager.installationOf(vision[index].id),
                  transfer: _manager.transferOf(vision[index].id),
                  onDownload: () => _confirmDownload(vision[index]),
                  onImport: () => _manager.import(vision[index].id),
                  onCancel: () => _manager.cancel(vision[index].id),
                  onRemove: () => _confirmRemove(vision[index]),
                  onSelect: () {},
                  onDetails: () => _showDetails(vision[index]),
                ),
                if (index != vision.length - 1) const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
  );

  Future<void> _confirmDownload(LocalModelDefinition model) async {
    final installation = _manager.installationOf(model.id);
    final remaining = (model.downloadSizeBytes - installation.partialSizeBytes)
        .clamp(0, model.downloadSizeBytes);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(installation.partialSizeBytes > 0 ? '继续下载模型？' : '下载模型？'),
        content: Text(
          '${model.name}\n还需下载约 ${_formatBytes(remaining)}，建议使用 Wi-Fi。\n\n'
          '下载中可离开此页面；中断后会保留进度。'
          '${model.task == LocalModelTask.textToSpeech ? '\n\n解压安装时请预留约 600 MB 可用空间。' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始下载'),
          ),
        ],
      ),
    );
    if (confirmed == true) unawaited(_manager.download(model.id));
  }

  Future<void> _confirmRemove(LocalModelDefinition model) async {
    final size = _manager.installationOf(model.id).installedSizeBytes;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('移除${model.name}？'),
        content: Text('将释放约 ${_formatBytes(size)} 空间。已经生成的笔记内容不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('移除模型'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _manager.remove(model.id);
      await _loadDictationPreferences();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _selectForLiveDictation(LocalModelDefinition model) async {
    if (model.task != LocalModelTask.liveDictation) return;
    try {
      await _manager.selectForLiveDictation(model.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已将${model.name}设为实时听写模型')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _selectForAssistant(LocalModelDefinition model) async {
    if (model.task != LocalModelTask.textGeneration) return;
    try {
      await _manager.selectForAssistant(model.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已将${model.name}设为本地助手模型')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.toString().replaceFirst('Bad state: ', '')),
          ),
        );
      }
    }
  }

  Future<void> _editHotwords() async {
    final result = await showModalBottomSheet<RealtimeDictationPreferences>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) =>
          _HotwordsSheet(initial: _preferences, service: _dictationPreferences),
    );
    if (result == null || !mounted) return;
    setState(() => _preferences = result);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.hotwordsEnabled
              ? '已保存 ${result.hotwords.length} 个热词'
              : '已关闭实时听写热词',
        ),
      ),
    );
  }

  Future<void> _setTwoPassEnabled(bool enabled) async {
    try {
      final saved = await _dictationPreferences.save(
        hotwordsText: _preferences.hotwords.join('\n'),
        hotwordsScore: _preferences.hotwordsScore,
        twoPassEnabled: enabled,
        noiseSuppressionEnabled: _preferences.noiseSuppressionEnabled,
      );
      if (!mounted) return;
      setState(() => _preferences = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? '已开启听写结束精修' : '已关闭听写结束精修')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置保存失败，请检查设备存储空间')));
      }
    }
  }

  Future<void> _setNoiseSuppressionEnabled(bool enabled) async {
    try {
      final saved = await _dictationPreferences.save(
        hotwordsText: _preferences.hotwords.join('\n'),
        hotwordsScore: _preferences.hotwordsScore,
        twoPassEnabled: _preferences.twoPassEnabled,
        noiseSuppressionEnabled: enabled,
      );
      if (!mounted) return;
      setState(() => _preferences = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(enabled ? '已开启实时听写降噪' : '已关闭实时听写降噪')),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设置保存失败，请检查设备存储空间')));
      }
    }
  }

  void _showDetails(LocalModelDefinition model) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 0, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(model.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(model.description, style: const TextStyle(height: 1.55)),
              const SizedBox(height: 18),
              _DetailRow('用途', model.summary),
              _DetailRow('引擎', model.engine),
              if (model.languages.isNotEmpty)
                _DetailRow('语言', model.languages.join('、')),
              if (model.version.isNotEmpty) _DetailRow('版本', model.version),
              if (model.source.isNotEmpty) _DetailRow('来源', model.source),
              if (model.license.isNotEmpty) _DetailRow('许可', model.license),
            ],
          ),
        ),
      ),
    );
  }
}

class _HotwordsSheet extends StatefulWidget {
  final RealtimeDictationPreferences initial;
  final RealtimeDictationPreferencesService service;

  const _HotwordsSheet({required this.initial, required this.service});

  @override
  State<_HotwordsSheet> createState() => _HotwordsSheetState();
}

class _HotwordsSheetState extends State<_HotwordsSheet> {
  late final TextEditingController _controller;
  late double _score;
  String? _validationMessage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initial.hotwords.join('\n'),
    );
    _score = widget.initial.hotwordsScore;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _validationMessage = null;
    });
    try {
      final saved = await widget.service.save(
        hotwordsText: _controller.text,
        hotwordsScore: _score,
        twoPassEnabled: widget.initial.twoPassEnabled,
        noiseSuppressionEnabled: widget.initial.noiseSuppressionEnabled,
      );
      if (mounted) Navigator.pop(context, saved);
    } on FormatException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _validationMessage = error.message.toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _validationMessage = '保存失败，请检查设备存储空间';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    final availableHeight =
        MediaQuery.sizeOf(context).height - keyboardInset - 24;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '实时听写热词',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text(
                  '每行输入一个人名、产品名或专业术语；留空即关闭。热词从下一次听写开始生效。',
                  style: TextStyle(color: AppColors.muted, height: 1.45),
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          key: const Key('live-dictation-hotwords-field'),
                          controller: _controller,
                          contextMenuBuilder: buildAppEditableTextContextMenu,
                          minLines: 4,
                          maxLines: 8,
                          autofocus: true,
                          decoration: InputDecoration(
                            hintText: '非空笔记\nFKNotes\nsherpa onnx',
                            labelText: '热词列表',
                            errorText: _validationMessage,
                            alignLabelWithHint: true,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            const Expanded(child: Text('增强强度')),
                            Text(
                              _score.toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          key: const Key('live-dictation-hotwords-score'),
                          value: _score,
                          min: RealtimeDictationPreferencesService
                              .minHotwordsScore,
                          max: RealtimeDictationPreferencesService
                              .maxHotwordsScore,
                          divisions: 8,
                          label: _score.toStringAsFixed(1),
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _score = value),
                        ),
                        const Text(
                          '过高的强度可能把发音相近的普通词误判为热词，建议先使用 2.0。',
                          style: TextStyle(
                            color: AppColors.muted,
                            fontSize: 12,
                            height: 1.45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const Key('save-live-dictation-hotwords'),
                        onPressed: _saving ? null : _save,
                        child: Text(_saving ? '保存中…' : '保存'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TwoPassCard extends StatelessWidget {
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _TwoPassCard({required this.enabled, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(Icons.auto_fix_high_rounded, color: AppColors.moss),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '结束后精修',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              SizedBox(height: 4),
              Text(
                '使用 SenseVoice 二次识别，仅在质量检查通过时替换（默认关闭）',
                style: TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
        Switch(
          key: const Key('live-dictation-two-pass-switch'),
          value: enabled,
          onChanged: onChanged,
        ),
      ],
    ),
  );
}

class _NoiseSuppressionCard extends StatelessWidget {
  final bool enabled;
  final bool modelInstalled;
  final ValueChanged<bool> onChanged;

  const _NoiseSuppressionCard({
    required this.enabled,
    required this.modelInstalled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.noise_control_off_rounded,
            color: AppColors.moss,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '实时降噪',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                modelInstalled ? '先抑制环境噪声，再送入流式识别' : '请先安装下方的 DPDFNet 实时降噪模型',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
        Switch(
          key: const Key('live-dictation-noise-suppression-switch'),
          value: modelInstalled && enabled,
          onChanged: modelInstalled ? onChanged : null,
        ),
      ],
    ),
  );
}

class _HotwordsCard extends StatelessWidget {
  final RealtimeDictationPreferences preferences;
  final VoidCallback onTap;

  const _HotwordsCard({required this.preferences, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.line),
    ),
    child: InkWell(
      key: const Key('live-dictation-hotwords-card'),
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.softGreen,
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.local_fire_department_outlined,
                color: AppColors.moss,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '热词增强',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preferences.hotwordsEnabled
                        ? '${preferences.hotwords.length} 个热词 · 强度 '
                              '${preferences.hotwordsScore.toStringAsFixed(1)}'
                        : '优先识别人名、品牌与专业术语',
                    style: const TextStyle(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    ),
  );
}

class _ModelSummary extends StatelessWidget {
  final int installedCount;
  final int installedSizeBytes;
  const _ModelSummary({
    required this.installedCount,
    required this.installedSizeBytes,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppColors.line),
    ),
    child: Row(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.softGreen,
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.memory_rounded, color: AppColors.moss),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$installedCount 个模型可用',
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '可选模型占用 ${_formatBytes(installedSizeBytes)}',
                style: const TextStyle(color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ModelCard extends StatelessWidget {
  final LocalModelDefinition definition;
  final LocalModelInstallation installation;
  final ModelTransferState? transfer;
  final bool emphasized;
  final bool selectedForLiveDictation;
  final bool selectedForAssistant;
  final VoidCallback onDownload;
  final VoidCallback onImport;
  final VoidCallback onCancel;
  final VoidCallback onRemove;
  final VoidCallback onSelect;
  final VoidCallback onDetails;
  const _ModelCard({
    required this.definition,
    required this.installation,
    required this.transfer,
    this.emphasized = false,
    this.selectedForLiveDictation = false,
    this.selectedForAssistant = false,
    required this.onDownload,
    required this.onImport,
    required this.onCancel,
    required this.onRemove,
    required this.onSelect,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final running = transfer?.isRunning == true;
    final icon = switch (definition.task) {
      LocalModelTask.audioTranscription => Icons.graphic_eq_rounded,
      LocalModelTask.liveDictation => Icons.mic_rounded,
      LocalModelTask.voiceActivityDetection => Icons.multiline_chart_rounded,
      LocalModelTask.speechEnhancement => Icons.noise_control_off_rounded,
      LocalModelTask.speakerDiarization => Icons.groups_2_outlined,
      LocalModelTask.textToSpeech => Icons.record_voice_over_rounded,
      LocalModelTask.textGeneration => Icons.auto_awesome_rounded,
      LocalModelTask.textRecognition => Icons.document_scanner_rounded,
      LocalModelTask.imageUnderstanding => Icons.image_search_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: emphasized ? AppColors.moss : AppColors.line,
          width: emphasized ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.softGreen,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppColors.moss),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            definition.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (definition.recommended) ...[
                          const SizedBox(width: 7),
                          const _StatusBadge(label: '推荐'),
                        ],
                        if (selectedForLiveDictation &&
                            definition.task ==
                                LocalModelTask.liveDictation) ...[
                          const SizedBox(width: 7),
                          _StatusBadge(
                            label: '当前听写',
                            installed: installation.installed,
                          ),
                        ],
                        if (selectedForAssistant &&
                            installation.installed &&
                            definition.task ==
                                LocalModelTask.textGeneration) ...[
                          const SizedBox(width: 7),
                          const _StatusBadge(label: '当前助手', installed: true),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      definition.summary,
                      style: const TextStyle(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '模型详情',
                onPressed: onDetails,
                icon: const Icon(Icons.info_outline_rounded, size: 21),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _MetaChip(label: definition.engine),
              if (definition.downloadSizeBytes > 0)
                _MetaChip(label: _formatBytes(definition.downloadSizeBytes)),
              if (definition.languages.isNotEmpty)
                _MetaChip(label: definition.languages.take(2).join(' / ')),
            ],
          ),
          if (running) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: transfer!.progress <= 0 ? null : transfer!.progress,
              minHeight: 7,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _transferDescription(transfer!),
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                if (transfer!.status == ModelTransferStatus.verifying ||
                    transfer!.status == ModelTransferStatus.canceling ||
                    !transfer!.cancelable)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      '请稍候',
                      style: TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                  )
                else
                  TextButton(onPressed: onCancel, child: const Text('取消')),
              ],
            ),
          ] else ...[
            const SizedBox(height: 15),
            _actions(context),
          ],
          if (transfer?.status == ModelTransferStatus.failed) ...[
            const SizedBox(height: 9),
            Text(
              transfer?.errorMessage ?? '模型下载失败',
              style: const TextStyle(color: AppColors.coral, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _actions(BuildContext context) {
    if (definition.availability == LocalModelAvailability.builtIn) {
      return const Align(
        alignment: Alignment.centerRight,
        child: _StatusBadge(label: '随应用提供', installed: true),
      );
    }
    if (definition.availability == LocalModelAvailability.planned) {
      return const Align(
        alignment: Alignment.centerRight,
        child: _StatusBadge(label: '即将支持'),
      );
    }
    if (installation.installed) {
      return Row(
        children: [
          const _StatusBadge(label: '已安装', installed: true),
          const Spacer(),
          if (definition.task == LocalModelTask.liveDictation &&
              !selectedForLiveDictation)
            TextButton.icon(
              onPressed: onSelect,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('用于听写'),
            ),
          if (definition.task == LocalModelTask.textGeneration &&
              !selectedForAssistant)
            TextButton.icon(
              onPressed: onSelect,
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('用于助手'),
            ),
          TextButton.icon(
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded, size: 19),
            label: const Text('移除'),
          ),
        ],
      );
    }
    final canContinue =
        installation.partialSizeBytes > 0 ||
        transfer?.status == ModelTransferStatus.canceled ||
        transfer?.status == ModelTransferStatus.failed;
    return Row(
      children: [
        TextButton.icon(
          onPressed: onImport,
          icon: const Icon(Icons.folder_open_rounded, size: 19),
          label: const Text('从文件导入'),
        ),
        const Spacer(),
        FilledButton.icon(
          onPressed: onDownload,
          icon: const Icon(Icons.download_rounded, size: 19),
          label: Text(canContinue ? '继续下载' : '下载'),
        ),
      ],
    );
  }

  String _transferDescription(ModelTransferState state) {
    if (state.status == ModelTransferStatus.canceling) {
      return '正在取消并保留已下载内容…';
    }
    if (state.status == ModelTransferStatus.connecting) {
      final source = state.sourceLabel.isEmpty ? '' : ' · ${state.sourceLabel}';
      return '正在连接下载节点$source';
    }
    if (state.status == ModelTransferStatus.verifying) {
      return '已下载 ${_formatBytes(state.transferredBytes)} · 正在完成安装';
    }
    if (state.status == ModelTransferStatus.waitingToInstall) {
      return '已下载 ${_formatBytes(state.transferredBytes)} · 等待安装';
    }
    final verb = state.status == ModelTransferStatus.importing ? '已导入' : '已下载';
    final speed = state.bytesPerSecond <= 0
        ? '等待首个数据包…'
        : '${_formatBytes(state.bytesPerSecond.round())}/s';
    final source = state.sourceLabel.isEmpty ? '' : ' · ${state.sourceLabel}';
    return '$verb ${_formatBytes(state.transferredBytes)} / '
        '${_formatBytes(state.totalBytes)}$source · $speed';
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final bool installed;
  const _StatusBadge({required this.label, this.installed = false});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: installed ? AppColors.softGreen : AppColors.softBlue,
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(
      label,
      style: TextStyle(
        color: installed ? AppColors.moss : AppColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class _MetaChip extends StatelessWidget {
  final String label;
  const _MetaChip({required this.label});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.canvas,
      borderRadius: BorderRadius.circular(9),
      border: Border.all(color: AppColors.line),
    ),
    child: Text(
      label,
      style: const TextStyle(color: AppColors.muted, fontSize: 11),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow(this.label, this.value);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 58,
          child: Text(label, style: const TextStyle(color: AppColors.muted)),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

String _formatBytes(int bytes) => bytes < 1024
    ? '$bytes B'
    : bytes < 1048576
    ? '${(bytes / 1024).toStringAsFixed(1)} KB'
    : bytes < 1073741824
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1073741824).toStringAsFixed(1)} GB';
