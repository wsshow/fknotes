import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

import '../models/local_llm.dart';
import '../models/taobao_mnn_model.dart';
import 'file_storage_service.dart';
import 'model_download_source_policy.dart';
import 'model_download_transport.dart';
import 'model_install_coordinator.dart';
import 'speech_model_service.dart';
import 'taobao_mnn_catalog_service.dart';

class LanguageModelInfo {
  final String modelId;
  final bool installed;
  final String? problem;
  final String configPath;
  final int sizeBytes;

  const LanguageModelInfo({
    required this.modelId,
    required this.installed,
    this.problem,
    this.configPath = '',
    this.sizeBytes = 0,
  });
}

class _LanguageModelFile {
  final String name;
  final int sizeBytes;
  final String? sha256;
  final String? gitBlobId;

  const _LanguageModelFile(
    this.name,
    this.sizeBytes,
    this.sha256, {
    this.gitBlobId,
  });
}

class _LanguageModelSpec {
  final String id;
  final String displayName;
  final String storageFolder;
  final String repository;
  final String revision;
  final String license;
  final int nativeContextTokens;
  final int minimumMemoryBytes;
  final LocalLlmCapabilities capabilities;
  final LocalLlmGenerationOptions generationOptions;
  final List<_LanguageModelFile> files;

  const _LanguageModelSpec({
    required this.id,
    required this.displayName,
    required this.storageFolder,
    required this.repository,
    required this.revision,
    this.license = 'Apache-2.0',
    required this.nativeContextTokens,
    required this.minimumMemoryBytes,
    required this.capabilities,
    this.generationOptions = const LocalLlmGenerationOptions(),
    required this.files,
  });

  int get downloadSizeBytes =>
      files.fold(0, (total, file) => total + file.sizeBytes);
}

/// Downloads and transactionally installs MNN language-model directories.
class LanguageModelService {
  LanguageModelService._();
  static final LanguageModelService instance = LanguageModelService._();

  static const miniCpm5Id = 'minicpm5-1b-mnn-int4';
  static const qwen35Id = 'qwen3.5-2b-mnn-int4';
  static const qwen3Vl4BId = 'qwen3-vl-4b-instruct-mnn-int4';
  static const qwen3Vl8BId = 'qwen3-vl-8b-instruct-mnn-int4';
  static const miniCpmV4Id = 'minicpm-v-4-mnn-int4';
  static const gemma4E2BId = 'gemma-4-e2b-it-mnn-int4';
  static const gemma4E4BId = 'gemma-4-e4b-it-mnn-int4';
  static const miniCpm5DownloadSizeBytes = 626439064;
  static const qwen35DownloadSizeBytes = 1386690287;
  static const qwen3Vl4BDownloadSizeBytes = 2958466071;
  static const qwen3Vl8BDownloadSizeBytes = 5453816751;
  static const miniCpmV4DownloadSizeBytes = 2834666144;
  static const gemma4E2BDownloadSizeBytes = 3739995144;
  static const gemma4E4BDownloadSizeBytes = 5542169905;
  static const supportedModelIds = [
    miniCpm5Id,
    qwen35Id,
    qwen3Vl4BId,
    qwen3Vl8BId,
    miniCpmV4Id,
    gemma4E2BId,
    gemma4E4BId,
  ];
  static const _manifestFileName = 'manifest.json';

