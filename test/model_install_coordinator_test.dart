import 'dart:async';

import 'package:fknotes/services/local_model_manager.dart';
import 'package:fknotes/services/model_install_coordinator.dart';
import 'package:fknotes/services/speech_model_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ModelInstallCoordinator', () {
    test('serializes installs and reports queued work', () async {
      final coordinator = ModelInstallCoordinator.instance;
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      final events = <String>[];
      var secondWaited = false;

      final first = coordinator.run(() async {
        events.add('first-start');
        firstStarted.complete();
        await releaseFirst.future;
        events.add('first-end');
      });
      await firstStarted.future;

      final second = coordinator.run(
        () async => events.add('second-start'),
        onWaiting: () => secondWaited = true,
      );
      await Future<void>.delayed(Duration.zero);

      expect(secondWaited, isTrue);
      expect(events, ['first-start']);

      releaseFirst.complete();
      await Future.wait([first, second]);

      expect(events, ['first-start', 'first-end', 'second-start']);
      expect(coordinator.pendingCount, 0);
    });

    test('canceled queued install does not block following work', () async {
      final coordinator = ModelInstallCoordinator.instance;
      final firstStarted = Completer<void>();
      final releaseFirst = Completer<void>();
      var canceledOperationRan = false;
      var followingOperationRan = false;

      final first = coordinator.run(() async {
        firstStarted.complete();
        await releaseFirst.future;
      });
      await firstStarted.future;

      final canceled = coordinator.run(
        () async => canceledOperationRan = true,
        isCanceled: () => true,
        cancellationError: () => const _Canceled(),
      );
      final following = coordinator.run(() async {
        followingOperationRan = true;
      });

      releaseFirst.complete();
      await first;
      await expectLater(canceled, throwsA(isA<_Canceled>()));
      await following;

      expect(canceledOperationRan, isFalse);
      expect(followingOperationRan, isTrue);
      expect(coordinator.pendingCount, 0);
    });

    test('failed install releases the queue', () async {
      final coordinator = ModelInstallCoordinator.instance;
      var followingOperationRan = false;

      final failed = coordinator.run<void>(
        () async => throw StateError('install failed'),
      );
      final following = coordinator.run(() async {
        followingOperationRan = true;
      });

      await expectLater(failed, throwsStateError);
      await following;

      expect(followingOperationRan, isTrue);
      expect(coordinator.pendingCount, 0);
    });
  });

  test('model transfer exposes the waiting-to-install phase', () {
    final transfer = ModelTransferState(
      modelId: 'test-model',
      status: ModelTransferStatus.downloading,
      transferredBytes: 50,
      totalBytes: 100,
    );

    transfer.updateProgress(
      const SpeechModelImportProgress(100, 100, waitingForInstall: true),
    );

    expect(transfer.status, ModelTransferStatus.waitingToInstall);
    expect(transfer.isRunning, isTrue);
    expect(transfer.progress, 1);
  });
}

class _Canceled implements Exception {
  const _Canceled();
}
