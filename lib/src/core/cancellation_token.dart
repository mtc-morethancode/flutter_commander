import 'dart:async';

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
  /// A singleton uncancelled token that never cancels and allocates no listener memory.
  static final CancellationToken none = _NoneCancellationToken();

  bool _isCancelled;
  String? _reason;
  Completer<void>? _whenCancelledCompleter;
  final List<void Function()>? _listeners;

  /// Creates a new, uncancelled [CancellationToken].
  CancellationToken()
      : _isCancelled = false,
        _listeners = <void Function()>[];

  CancellationToken._internal()
      : _isCancelled = false,
        _listeners = null;

  /// Creates a [CancellationToken] that automatically cancels after [duration].
  factory CancellationToken.timeout(
    Duration duration, {
    String? message = 'The operation timed out.',
  }) {
    final token = CancellationToken();
    final timer = Timer(duration, () {
      token.cancel(message);
    });
    token.attach(timer.cancel);
    return token;
  }

  /// Creates a composite [CancellationToken] that cancels whenever any of [tokens] cancels.
  factory CancellationToken.combine(Iterable<CancellationToken> tokens) {
    final combined = CancellationToken();
    final detachList = <void Function()>[];

    for (final token in tokens) {
      if (token.isCancelled) {
        combined.cancel(token.cancellationReason);
        return combined;
      }
      final detach = token.attach(() {
        combined.cancel(token.cancellationReason);
      });
      detachList.add(detach);
    }

    // Detach listeners from parents once the combined token is cancelled
    combined.attach(() {
      for (var i = 0; i < detachList.length; i++) {
        detachList[i]();
      }
    });

    return combined;
  }

  /// Whether cancellation has been requested for this token.
  bool get isCancelled => _isCancelled;

  /// Optional human-readable reason why cancellation was requested, if provided to [cancel].
  String? get cancellationReason => _reason;

  /// A [Future] that completes when cancellation is requested.
  ///
  /// If already cancelled, returns an immediately completed [Future].
  Future<void> get whenCancelled {
    if (_isCancelled) return Future<void>.value();
    _whenCancelledCompleter ??= Completer<void>();
    return _whenCancelledCompleter!.future;
  }

  /// Cancels this token and notifies all registered listeners synchronously.
  /// Subsequent calls to this method have no effect.
  void cancel([String? reason]) {
    if (_isCancelled) return;
    _isCancelled = true;
    _reason = reason;

    if (_whenCancelledCompleter != null &&
        !_whenCancelledCompleter!.isCompleted) {
      _whenCancelledCompleter!.complete();
    }

    if (_listeners == null || _listeners!.isEmpty) return;
    final listenersCopy = List<void Function()>.from(_listeners!);
    _listeners!.clear();
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
      throw _reason != null
          ? CancellationException(_reason!)
          : const CancellationException();
    }
  }

  /// Registers a [callback] to be executed when cancellation is requested.
  ///
  /// If the token is already cancelled, the [callback] executes immediately.
  /// Prefer using [attach] when you need to unregister the callback upon normal completion.
  void onCancelled(void Function() callback) {
    attach(callback);
  }

  /// Registers a cancellation callback and returns a teardown function to unregister
  /// the callback if the operation completes normally.
  ///
  /// If this token is already cancelled, [onCancel] is invoked immediately and the
  /// returned teardown function is a no-op.
  void Function() attach(void Function() onCancel) {
    if (_isCancelled) {
      try {
        onCancel();
      } catch (_) {}
      return () {};
    }
    _listeners?.add(onCancel);
    var detached = false;
    return () {
      if (detached) return;
      detached = true;
      _listeners?.remove(onCancel);
    };
  }

  /// Races [future] against this cancellation token.
  ///
  /// If this token is already cancelled or becomes cancelled while [future] is
  /// in-flight, immediately throws [CancellationException] without waiting for
  /// [future] to complete.
  ///
  /// If [future] completes before cancellation, returns its value or propagates its error.
  Future<T> race<T>(Future<T> future) {
    if (_isCancelled) {
      return Future<T>.error(
        _reason != null
            ? CancellationException(_reason!)
            : const CancellationException(),
      );
    }

    final completer = Completer<T>();
    late final void Function() detach;

    detach = attach(() {
      if (!completer.isCompleted) {
        completer.completeError(
          _reason != null
              ? CancellationException(_reason!)
              : const CancellationException(),
        );
      }
    });

    future.then(
      (value) {
        detach();
        if (!completer.isCompleted) {
          completer.complete(value);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        detach();
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
    );

    return completer.future;
  }

  /// Convenient alias for [race].
  Future<T> withCancellation<T>(Future<T> future) => race<T>(future);

  /// Executes [operation] in a cancellable manner.
  ///
  /// If cancellation has already been requested, [operation] is not called and
  /// this method immediately throws [CancellationException]. If [operation] returns
  /// a [Future], it is automatically raced against this token via [race].
  Future<T> runCancellable<T>(FutureOr<T> Function() operation) {
    throwIfCancelled();
    try {
      final result = operation();
      if (result is Future<T>) {
        return race<T>(result);
      }
      return Future<T>.value(result);
    } catch (e, st) {
      return Future<T>.error(e, st);
    }
  }

  /// Delays execution for [duration] in a cancellable manner.
  ///
  /// If cancellation occurs during the delay, the underlying timer is immediately
  /// cancelled and this method throws a [CancellationException].
  Future<void> sleep(Duration duration) {
    if (_isCancelled) {
      return Future<void>.error(
        _reason != null
            ? CancellationException(_reason!)
            : const CancellationException(),
      );
    }

    final completer = Completer<void>();
    late final Timer timer;
    late final void Function() detach;

    detach = attach(() {
      timer.cancel();
      if (!completer.isCompleted) {
        completer.completeError(
          _reason != null
              ? CancellationException(_reason!)
              : const CancellationException(),
        );
      }
    });

    timer = Timer(duration, () {
      detach();
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    return completer.future;
  }

  /// Subscribes to [stream] and awaits until the stream closes or this token
  /// is cancelled.
  ///
  /// Upon cancellation, the underlying [StreamSubscription] is automatically
  /// cancelled and this method returns cleanly.
  Future<void> forEach<T>(
    Stream<T> stream, {
    required void Function(T data) onData,
    Function? onError,
    bool? cancelOnError,
  }) {
    if (_isCancelled) {
      return Future<void>.value();
    }

    final completer = Completer<void>();
    late final StreamSubscription<T> subscription;
    late final void Function() detach;

    detach = attach(() {
      unawaited(subscription.cancel());
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    subscription = stream.listen(
      (data) {
        if (!_isCancelled) {
          onData(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_isCancelled) {
          if (onError != null) {
            if (onError is void Function(Object, StackTrace)) {
              onError(error, stackTrace);
            } else if (onError is void Function(Object)) {
              onError(error);
            } else {
              onError(error, stackTrace);
            }
          } else {
            detach();
            unawaited(subscription.cancel());
            if (!completer.isCompleted) {
              completer.completeError(error, stackTrace);
            }
          }
        }
      },
      onDone: () {
        detach();
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      cancelOnError: cancelOnError,
    );

    return completer.future;
  }
}

class _NoneCancellationToken extends CancellationToken {
  _NoneCancellationToken() : super._internal();

  @override
  bool get isCancelled => false;

  @override
  String? get cancellationReason => null;

  @override
  Future<void> get whenCancelled => Completer<void>().future;

  @override
  void cancel([String? reason]) {}

  @override
  void throwIfCancelled() {}

  @override
  void onCancelled(void Function() callback) {}

  @override
  void Function() attach(void Function() onCancel) => () {};

  @override
  Future<T> race<T>(Future<T> future) => future;

  @override
  Future<T> withCancellation<T>(Future<T> future) => future;

  @override
  Future<T> runCancellable<T>(FutureOr<T> Function() operation) async =>
      operation();

  @override
  Future<void> sleep(Duration duration) => Future<void>.delayed(duration);

  @override
  Future<void> forEach<T>(
    Stream<T> stream, {
    required void Function(T data) onData,
    Function? onError,
    bool? cancelOnError,
  }) async {
    await for (final item in stream) {
      onData(item);
    }
  }
}
