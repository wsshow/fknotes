import 'package:fknotes/services/background_task_center.dart';
import 'package:fknotes/services/local_inference_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final inference = LocalInferenceCoordinator.instance;
  final center = BackgroundTaskCenter.instance;

  setUp(inference.resetForTesting);
  tearDown(inference.resetForTesting);

  test('reports active clean-slate inference ownership', () {
    final lease = inference.acquire(
      type: LocalInferenceTaskType.liveDictation,
      ownerId: 'dictation-task',
    );

    expect(center.activeCount, 1);
    expect(center.failedCount, 0);
    expect(center.items.single.kind, BackgroundTaskKind.inference);
    expect(center.items.single.title, '实时听写');

    lease.release();
    expect(center.items, isEmpty);
  });
}
