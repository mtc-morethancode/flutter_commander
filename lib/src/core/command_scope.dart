import 'dart:async';

import 'cancellation_token.dart';

/// Context provided to a [Command] during its execution lifecycle.
///
/// Gives access to the current state, synchronous state updates via pure reducers,
/// one-shot side-effect emissions, and collaborative cancellation helpers.
abstract interface class CommandScope<S, E> {
  /// The current state of the commander.
  S get state;

  /// Updates the state synchronously using a pure [reducer] function.
  ///
  /// Example:
  /// ```dart
  /// scope.updateState((current) => current.copyWith(isLoading: true));
  /// ```
  void updateState(S Function(S current) reducer);

  /// Emits a one-shot side effect (navigation, snackbars, dialogs, etc.).
  ///
  /// Effects are dispatched through an event stream to prevent polluting
  /// the persistent presentation state.
  void emitSideEffect(E effect);

  /// Collaborative cancellation token for this execution instance.
  CancellationToken get cancellationToken;

  /// Convenience getter checking if cancellation has been requested.
  bool get isCancelled => cancellationToken.isCancelled;

  /// Throws a [CancellationException] if cancellation has been requested for this command.
  void throwIfCancelled();

  /// Races [future] against this command's cancellation token.
  ///
  /// If this command is cancelled (e.g., restarted or commander disposed) while
  /// [future] is running, this method immediately throws [CancellationException]
  /// without waiting for [future] to complete.
  Future<T> race<T>(Future<T> future);

  /// Convenient alias for [race].
  Future<T> withCancellation<T>(Future<T> future);

  /// Executes [operation] in a cancellable manner.
  ///
  /// If cancellation has already been requested, [operation] is not called and
  /// this method immediately throws [CancellationException]. If [operation] returns
  /// a [Future], it is automatically raced against this scope via [race].
  Future<T> runCancellable<T>(FutureOr<T> Function() operation);

  /// Pauses execution for [duration] in a cancellable manner.
  ///
  /// If the command is cancelled while sleeping, throws [CancellationException]
  /// immediately rather than hanging until [duration] expires.
  Future<void> sleep(Duration duration);

  /// Subscribes to [stream] and automatically cancels the subscription when this
  /// command's cancellation token is triggered (e.g. on restart or disposal).
  StreamSubscription<T> listen<T>(
    Stream<T> stream, {
    void Function(T data)? onData,
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  });

  /// Subscribes to [stream] and awaits until the stream closes or this command
  /// is cancelled (e.g. via [ExecutionPolicy.restart] or commander disposal).
  ///
  /// Upon cancellation, the subscription is automatically closed and this method
  /// returns cleanly.
  Future<void> forEach<T>(
    Stream<T> stream, {
    required void Function(T data) onData,
    Function? onError,
    bool? cancelOnError,
  });

  /// Registers a cleanup callback that will be executed if this command is cancelled.
  ///
  /// Returns a teardown function to unregister the callback if the operation completes normally.
  void Function() attach(void Function() onCancel);
}
