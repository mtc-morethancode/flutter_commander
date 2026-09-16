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
abstract class Command<I extends Intent, S, E> {
  /// Const constructor for commands without mutable state.
  const Command();

  /// Concurrency policy applied when this command is triggered.
  /// Defaults to [ExecutionPolicy.concurrent].
  ExecutionPolicy get policy => ExecutionPolicy.concurrent;

  /// Executes the command logic with the provided [scope] and triggering [intent].
  Future<void> execute(CommandScope<S, E> scope, I intent);
}
