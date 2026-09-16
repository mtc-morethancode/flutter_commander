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
  void cancel() => cancellationToken.cancel();

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
  bool hasState(bool Function(S state) predicate) => _recordedStates.any(predicate);

  /// Checks if any emitted side effect matches [predicate].
  bool hasEffect(bool Function(E effect) predicate) => _recordedEffects.any(predicate);
}