  static const _specs = <_LanguageModelSpec>[
    _LanguageModelSpec(
      id: miniCpm5Id,
      displayName: 'MiniCPM5 1B INT4',
      storageFolder: 'minicpm5-1b-mnn-int4',
      repository: 'taobao-mnn/MiniCPM5-1B-MNN',
      revision: '7621114a378eace477bd3a83f96b5b4c38aaca37',
      nativeContextTokens: 131072,
      minimumMemoryBytes: 4 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(thinking: true, toolCalling: true),
      files: [
        _LanguageModelFile(
          'config.json',
          317,
          '236b584538be72c493daca7ab3abe24de5d3deedfedd47e87c44d5c24c5d846f',
        ),
        _LanguageModelFile(
          'embeddings_int4.bin',
          125337600,
          '71fe454d4901121805d99dd5f888c0b169f03263a6930dfb5c14b6866f41d81a',
        ),
        _LanguageModelFile(
          'llm.mnn',
          419768,
          '5d4ed23b414eeef767a3bfbd80b943a253a003ca9ee3b68cad78bc6b325cf4df',
        ),
        _LanguageModelFile(
          'llm.mnn.json',
          848443,
          '9eaee78129337385579a2f4718e46043757101f2dc384f8373ce9d6abae5e966',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          495615626,
          'd87789339065661c6435b43e61fdf133929d46c768f0c67c5c9eeed44913aada',
        ),
        _LanguageModelFile(
          'llm_config.json',
          9824,
          '8043421e920ca16f638f930f04b17f52b61e9df36be0f8d404901ae6407c51b6',
        ),
        _LanguageModelFile(
          'tokenizer.mtok',
          3536385,
          '1d5777b5f38f3b72c7e2a54aa7eeca92b782a669050211e00ca84136e8cc2ef2',
        ),
        _LanguageModelFile(
          'tokenizer.txt',
          671101,
          '184864dbdd4a5ea71ef72c5e6cc414e743ae6a373e3876e1e41e387fae047e60',
        ),
      ],
    ),
    _LanguageModelSpec(
      id: qwen35Id,
      displayName: 'Qwen3.5 2B INT4',
      storageFolder: 'qwen3.5-2b-mnn-int4',
      repository: 'taobao-mnn/Qwen3.5-2B-MNN',
      revision: '35781816d7b6a9dcb273a6765ac9563401951c3c',
      nativeContextTokens: 262144,
      minimumMemoryBytes: 6 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(
        thinking: true,
        toolCalling: true,
        imageInput: true,
      ),
      generationOptions: LocalLlmGenerationOptions(
        temperature: 1,
        topP: 0.95,
        topK: 20,
      ),
      files: [
        _LanguageModelFile(
          'config.json',
          652,
          '92853033efe602f95efca3e1c05cd8b108f973c8beed417843a9671f8147ed8d',
        ),
        _LanguageModelFile(
          'llm.mnn',
          2148136,
          '23df98f8b341b277365e0bbca025c1d192939e3d32d7f79776352c6f32e77960',
        ),
        _LanguageModelFile(
          'llm.mnn.json',
          5344018,
          '7131ff4f1a441add1039d371815ad94652ae6801f579591cb2f9ad90b5954025',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          1176647702,
          'c93f71a2dbecf9328782bd38861656d8faa82e95e7f99607350074768a482054',
        ),
        _LanguageModelFile(
          'llm_config.json',
          8692,
          'a88234b36c2af0eff8e5c89667011badf71c15e30459eb0e21030a8f3f9ed240',
        ),
        _LanguageModelFile(
          'tokenizer.txt',
          6465727,
          '7e75de1f279a10b65bd9dc1a5207205cb8993823861c4c42bbbd74e48e1c23a4',
        ),
        _LanguageModelFile(
          'visual.mnn',
          488096,
          '88fc40a7b676e90eb2cb86d854db15cb90b9eb1f34087ab0f48c5e43572c8dac',
        ),
        _LanguageModelFile(
          'visual.mnn.weight',
          195587264,
          '8f90e106f5b9ae9a939faed240305cfdd5c6740ae91d3fc418a990bee0cce36b',
        ),
      ],
    ),
    _LanguageModelSpec(
      id: qwen3Vl4BId,
      displayName: 'Qwen3-VL 4B Instruct INT4',
      storageFolder: 'qwen3-vl-4b-instruct-mnn-int4',
      repository: 'taobao-mnn/Qwen3-VL-4B-Instruct-MNN',
      revision: '5c00738180f120067d51306ecf365015cdbbabcf',
      nativeContextTokens: 262144,
      minimumMemoryBytes: 8 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(toolCalling: true, imageInput: true),
      generationOptions: LocalLlmGenerationOptions(
        temperature: 0.7,
        topP: 0.8,
        topK: 20,
      ),
      files: [
        _LanguageModelFile(
          'config.json',
          605,
          '1ed5c6e65459fdc4b0c33319715b763005013ba8580dd3c687bd2651546ca2a4',
        ),
        _LanguageModelFile(
          'llm.mnn',
          591728,
          '1214d79288201d4bd2226cb435ed85d83aea4a35b2a59634ca9116f78143e382',
        ),
        _LanguageModelFile(
          'llm.mnn.json',
          1245003,
          '8fa8b23545be87bfca5d11d3180c2ba9cf1def961738c7edbbe8876ff03e21ec',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          2709972658,
          '387576d52e7a297e3e6de837c60c25e364cd62c6244f878633097064bea0a245',
        ),
        _LanguageModelFile(
          'llm_config.json',
          6446,
          '907a48df99ba73e78a01ba55e05bb58567f78eb75f9233aa8f58bfbbabe8cf45',
        ),
        _LanguageModelFile(
          'tokenizer.txt',
          3193555,
          '7119de4966cc6a8ae87d7f083e65b315282d06c3122fdd41ce783fdd2d3c1ca2',
        ),
        _LanguageModelFile(
          'visual.mnn',
          502512,
          'fb7e1923db713c6607fd2fb9eae5fd7488aff9f454b8067ab558370f84010b2b',
        ),
        _LanguageModelFile(
          'visual.mnn.weight',
          242953564,
          'b48c901ffe64d1615da93992f3c0508ecf51856b016c424cd96de27114e85694',
        ),
      ],
    ),
    _LanguageModelSpec(
      id: qwen3Vl8BId,
      displayName: 'Qwen3-VL 8B Instruct INT4',
      storageFolder: 'qwen3-vl-8b-instruct-mnn-int4',
      repository: 'taobao-mnn/Qwen3-VL-8B-Instruct-MNN',
      revision: '890e672be412e84d34bc318925aa4b7b61ad24c7',
      nativeContextTokens: 262144,
      minimumMemoryBytes: 12 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(toolCalling: true, imageInput: true),
      generationOptions: LocalLlmGenerationOptions(
        temperature: 0.7,
        topP: 0.8,
        topK: 20,
      ),
      files: [
        _LanguageModelFile(
          'config.json',
          605,
          '1ed5c6e65459fdc4b0c33319715b763005013ba8580dd3c687bd2651546ca2a4',
        ),
        _LanguageModelFile(
          'embeddings_int4.bin',
          388956160,
          '311cd44e48dcec950bcc5cffb465ae0e2fec8154247f2ff545b7fd1240960bf4',
        ),
        _LanguageModelFile(
          'llm.mnn',
          591728,
          '61f0fe3b5d0447518ae5b26ab19c0b8a7f07c51f598be5f52fa0aee7405972e3',
        ),
        _LanguageModelFile(
          'llm.mnn.json',
          1245313,
          '785b31ac0e0b4def1a9e707cd0876fc1e072f957db61d56868c89e0f8219aa2a',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          4732532162,
          'a52971cb29c0bef35ab336b370db00d676223e6d721b99e3bf0b9c70f2d9bcfe',
        ),
        _LanguageModelFile(
          'llm_config.json',
          6436,
          'ce8f3a6532832d37eff85cf45ddb24b4d21567d293cfc8c64a67fa0fdca93df9',
        ),
        _LanguageModelFile(
          'tokenizer.txt',
          3193555,
          '7119de4966cc6a8ae87d7f083e65b315282d06c3122fdd41ce783fdd2d3c1ca2',
        ),
        _LanguageModelFile(
          'visual.mnn',
          562048,
          '8f1653348a94c29e56d47529dd461215c80d5380263136adee7945809f407bf7',
        ),
        _LanguageModelFile(
          'visual.mnn.weight',
          326728744,
          '6d8b1a4886cca9ab8b8c86979f4e5291e126ac930124e9a2361833e7b11301e6',
        ),
      ],
    ),
    _LanguageModelSpec(
      id: miniCpmV4Id,
      displayName: 'MiniCPM-V 4 INT4',
      storageFolder: 'minicpm-v-4-mnn-int4',
      repository: 'taobao-mnn/MiniCPM-V-4-MNN',
      revision: 'b0ec85ec6f4d1f85df144087bbcfc66a221a3b33',
      nativeContextTokens: 32768,
      minimumMemoryBytes: 8 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(imageInput: true),
      files: [
        _LanguageModelFile(
          'config.json',
          342,
          '40d2d5bf0393cc347ff48cf29246ca9efff9a44a29c2c1ea4acac3135fff87fe',
        ),
        _LanguageModelFile(
          'embeddings_bf16.bin',
          376053760,
          '2cf70b1293338944249e84c36b2c8612d580e8bcc2d34a44c876da304785aa00',
        ),
        _LanguageModelFile(
          'llm.mnn',
          554144,
          'c2517765e628b57f30eda4c8648172921a7b6a0c949e8d4899bd324200d09567',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          2137361754,
          '3d17c4db06d1ed9d35a01843cd50e2ea3fee08b4701018be4872eae0c1bc38e1',
        ),
        _LanguageModelFile(
          'llm_config.json',
          1076,
          '2d6a1e1e96a2ba42ec8d68b74a2f080e0dada266c194ce3d6214514804a5e0f4',
        ),
        _LanguageModelFile(
          'tokenizer.txt',
          1485414,
          '404838daab75cfc8883ca4e1f79a4ef87c98fcbbffaa188f6cf6da8cea9e28e4',
        ),
        _LanguageModelFile(
          'visual.mnn',
          546800,
          '3912a0b7e256807d722273e823a95c6e38430d26f24b176cabfa9a8da7237819',
        ),
        _LanguageModelFile(
          'visual.mnn.weight',
          318662854,
          'fb73e88834fb7234f4b9927a68996341690c78a56597fde1740444f6c2d65d9d',
        ),
      ],
    ),
    _LanguageModelSpec(
      id: gemma4E2BId,
      displayName: 'Gemma 4 E2B IT INT4',
      storageFolder: 'gemma-4-e2b-it-mnn-int4',
      repository: 'taobao-mnn/gemma-4-E2B-it-MNN',
      revision: 'ce18884f154ce405545f1acda5c5c8fdd9c1280c',
      nativeContextTokens: 131072,
      minimumMemoryBytes: 8 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(
        thinking: true,
        toolCalling: true,
        imageInput: true,
        audioInput: true,
      ),
      generationOptions: LocalLlmGenerationOptions(
        temperature: 1,
        topP: 0.95,
        topK: 64,
      ),
      files: [
        _LanguageModelFile(
          'audio.mnn',
          1428288,
          '8826caef00f13c74be59b69b06c76b1acc7576d0359537abc37386e11124dd51',
        ),
        _LanguageModelFile(
          'audio.mnn.weight',
          589877376,
          '16d1191104bf049df50b7d11747ebd6e842fec0fb22c6004f1e85c57804a2015',
        ),
        _LanguageModelFile(
          'config.json',
          678,
          '3b1c8caafa2792a64b81d2ef47d3e6afc1c250b280389e77d0d25628108c87a7',
        ),
        _LanguageModelFile(
          'llm.mnn',
          2276992,
          '7115ecd7a66332d8a14c9d6467d560baec33c9650174cbb2f0e7641a69999216',
        ),
        _LanguageModelFile(
          'llm.mnn.json',
          4895844,
          'b2befd57549d0694aafed3dbfc720d2ee67c94b5fa38ce54827b62b0f3654f9d',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          1436474178,
          '8d4b0fabb015da09a820fab22714f392b9e73f8f2fc7175dea7ef4f581d03881',
        ),
        _LanguageModelFile(
          'llm_config.json',
          1415,
          '7096f286d274bee7f374b7d06533d5a611f6d678b119fa9542e74e65fd8a5379',
        ),
        _LanguageModelFile(
          'ple_embeddings_int4.bin',
          1468006400,
          'c76e660ca418790bde8757099af0144488ece631dcd612245f1e1bf801f9e1e3',
        ),
        _LanguageModelFile(
          'tokenizer.mtok',
          10068633,
          'e08a1293e250750949bb1f543edd626cc6cf9f039a2e461958d20f33407d26b9',
        ),
        _LanguageModelFile(
          'visual.mnn',
          1060528,
          '759a3fa521cbb9e4bcf877769524faa41f0e1288a61d664cb9656f3e70f61fb0',
        ),
        _LanguageModelFile(
          'visual.mnn.weight',
          225904812,
          '308e356f5a8527c28c1caba233b8d3521d4ba558b56cbcb8a53ed103d73ae1af',
        ),
      ],
    ),
    _LanguageModelSpec(
      id: gemma4E4BId,
      displayName: 'Gemma 4 E4B IT INT4',
      storageFolder: 'gemma-4-e4b-it-mnn-int4',
      repository: 'taobao-mnn/gemma-4-E4B-it-MNN',
      revision: 'fec885bae19e9363cebd36de22527b340bc6b450',
      nativeContextTokens: 131072,
      minimumMemoryBytes: 12 * 1024 * 1024 * 1024,
      capabilities: LocalLlmCapabilities(
        thinking: true,
        toolCalling: true,
        imageInput: true,
        audioInput: true,
      ),
      generationOptions: LocalLlmGenerationOptions(
        temperature: 1,
        topP: 0.95,
        topK: 64,
      ),
      files: [
        _LanguageModelFile(
          'audio.mnn',
          1428400,
          'ba4a5ccf5b78c237f511bb91d4c3d5d020c362169d83ce4fb9c64111cce2c379',
        ),
        _LanguageModelFile(
          'audio.mnn.weight',
          593027200,
          '9a74d2940e890944b748a18ded43c61d183a5e4bc3ecc4f0aa3fd98abe217c32',
        ),
        _LanguageModelFile(
          'config.json',
          678,
          '3b1c8caafa2792a64b81d2ef47d3e6afc1c250b280389e77d0d25628108c87a7',
        ),
        _LanguageModelFile(
          'llm.mnn',
          3585584,
          'b55bad1efd4e66217e7ff75b896535fc01a0d07fcc78cc7a3d6b562fd71e8836',
        ),
        _LanguageModelFile(
          'llm.mnn.json',
          7804930,
          '3222ce9243e3f67251bb3aee8bbbfdb5f5cef38933c66f059d1e19121b2a8e70',
        ),
        _LanguageModelFile(
          'llm.mnn.weight',
          2936840364,
          '1232792a67e05d31525e5d3d8e30d827c55803f5dab9923aab2bbfd7fb9207e7',
        ),
        _LanguageModelFile(
          'llm_config.json',
          1416,
          'c03fc5ccbdab67b7021f56ff255223f7c4308d2fa3a46059573ce309d8757594',
        ),
        _LanguageModelFile(
          'ple_embeddings_int4.bin',
          1761607680,
          '0d91ddc26d4e6a0d7657ead0385781a30da62d5c5457e0498fbe324a979c33af',
        ),
        _LanguageModelFile(
          'tokenizer.mtok',
          10068633,
          'e08a1293e250750949bb1f543edd626cc6cf9f039a2e461958d20f33407d26b9',
        ),
        _LanguageModelFile(
          'visual.mnn',
          1060528,
          '6003978cd06e99eef6679c423f511a280479d858237cd18207019572d45f1327',
        ),
        _LanguageModelFile(
          'visual.mnn.weight',
          226744492,
          '77b5258977b829e8bb3058447c448e396e48442c66fa0d7034013a6735957769',
        ),
      ],
    ),
  ];

