import 'dart:async';

/// Serializes model verification, extraction and activation across model types.
///
/// Network transfers remain fully independent. Only the storage- and
/// memory-intensive installation phase enters this queue.
class ModelInstallCoordinator {
  ModelInstallCoordinator._();
  static final ModelInstallCoordinator instance = ModelInstallCoordinator._();

  Future<void> _tail = Future<void>.value();
  int _pending = 0;

  int get pendingCount => _pending;

  Future<T> run<T>(
    Future<T> Function() operation, {
    void Function()? onWaiting,
    bool Function()? isCanceled,
    Object Function()? cancellationError,
  }) {
    final previous = _tail;
    final release = Completer<void>();
    final result = Completer<T>();
    final waitsForAnotherInstall = _pending > 0;
    _pending++;
    _tail = release.future;

    unawaited(() async {
      try {
        if (waitsForAnotherInstall) onWaiting?.call();
        await previous;
        if (isCanceled?.call() == true) {
          throw cancellationError?.call() ??
              StateError('Model installation was canceled');
        }
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      } finally {
        _pending--;
        release.complete();
      }
    }());
    return result.future;
  }
}
