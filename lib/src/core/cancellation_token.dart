/// Exception thrown when a collaborative operation checks [CancellationToken.throwIfCancelled]
/// after the token has been cancelled.
class CancellationException implements Exception {
  /// Optional human-readable message describing the cancellation context.
  final String message;

  /// Creates a [CancellationException] with an optional descriptive [message].
  const CancellationException([this.message = 'The operation was cancelled.']);

  @override
  String toString() => 'CancellationException: $message';
}

/// Collaborative token used to signal cancellation across asynchronous tasks.
///
/// Designed to support cooperative cancellation patterns in commands, such as
/// when using [ExecutionPolicy.restart] or manual task abortion.
class CancellationToken {
  bool _isCancelled = false;
  final List<void Function()> _listeners = [];

  /// Whether cancellation has been requested for this token.
  bool get isCancelled => _isCancelled;

  /// Cancels this token and notifies all registered listeners synchronously.
  /// Subsequent calls to this method have no effect.
  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    final listenersCopy = List<void Function()>.from(_listeners);
    _listeners.clear();
    for (final listener in listenersCopy) {
      try {
        listener();
      } catch (_) {
        // Suppress listener errors during cancellation to avoid breaking teardown.
      }
    }
  }

  /// Throws a [CancellationException] if cancellation has been requested.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw const CancellationException();
    }
  }

  /// Registers a [callback] to be executed when cancellation is requested.
  /// If the token is already cancelled, the [callback] executes immediately.
  void onCancelled(void Function() callback) {
    if (_isCancelled) {
      callback();
    } else {
      _listeners.add(callback);
    }
  }
}
