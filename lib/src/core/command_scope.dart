import 'cancellation_token.dart';

/// Context provided to a [Command] during its execution lifecycle.
///
/// Gives access to the current state, synchronous state updates via pure reducers,
/// one-shot side-effect emissions, and collaborative cancellation tokens.
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
}