  final _storage = FileStorageService.instance;
  final Set<String> _busyModelIds = {};
  final Map<String, _LanguageModelSpec> _dynamicSpecs = {};
  bool _remoteCacheLoaded = false;

  List<String> get modelIds => [
    ...supportedModelIds,
    ..._dynamicSpecs.keys.where((id) => !supportedModelIds.contains(id)),
  ];
  Set<String> get curatedRepositories =>
      _specs.map((spec) => spec.repository.toLowerCase()).toSet();
  bool supports(String id) =>
      supportedModelIds.contains(id) || _dynamicSpecs.containsKey(id);

  void registerRemoteModels(Iterable<TaobaoMnnModelSpec> models) {
    for (final model in models) {
      if (curatedRepositories.contains(model.repository.toLowerCase())) {
        continue;
      }
      final folderHash = sha1
          .convert(utf8.encode(model.repository.toLowerCase()))
          .toString()
          .substring(0, 10);
      final safeName = model.name
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      _dynamicSpecs[model.id] = _LanguageModelSpec(
        id: model.id,
        displayName: model.name,
        storageFolder: 'remote-$safeName-$folderHash',
        repository: model.repository,
        revision: model.revision,
        license: model.license,
        nativeContextTokens: model.nativeContextTokens,
        minimumMemoryBytes: model.recommendedMemoryBytes,
        capabilities: model.capabilities,
        generationOptions: model.generationOptions,
        files: [
          for (final file in model.files)
            _LanguageModelFile(
              file.name,
              file.sizeBytes,
              file.sha256,
              gitBlobId: file.gitBlobId,
            ),
        ],
      );
    }
  }

