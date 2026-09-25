import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../core/command.dart';
import '../core/command_interceptor.dart';
import '../core/command_scope.dart';
import '../core/commander_observer.dart';
import '../core/execution_policy.dart';
import '../core/intent.dart';
import 'command_registry.dart';
import 'command_runner.dart';

/// Thrown when a [CommandIntent] is dispatched without any matching registered [Command].
class UnregisteredIntentException implements Exception {
  /// The unmatched intent instance.
  final CommandIntent intent;

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
/// class OrderCommander extends Commander<OrderState, OrderEffect> {
///   OrderCommander(OrderRepository repo) : super(OrderState.initial()) {
///     bind(SubmitOrderCommand(repo));
///     on<ResetFormIntent>((scope, intent) {
///       scope.updateState((s) => OrderState.initial());
///     });
///   }
/// }
/// ```
abstract class Commander<S, E>
    with ChangeNotifier
    implements ValueListenable<S> {
  /// Global observer for monitoring telemetry, analytics, and crashes across
  /// all commanders in the application.
  static CommanderObserver? observer;

  /// In debug mode, logs a diagnostic warning when an `updateState` reducer
  /// returns the exact same state reference (`identical(oldState, newState)`).
  ///
  /// This helps catch in-place mutation bugs (e.g. `state.items.add(x); return state;`)
  /// which cause state updates to be skipped.
  static bool debugWarnOnIdenticalState = true;

  static const int _maxPendingEffectsBuffer = 32;
  final Queue<E> _unhandledEffectsBuffer = Queue<E>();

  S _state;
  bool _isDisposed = false;

  late final StreamController<E> _effectsController;
  final List<CommandInterceptor> _interceptors = [];
  late final CommandRegistry<S, E> _registry;
  late final CommandRunner<S, E> _runner;

  /// Creates a [Commander] with an [initialState] and optional [interceptors].
  Commander(S initialState, {List<CommandInterceptor>? interceptors})
      : _state = initialState {
    if (interceptors != null) {
      _interceptors.addAll(interceptors);
    }

    _effectsController = StreamController<E>.broadcast(
      onListen: _flushPendingEffects,
    );

    Commander.observer?.onCommanderCreated(this);
    _registry = CommandRegistry<S, E>();
    _runner = CommandRunner<S, E>(
      commander: this,
      getState: () => _state,
      updateState: _handleUpdateState,
      emitSideEffect: _handleEmitSideEffect,
      interceptors: _interceptors,
      onError: (command, intent, error, stackTrace) {
        onError(error, stackTrace, intent);
      },
    );

    onInit();
  }

  /// Lifecycle hook called immediately upon commander construction.
  ///
  /// Can be overridden by subclasses or mixins (such as `SavedStateMixin`)
  /// to perform initial setups or schedule asynchronous tasks.
  @protected
  @mustCallSuper
  void onInit() {}

  void _flushPendingEffects() {
    if (_unhandledEffectsBuffer.isEmpty) return;

    // Dispatch buffered cold-start effects to the newly attached listener
    scheduleMicrotask(() {
      while (_unhandledEffectsBuffer.isNotEmpty &&
          !_effectsController.isClosed &&
          _effectsController.hasListener) {
        final effect = _unhandledEffectsBuffer.removeFirst();
        _effectsController.add(effect);
      }
    });
  }

  /// The current state of this commander.
  S get state => _state;

  /// Implementation of [ValueListenable.value].
  @override
  S get value => _state;

  /// Broadcast stream of one-shot side effects.
  Stream<E> get effects => _effectsController.stream;

  /// Whether this commander has been disposed.
  bool get isDisposed => _isDisposed;

  /// Adds a telemetry/logging [interceptor] to this commander.
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
  void bind<I extends CommandIntent>(Command<I, S, E> command) {
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
  void on<I extends CommandIntent>(
    FutureOr<void> Function(CommandScope<S, E> scope, I intent) handler, {
    ExecutionPolicy policy = ExecutionPolicy.concurrent,
    Object? Function(I intent)? concurrencyKey,
    Duration? debounce,
  }) {
    _registry.registerInline<I>(
      handler,
      policy: policy,
      concurrencyKey: concurrencyKey,
      debounce: debounce,
    );
  }

  /// Hook invoked whenever an unhandled error occurs during the execution of a command.
  ///
  /// By default, this method rethrows the error with its original [stackTrace].
  /// Subclasses can override this method to handle errors globally (e.g. logging to
  /// Crashlytics, emitting an error side effect, or updating error state) without
  /// letting unhandled exceptions crash the UI layer.
  ///
  /// Example:
  /// ```dart
  /// @override
  /// void onError(Object error, StackTrace stackTrace, CommandIntent intent) {
  ///   // Absorb error safely or emit side effect
  /// }
  /// ```
  @protected
  void onError(
    Object error,
    StackTrace stackTrace,
    CommandIntent intent,
  ) {
    Error.throwWithStackTrace(error, stackTrace);
  }

  /// Dispatches an [intent] to be processed by its corresponding registered [Command].
  ///
  /// Returns a [Future] completing when the command execution finishes
  /// (or completes immediately if dropped by [ExecutionPolicy.drop]).
  /// Throws [UnregisteredIntentException] if no command was registered for [intent].
  Future<void> dispatch(CommandIntent intent) {
    if (_isDisposed) return Future<void>.value();

    final command = _registry.find(intent);
    if (command == null) {
      throw UnregisteredIntentException(intent);
    }

    final result = _runner.run(command, intent);
    if (result is Future) {
      return result;
    }
    return Future<void>.value();
  }

  /// Updates the state using the provided pure [reducer].
  ///
  /// Note: States must be immutable. If the [reducer] returns an identical or
  /// equal (`==`) state, [notifyListeners] is skipped to prevent redundant rebuilds.
  void _handleUpdateState(S Function(S current) reducer) {
    if (_isDisposed) return;

    final oldState = _state;
    final newState = reducer(oldState);

    // Skip if state is identical or equal
    if (identical(oldState, newState) || oldState == newState) {
      assert(() {
        if (identical(oldState, newState) &&
            debugWarnOnIdenticalState &&
            kDebugMode) {
          debugPrint(
            '[flutter_commander] [Warning] updateState reducer in $runtimeType returned the identical state instance. '
            'If you modified fields in-place on the existing state, the update was skipped because '
            'flutter_commander enforces immutability. Return a new state instance (e.g. using copyWith).',
          );
        }
        return true;
      }());
      return;
    }

    _state = newState;

    if (Commander.observer != null) {
      Commander.observer!.onStateChanged(this, oldState, newState);
    }
    if (_interceptors.isNotEmpty) {
      for (var i = 0; i < _interceptors.length; i++) {
        try {
          _interceptors[i].onStateChanged(oldState, newState);
        } catch (_) {}
      }
    }

    onStateChanged(oldState, newState);

    notifyListeners();
  }

  /// Lifecycle hook called after state transitions from [oldState] to [newState].
  ///
  /// Subclasses and mixins can override this hook to react to state updates
  /// (such as automatic state persistence or undo/redo history tracking).
  @protected
  @mustCallSuper
  void onStateChanged(S oldState, S newState) {}

  /// Lifecycle hook called when state is restored from persistence or history.
  @protected
  @mustCallSuper
  void onStateRestored(S oldState, S newState) {}

  /// Restores or overrides the state directly (e.g. from `SavedStateMixin` or undo/redo).
  ///
  /// If [restoredState] equals the current state, listeners are not notified.
  @protected
  void restoreState(S restoredState) {
    if (_isDisposed) return;

    final oldState = _state;
    if (identical(oldState, restoredState) || oldState == restoredState) {
      return;
    }

    _state = restoredState;

    if (Commander.observer != null) {
      Commander.observer!.onStateChanged(this, oldState, restoredState);
    }
    if (_interceptors.isNotEmpty) {
      for (var i = 0; i < _interceptors.length; i++) {
        try {
          _interceptors[i].onStateChanged(oldState, restoredState);
        } catch (_) {}
      }
    }

    onStateRestored(oldState, restoredState);
    notifyListeners();
  }

  /// Emits a one-shot side effect directly through this commander's effects stream.
  @protected
  void emitSideEffect(E effect) => _handleEmitSideEffect(effect);

  void _handleEmitSideEffect(E effect) {
    if (_isDisposed) return;

    if (Commander.observer != null) {
      Commander.observer!.onEffectEmitted(this, effect);
    }
    if (_interceptors.isNotEmpty) {
      for (var i = 0; i < _interceptors.length; i++) {
        try {
          _interceptors[i].onEffectEmitted(effect);
        } catch (_) {}
      }
    }

    if (_effectsController.hasListener) {
      if (!_effectsController.isClosed) {
        _effectsController.add(effect);
      }
    } else {
      // Buffer cold-start effect until first listener subscribes
      if (_unhandledEffectsBuffer.length >= _maxPendingEffectsBuffer) {
        _unhandledEffectsBuffer.removeFirst();
      }
      _unhandledEffectsBuffer.add(effect);
    }
  }

  @override
  @mustCallSuper
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    Commander.observer?.onCommanderDisposed(this);
    _unhandledEffectsBuffer.clear();
    _runner.dispose();
    _registry.clear();
    unawaited(_effectsController.close());

    super.dispose();
  }
}
