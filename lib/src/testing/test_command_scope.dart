import 'dart:async';

import '../core/cancellation_token.dart';
import '../core/command_scope.dart';

/// A deterministic, widget-free test harness for executing and verifying [Command] units.
///
/// Designed for fast, isolated unit tests without streams, mocks, or widget trees.
///
/// Example:
/// ```dart
/// test('SubmitOrderCommand emits loading then success', () async {
///   final command = SubmitOrderCommand(mockRepo);
///   final testScope = TestCommandScope<OrderState, OrderEffect>(OrderState.initial());
///
///   await command.execute(testScope, const SubmitOrderIntent('123'));
///
///   expect(testScope.states, [expectedLoadingState, expectedSuccessState]);
///   expect(testScope.effects, [const NavigateToConfirmationEffect()]);
/// });
/// ```
class TestCommandScope<S, E> implements CommandScope<S, E> {
  final S _initialState;
  S _currentState;
  final List<S> _recordedStates = [];
  final List<E> _recordedEffects = [];

  @override
  final CancellationToken cancellationToken;

  /// Creates a [TestCommandScope] with an [initialState] and optional [cancellationToken].
  TestCommandScope(
    S initialState, {
    CancellationToken? cancellationToken,
  })  : _initialState = initialState,
        _currentState = initialState,
        cancellationToken = cancellationToken ?? CancellationToken();

  /// The original initial state provided at instantiation.
  S get initialState => _initialState;

  /// The current state after applying all mutations.
  @override
  S get state => _currentState;

  /// Unmodifiable list of all states produced by [updateState] in chronological order.
  ///
  /// Does not include [initialState] unless it was explicitly emitted via [updateState].
  List<S> get states => List.unmodifiable(_recordedStates);

  /// Complete history of states including the [initialState] followed by all [states].
  List<S> get history => List.unmodifiable([_initialState, ..._recordedStates]);

  /// Unmodifiable list of all side-effects emitted by [emitSideEffect] in chronological order.
  List<E> get effects => List.unmodifiable(_recordedEffects);

  @override
  bool get isCancelled => cancellationToken.isCancelled;

  /// Simulates cooperative cancellation during a test.
  void cancel([String? reason]) => cancellationToken.cancel(reason);

  @override
  void throwIfCancelled() => cancellationToken.throwIfCancelled();

  @override
  Future<T> race<T>(Future<T> future) => cancellationToken.race<T>(future);

  @override
  Future<T> withCancellation<T>(Future<T> future) =>
      cancellationToken.race<T>(future);

  @override
  Future<T> runCancellable<T>(FutureOr<T> Function() operation) =>
      cancellationToken.runCancellable<T>(operation);

  @override
  Future<void> sleep(Duration duration) => cancellationToken.sleep(duration);

  @override
  void Function() attach(void Function() onCancel) =>
      cancellationToken.attach(onCancel);

  @override
  StreamSubscription<T> listen<T>(
    Stream<T> stream, {
    void Function(T data)? onData,
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final subscription = stream.listen(
      (data) {
        if (!cancellationToken.isCancelled && onData != null) {
          onData(data);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!cancellationToken.isCancelled && onError != null) {
          if (onError is void Function(Object, StackTrace)) {
            onError(error, stackTrace);
          } else if (onError is void Function(Object)) {
            onError(error);
          } else {
            onError(error, stackTrace);
          }
        }
      },
      onDone: () {
        if (!cancellationToken.isCancelled && onDone != null) {
          onDone();
        }
      },
      cancelOnError: cancelOnError,
    );

    cancellationToken.attach(() {
      unawaited(subscription.cancel());
    });

    return subscription;
  }

  @override
  Future<void> forEach<T>(
    Stream<T> stream, {
    required void Function(T data) onData,
    Function? onError,
    bool? cancelOnError,
  }) =>
      cancellationToken.forEach<T>(
        stream,
        onData: onData,
        onError: onError,
        cancelOnError: cancelOnError,
      );

  @override
  void updateState(S Function(S current) reducer) {
    if (cancellationToken.isCancelled) return;
    _currentState = reducer(_currentState);
    _recordedStates.add(_currentState);
  }

  @override
  void emitSideEffect(E effect) {
    if (cancellationToken.isCancelled) return;
    _recordedEffects.add(effect);
  }

  /// Clears recorded states and effects, restoring [state] back to [initialState].
  void reset() {
    _currentState = _initialState;
    _recordedStates.clear();
    _recordedEffects.clear();
  }

  /// Checks if any recorded state matches [predicate].
  bool hasState(bool Function(S state) predicate) =>
      _recordedStates.any(predicate);

  /// Checks if any emitted side effect matches [predicate].
  bool hasEffect(bool Function(E effect) predicate) =>
      _recordedEffects.any(predicate);
}