  _LanguageModelSpec _spec(String id) =>
      _dynamicSpecs[id] ?? _specs.firstWhere((spec) => spec.id == id);

  String _root(_LanguageModelSpec spec) =>
      p.join(_storage.baseDir, 'models', 'llm', spec.storageFolder);
  String _activeDir(_LanguageModelSpec spec) => p.join(_root(spec), 'active');
  String _downloadDir(_LanguageModelSpec spec) =>
      p.join(_root(spec), '.download');
  String _partialPath(_LanguageModelSpec spec, _LanguageModelFile file) =>
      p.join(_downloadDir(spec), '${file.name}.part');
  String get _selectionPath =>
      p.join(_storage.baseDir, 'models', 'llm', 'selection.json');

  int downloadSizeBytes(String id) => _spec(id).downloadSizeBytes;
  String displayName(String id) => _spec(id).displayName;
  LocalLlmCapabilities capabilities(String id) => _spec(id).capabilities;

  Future<String> selectedModelId() async {
    await _ensureRemoteModelsLoaded();
    final file = File(_selectionPath);
    if (!await file.exists()) return qwen35Id;
    try {
      final json = jsonDecode(await file.readAsString());
      final id = json is Map ? json['modelId'] : null;
      return id is String && supports(id) ? id : qwen35Id;
    } on FormatException {
      return qwen35Id;
    } on FileSystemException {
      return qwen35Id;
    }
  }

