import 'package:fknotes/services/local_inference_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final coordinator = LocalInferenceCoordinator.instance;

  setUp(coordinator.resetForTesting);
  tearDown(coordinator.resetForTesting);

  test('allows exactly one heavy local inference owner', () {
    final lease = coordinator.acquire(
      type: LocalInferenceTaskType.liveDictation,
      ownerId: 'dictation',
    );

    expect(coordinator.activity?.type, LocalInferenceTaskType.liveDictation);
    expect(
      () => coordinator.acquire(
        type: LocalInferenceTaskType.assistant,
        ownerId: 'chat',
      ),
      throwsA(
        isA<LocalInferenceBusyException>().having(
          (error) => error.toString(),
          'message',
          contains('实时听写'),
        ),
      ),
    );

    lease.release();
    expect(coordinator.isBusy, isFalse);
  });

  test('stale or duplicate lease release cannot clear a newer owner', () {
    final first = coordinator.acquire(
      type: LocalInferenceTaskType.transcription,
      ownerId: 'first',
    );
    first.release();
    final second = coordinator.acquire(
      type: LocalInferenceTaskType.readAloud,
      ownerId: 'second',
    );

    first.release();
    expect(coordinator.activity?.ownerId, 'second');

    second.release();
    expect(coordinator.activity, isNull);
  });
}
