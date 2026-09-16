import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/command.dart';
import '../core/command_interceptor.dart';
import '../core/command_scope.dart';
import '../core/execution_policy.dart';
import '../core/intent.dart';
import 'command_registry.dart';
import 'command_runner.dart';

/// Thrown when an [Intent] is dispatched without any matching registered [Command].
class UnregisteredIntentException implements Exception {
  /// The unmatched intent instance.
  final Intent intent;

  /// Creates an [UnregisteredIntentException] for [intent].
  const UnregisteredIntentException(this.intent);

  @override
  String toString() =>
      'UnregisteredIntentException: No command registered for intent of type ${intent.runtimeType}. '
      'Ensure you registered it via bind(...) or on<${intent.runtimeType}>((scope, intent) => ...).';
}

/// The core reactive orchestrator in `flutter_commander`.
///
/// Implements [ValueListenable] for high-performance reactive Flutter UI bindings
/// while orchestrating commands, concurrency policies, side-effect streams,
/// and telemetry interceptors.
///
/// Example:
/// ```dart
/// class OrderController extends CommanderController<OrderState, OrderEffect> {
///   OrderController(OrderRepository repo) : super(OrderState.initial()) {
///     bind(SubmitOrderCommand(repo));
///     on<ResetFormIntent>((scope, intent) {
///       scope.updateState((s) => OrderState.initial());
///     });
///   }
/// }
/// ```
abstract class CommanderController<S, E> with ChangeNotifier implements ValueListenable<S> {
  S _state;
  bool _isDisposed = false;

  final StreamController<E> _effectsController = StreamController<E>.broadcast();
  final List<CommandInterceptor> _interceptors = [];
  late final CommandRegistry<S, E> _registry;
  late final CommandRunner<S, E> _runner;

  /// Creates a [CommanderController] with an [initialState] and optional [interceptors].
  CommanderController(S initialState, {List<CommandInterceptor>? interceptors})
      : _state = initialState {
    if (interceptors != null) {
      _interceptors.addAll(interceptors);
    }

    _registry = CommandRegistry<S, E>();
    _runner = CommandRunner<S, E>(
      getState: () => _state,
      updateState: _handleUpdateState,
      emitSideEffect: _handleEmitSideEffect,
      interceptors: _interceptors,
    );
  }

  /// The current state of this controller.
  S get state => _state;

  /// Implementation of [ValueListenable.value].
  @override
  S get value => _state;

  /// Broadcast stream of one-shot side effects.
  Stream<E> get effects => _effectsController.stream;

  /// Whether this controller has been disposed.
  bool get isDisposed => _isDisposed;

  /// Adds a telemetry/logging [interceptor] to this controller.
  void addInterceptor(CommandInterceptor interceptor) {
    _interceptors.add(interceptor);
  }

  /// Removes an active [interceptor].
  void removeInterceptor(CommandInterceptor interceptor) {
    _interceptors.remove(interceptor);
  }

  /// Registers a formal [Command] class for intent type [I].
  ///
  /// The intent type [I] is automatically inferred from the command's generic type.
  ///
  /// Example:
  /// ```dart
  /// bind(SubmitOrderCommand(repo));
  /// ```
  @protected
  void bind<I extends Intent>(Command<I, S, E> command) {
    _registry.register<I>(command);
  }

  /// Registers an inline DSL action for quick UI interactions without creating
  /// a separate [Command] class.
  ///
  /// Example:
  /// ```dart
  /// on<ToggleThemeIntent>((scope, intent) {
  ///   scope.updateState((s) => s.copyWith(isDark: !s.isDark));
  /// });
  /// ```
  @protected
  void on<I extends Intent>(
    FutureOr<void> Function(CommandScope<S, E> scope, I intent) handler, {
    ExecutionPolicy policy = ExecutionPolicy.concurrent,
  }) {
    _registry.registerInline<I>(handler, policy: policy);
  }

  /// Dispatches an [intent] to be processed by its corresponding registered [Command].
  ///
  /// Returns a [Future] completing when the command execution finishes
  /// (or completes immediately if dropped by [ExecutionPolicy.drop]).
  /// Throws [UnregisteredIntentException] if no command was registered for [intent].
  Future<void> dispatch(Intent intent) async {
    if (_isDisposed) return;

    final command = _registry.find(intent);
    if (command == null) {
      throw UnregisteredIntentException(intent);
    }

    await _runner.run(command, intent);
  }

  void _handleUpdateState(S Function(S current) reducer) {
    if (_isDisposed) return;

    final oldState = _state;
    final newState = reducer(oldState);

    // Skip if state is identical or equal
    if (identical(oldState, newState) || oldState == newState) {
      return;
    }

    _state = newState;

    for (final interceptor in _interceptors) {
      try {
        interceptor.onStateChanged(oldState, newState);
      } catch (_) {}
    }

    notifyListeners();
  }

  void _handleEmitSideEffect(E effect) {
    if (_isDisposed) return;

    for (final interceptor in _interceptors) {
      try {
        interceptor.onEffectEmitted(effect);
      } catch (_) {}
    }

    if (!_effectsController.isClosed) {
      _effectsController.add(effect);
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    _runner.dispose();
    _registry.clear();
    unawaited(_effectsController.close());

    super.dispose();
  }
}
