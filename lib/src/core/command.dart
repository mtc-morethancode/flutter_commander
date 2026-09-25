import 'dart:async';

import 'command_scope.dart';
import 'execution_policy.dart';
import 'intent.dart';

/// Base class for all business logic commands in `flutter_commander`.
///
/// Encapsulates a single use case or interaction with dedicated dependencies
/// and an explicit [ExecutionPolicy].
///
/// Example:
/// ```dart
/// class SubmitOrderCommand extends Command<SubmitOrderIntent, OrderState, OrderEffect> {
///   final OrderRepository _repo;
///   SubmitOrderCommand(this._repo);
///
///   @override
///   ExecutionPolicy get policy => ExecutionPolicy.drop;
///
///   @override
///   Future<void> execute(
///     CommandScope<OrderState, OrderEffect> scope,
///     SubmitOrderIntent intent,
///   ) async {
///     scope.updateState((s) => s.copyWith(isLoading: true));
///     try {
///       await _repo.submit(intent.orderId);
///       scope.emitSideEffect(const NavigateToConfirmationEffect());
///       scope.updateState((s) => s.copyWith(isLoading: false));
///     } catch (e) {
///       scope.updateState((s) => s.copyWith(isLoading: false, error: e.toString()));
///     }
///   }
/// }
/// ```
abstract class Command<I extends CommandIntent, S, E> {
  /// Const constructor for commands without mutable state.
  const Command();

  /// Concurrency policy applied when this command is triggered.
  /// Defaults to [ExecutionPolicy.concurrent].
  ExecutionPolicy get policy => ExecutionPolicy.concurrent;

  /// Optional key used to scope concurrency policies ([ExecutionPolicy.drop],
  /// [ExecutionPolicy.restart], [ExecutionPolicy.queue]) per entity or group rather
  /// than globally across all invocations of this command.
  ///
  /// If null (default), the policy applies globally across all invocations of this command.
  /// If non-null, the policy applies independently to each unique key returned.
  Object? concurrencyKey(I intent) => null;

  /// Internal helper to resolve concurrency key without dynamic invocation.
  Object? resolveConcurrencyKey(CommandIntent intent) {
    if (intent is I) {
      return concurrencyKey(intent);
    }
    return null;
  }

  /// Optional duration to debounce invocations of this command.
  ///
  /// If specified and greater than [Duration.zero], incoming invocations will wait
  /// for [debounce] of inactivity before proceeding to execution under [policy].
  /// If a new invocation arrives before the duration elapses, the previous timer
  /// is reset.
  Duration? get debounce => null;

  /// Executes the command logic with the provided [scope] and triggering [intent].
  ///
  /// Can return `Future<void>` for asynchronous commands or `void` for synchronous actions.
  FutureOr<void> execute(CommandScope<S, E> scope, I intent);
}