  Future<void> _ensureRemoteModelsLoaded() async {
    if (_remoteCacheLoaded) return;
    final catalog = TaobaoMnnCatalogService.instance;
    await catalog.loadCache();
    registerRemoteModels(catalog.cachedDetails);
    _remoteCacheLoaded = true;
  }

  Future<void> selectModel(String id) async {
    final info = await inspect(id);
    if (!info.installed) throw StateError('${displayName(id)}尚未安装');
    final destination = File(_selectionPath);
    await destination.parent.create(recursive: true);
    final temporary = File('${destination.path}.tmp');
    await temporary.writeAsString(jsonEncode({'modelId': id}), flush: true);
    await _replaceFile(temporary, destination);
  }

  Future<LanguageModelInfo> inspect(
    String id, {
    bool verifyIntegrity = false,
  }) async {
    final spec = _spec(id);
    LanguageModelInfo unavailable(String problem) =>
        LanguageModelInfo(modelId: id, installed: false, problem: problem);
    final active = Directory(_activeDir(spec));
    final manifest = File(p.join(active.path, _manifestFileName));
    if (!await manifest.exists()) return unavailable('语言模型尚未安装');
    try {
      final json = jsonDecode(await manifest.readAsString());
      if (json is! Map ||
          json['id'] != spec.id ||
          json['revision'] != spec.revision ||
          json['engine'] != 'mnn') {
        return unavailable('语言模型版本不匹配，请重新下载');
      }
    } on FormatException {
      return unavailable('语言模型清单损坏，请重新下载');
    } on FileSystemException {
      return unavailable('无法读取语言模型');
    }
    var size = await manifest.length();
    for (final definition in spec.files) {
      final file = File(p.join(active.path, definition.name));
      if (!await file.exists() || await file.length() != definition.sizeBytes) {
        return unavailable('${definition.name} 缺失或大小异常');
      }
      if (verifyIntegrity && !await _matchesDefinition(file, definition)) {
        return unavailable('${definition.name} 完整性校验失败');
      }
      size += definition.sizeBytes;
    }
    final license = File(p.join(active.path, 'LICENSE.txt'));
    if (await license.exists()) size += await license.length();
    return LanguageModelInfo(
      modelId: id,
      installed: true,
      configPath: p.join(active.path, 'config.json'),
      sizeBytes: size,
    );
  }

