import 'package:fknotes/models/local_llm.dart';
import 'package:fknotes/services/local_assistant_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prefers mobile GPU backends and keeps a CPU fallback elsewhere', () {
    expect(
      LocalAssistantBackendPolicy.preferredFor(
        LocalLlmEngineKind.liteRtLm,
        isAndroid: true,
        isIOS: false,
      ),
      LocalLlmBackend.openCl,
    );
    expect(
      LocalAssistantBackendPolicy.preferredFor(
        LocalLlmEngineKind.mnn,
        isAndroid: true,
        isIOS: false,
      ),
      LocalLlmBackend.openCl,
    );
    expect(
      LocalAssistantBackendPolicy.preferredFor(
        LocalLlmEngineKind.mnn,
        isAndroid: false,
        isIOS: true,
      ),
      LocalLlmBackend.metal,
    );
    expect(
      LocalAssistantBackendPolicy.preferredFor(
        LocalLlmEngineKind.mnn,
        isAndroid: false,
        isIOS: false,
      ),
      LocalLlmBackend.cpu,
    );
  });
}