  Future<LocalLlmModelDescriptor> descriptor(String id) async {
    final spec = _spec(id);
    final info = await inspect(id);
    if (!info.installed) {
      throw StateError(info.problem ?? '${spec.displayName}尚未安装');
    }
    return LocalLlmModelDescriptor(
      id: spec.id,
      name: spec.displayName,
      configPath: info.configPath,
      nativeContextTokens: spec.nativeContextTokens,
      recommendedContextTokens: 4096,
      minimumMemoryBytes: spec.minimumMemoryBytes,
      capabilities: spec.capabilities,
      generationOptions: spec.generationOptions,
    );
  }

  Future<int> partialDownloadBytes(String id) async {
    final spec = _spec(id);
    var total = 0;
    for (final definition in spec.files) {
      final partial = File(_partialPath(spec, definition));
      if (await partial.exists()) {
        total += (await partial.length()).clamp(0, definition.sizeBytes);
      }
    }
    return total;
  }

  Future<LanguageModelInfo> download(
    String id, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => _runExclusive(id, () async {
    final spec = _spec(id);
    await Directory(_downloadDir(spec)).create(recursive: true);
    final currentBytes = <String, int>{};
    for (final definition in spec.files) {
      final partial = File(_partialPath(spec, definition));
      final length = await partial.exists() ? await partial.length() : 0;
      currentBytes[definition.name] = length.clamp(0, definition.sizeBytes);
    }

    void report(String name, ModelDownloadEvent event) {
      currentBytes[name] = event.transferredBytes;
      onProgress?.call(
        SpeechModelImportProgress(
          currentBytes.values.fold(0, (sum, bytes) => sum + bytes),
          spec.downloadSizeBytes,
          connecting: event.connecting,
          sourceLabel: event.sourceLabel,
        ),
      );
    }

    for (final definition in spec.files) {
      final path = '${spec.revision}/${definition.name}?download=true';
      final sourcePolicy = ModelDownloadSourcePolicy.instance;
      await ModelDownloadTransport.instance.download(
        sources: sourcePolicy.order([
          ModelDownloadSource(
            uri: Uri.parse(
              'https://huggingface.co/${spec.repository}/resolve/$path',
            ),
            label: 'Hugging Face',
            kind: ModelDownloadSourceKind.official,
          ),
          ModelDownloadSource(
            uri: Uri.parse(
              'https://hf-mirror.com/${spec.repository}/resolve/$path',
            ),
            label: '第三方国内镜像',
            kind: ModelDownloadSourceKind.mainlandMirror,
          ),
        ]),
        partial: File(_partialPath(spec, definition)),
        expectedBytes: definition.sizeBytes,
        userAgent: 'fknotes/${spec.id}',
        onProgress: (event) => report(definition.name, event),
        shouldCancel: shouldCancel,
        onSourceSelected: sourcePolicy.reportSuccessfulSource,
      );
    }
    if (shouldCancel?.call() == true) throw const ModelDownloadCanceled();
    return _install(
      spec,
      {
        for (final definition in spec.files)
          definition.name: File(_partialPath(spec, definition)),
      },
      onProgress: onProgress,
      shouldCancel: shouldCancel,
    );
  });

  Future<LanguageModelInfo?> pickAndImport(
    String id, {
    void Function(SpeechModelImportProgress progress)? onProgress,
  }) async {
    final spec = _spec(id);
    const group = XTypeGroup(
      label: 'MNN 语言模型文件',
      extensions: ['json', 'mnn', 'weight', 'bin', 'mtok', 'txt'],
    );
    final selected = await openFiles(acceptedTypeGroups: [group]);
    if (selected.isEmpty) return null;
    return _runExclusive(id, () async {
      final byName = {for (final file in selected) file.name: file};
      for (final definition in spec.files) {
        if (!byName.containsKey(definition.name)) {
          throw FormatException('缺少 ${definition.name}');
        }
      }
      final importing = Directory(p.join(_root(spec), '.importing'));
      if (await importing.exists()) await importing.delete(recursive: true);
      await importing.create(recursive: true);
      var copied = 0;
      try {
        final sources = <String, File>{};
        for (final definition in spec.files) {
          final source = byName[definition.name]!;
          if (await source.length() != definition.sizeBytes) {
            throw FormatException('${definition.name} 大小不匹配');
          }
          final destination = File(p.join(importing.path, definition.name));
          final output = await destination.open(mode: FileMode.write);
          try {
            await for (final chunk in source.openRead()) {
              await output.writeFrom(chunk);
              copied += chunk.length;
              onProgress?.call(
                SpeechModelImportProgress(copied, spec.downloadSizeBytes),
              );
            }
            await output.flush();
          } finally {
            await output.close();
          }
          sources[definition.name] = destination;
        }
        return await _install(spec, sources, onProgress: onProgress);
      } finally {
        if (await importing.exists()) await importing.delete(recursive: true);
      }
    });
  }

  Future<LanguageModelInfo> _install(
    _LanguageModelSpec spec,
    Map<String, File> sources, {
    void Function(SpeechModelImportProgress progress)? onProgress,
    bool Function()? shouldCancel,
  }) => ModelInstallCoordinator.instance.run(
    () async {
      onProgress?.call(
        SpeechModelImportProgress(
          spec.downloadSizeBytes,
          spec.downloadSizeBytes,
          verifying: true,
        ),
      );
      for (final definition in spec.files) {
        final source = sources[definition.name];
        if (source == null || !await _matchesDefinition(source, definition)) {
          if (source != null && await source.exists()) await source.delete();
          throw FormatException('${definition.name} 文件不完整，请重新下载');
        }
      }
      final staging = Directory(p.join(_root(spec), '.installing'));
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      try {
        for (final definition in spec.files) {
          final source = sources[definition.name]!;
          final destination = File(p.join(staging.path, definition.name));
          try {
            await source.rename(destination.path);
          } on FileSystemException {
            await source.copy(destination.path);
            await source.delete();
          }
        }
        await File(p.join(staging.path, 'LICENSE.txt')).writeAsString(
          'Model license: ${spec.license.isEmpty ? 'Not specified' : spec.license}\n'
          'Upstream: https://huggingface.co/${spec.repository}\n',
          flush: true,
        );
        await File(p.join(staging.path, _manifestFileName)).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'id': spec.id,
            'name': spec.displayName,
            'engine': 'mnn',
            'repository': spec.repository,
            'revision': spec.revision,
            'license': spec.license,
          }),
          flush: true,
        );
        await _activate(spec, staging);
        final download = Directory(_downloadDir(spec));
        if (await download.exists()) await download.delete(recursive: true);
        return inspect(spec.id);
      } finally {
        if (await staging.exists()) await staging.delete(recursive: true);
      }
    },
    onWaiting: () => onProgress?.call(
      SpeechModelImportProgress(
        spec.downloadSizeBytes,
        spec.downloadSizeBytes,
        waitingForInstall: true,
      ),
    ),
    isCanceled: shouldCancel,
    cancellationError: () => const ModelDownloadCanceled(),
  );

  Future<void> _activate(_LanguageModelSpec spec, Directory staging) async {
    final active = Directory(_activeDir(spec));
    final previous = Directory('${active.path}.previous');
    if (await previous.exists()) await previous.delete(recursive: true);
    if (await active.exists()) await active.rename(previous.path);
    try {
      await staging.rename(active.path);
      if (await previous.exists()) await previous.delete(recursive: true);
    } catch (_) {
      if (await active.exists()) await active.delete(recursive: true);
      if (await previous.exists()) await previous.rename(active.path);
      rethrow;
    }
  }

  Future<void> remove(String id) async {
    if (_busyModelIds.contains(id)) throw StateError('语言模型正在下载或导入');
    final root = Directory(_root(_spec(id)));
    if (await root.exists()) await root.delete(recursive: true);
    if (await selectedModelId() == id) {
      final selection = File(_selectionPath);
      if (await selection.exists()) await selection.delete();
    }
  }

  Future<bool> _matchesDefinition(
    File file,
    _LanguageModelFile definition,
  ) async {
    if (!await file.exists() || await file.length() != definition.sizeBytes) {
      return false;
    }
    final expectedSha256 = definition.sha256;
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final digest = await sha256.bind(file.openRead()).first;
      return digest.toString() == expectedSha256;
    }
    final expectedBlob = definition.gitBlobId;
    if (expectedBlob == null || expectedBlob.isEmpty) return false;
    final output = _DigestSink();
    final sink = sha1.startChunkedConversion(output);
    sink.add(utf8.encode('blob ${definition.sizeBytes}\u0000'));
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    return output.value?.toString() == expectedBlob;
  }

  Future<T> _runExclusive<T>(String id, Future<T> Function() operation) async {
    if (!_busyModelIds.add(id)) throw StateError('该语言模型已有任务正在进行');
    try {
      return await operation();
    } finally {
      _busyModelIds.remove(id);
    }
  }

  Future<void> _replaceFile(File source, File destination) async {
    try {
      await source.rename(destination.path);
    } on FileSystemException {
      if (await destination.exists()) await destination.delete();
      await source.rename(destination.path);
    }
  }
}

class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
