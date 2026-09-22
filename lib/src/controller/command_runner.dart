import 'dart:async';
import 'dart:collection';

import '../core/cancellation_token.dart';
import '../core/command.dart';
import '../core/command_interceptor.dart';
import '../core/command_scope.dart';
import '../core/commander_observer.dart';
import '../core/execution_policy.dart';
import '../core/intent.dart';
import 'commander_controller.dart';

/// Runner responsible for orchestrating command execution under their specified
/// [ExecutionPolicy], managing queues, cancellation tokens, debounce timers, and interceptors.
class CommandRunner<S, E> {
  final CommanderController<dynamic, dynamic>? _controller;
  final S Function() _getState;
  final void Function(S Function(S current) reducer) _updateState;
  final void Function(E effect) _emitSideEffect;
  final List<CommandInterceptor> _interceptors;
  final void Function(
    Command<dynamic, S, E> command,
    CommandIntent intent,
    Object error,
    StackTrace stackTrace,
  )? _onError;

  // Active state tracked by execution key (command identity + optional concurrency key)
  final Map<_ExecutionKey, CancellationToken> _activeTokens = {};
  final Map<_ExecutionKey, Future<void>> _activeExecutions = {};
  final Map<_ExecutionKey, Queue<_QueuedExecution<S, E>>> _queues = {};
  final Map<_ExecutionKey, _DebounceState> _debounceTimers = {};

  // All in-flight tokens (including concurrent executions) for comprehensive teardown on dispose
  final Set<CancellationToken> _inFlightTokens = {};

  bool _isDisposed = false;

  /// Creates a [CommandRunner] wired to the controller's state, effect channels, and error handler.
  CommandRunner({
    required CommanderController<dynamic, dynamic>? controller,
    required S Function() getState,
    required void Function(S Function(S current) reducer) updateState,
    required void Function(E effect) emitSideEffect,
    required List<CommandInterceptor> interceptors,
    void Function(
      Command<dynamic, S, E> command,
      CommandIntent intent,
      Object error,
      StackTrace stackTrace,
    )? onError,
  })  : _controller = controller,
        _getState = getState,
        _updateState = updateState,
        _emitSideEffect = emitSideEffect,
        _interceptors = interceptors,
        _onError = onError;

  /// Runs [command] with [intent] respecting [command.debounce] and [command.policy].
  Future<void> run(Command<dynamic, S, E> command, CommandIntent intent) async {
    if (_isDisposed) return;

    if (command.debounce != null && command.debounce! > Duration.zero) {
      return _runDebounced(command, intent, command.debounce!);
    }

    return _dispatchToPolicy(command, intent);
  }

  Future<void> _runDebounced(
    Command<dynamic, S, E> command,
    CommandIntent intent,
    Duration duration,
  ) {
    final execKey = _ExecutionKey(command, _getConcurrencyKey(command, intent));

    // Cancel previous pending timer for this key
    final existing = _debounceTimers.remove(execKey);
    if (existing != null) {
      existing.timer.cancel();
      if (!existing.completer.isCompleted) {
        existing.completer.complete();
      }
    }

    final completer = Completer<void>();
    final timer = Timer(duration, () async {
      _debounceTimers.remove(execKey);
      if (_isDisposed) {
        if (!completer.isCompleted) completer.complete();
        return;
      }
      try {
        await _dispatchToPolicy(command, intent);
        if (!completer.isCompleted) completer.complete();
      } catch (e, st) {
        if (!completer.isCompleted) completer.completeError(e, st);
      }
    });

    _debounceTimers[execKey] = _DebounceState(timer, completer);
    return completer.future;
  }

  Future<void> _dispatchToPolicy(
      Command<dynamic, S, E> command, CommandIntent intent) {
    switch (command.policy) {
      case ExecutionPolicy.drop:
        return _runDrop(command, intent);
      case ExecutionPolicy.restart:
        return _runRestart(command, intent);
      case ExecutionPolicy.queue:
        return _runQueue(command, intent);
      case ExecutionPolicy.concurrent:
        return _runConcurrent(command, intent);
    }
  }

  Object? _getConcurrencyKey(
      Command<dynamic, S, E> command, CommandIntent intent) {
    try {
      return (command as dynamic).concurrencyKey(intent);
    } catch (_) {
      return null;
    }
  }

  Future<void> _runDrop(
      Command<dynamic, S, E> command, CommandIntent intent) async {
    final execKey = _ExecutionKey(command, _getConcurrencyKey(command, intent));
    final active = _activeExecutions[execKey];
    if (active != null) {
      // An execution is currently running for this key; drop this invocation immediately.
      return;
    }

    final token = CancellationToken();
    _activeTokens[execKey] = token;

    final executionFuture = _executeCommand(command, intent, token);
    _activeExecutions[execKey] = executionFuture;

    try {
      await executionFuture;
    } finally {
      if (_activeExecutions[execKey] == executionFuture) {
        unawaited(_activeExecutions.remove(execKey));
        _activeTokens.remove(execKey);
      }
    }
  }

  Future<void> _runRestart(
      Command<dynamic, S, E> command, CommandIntent intent) async {
    final execKey = _ExecutionKey(command, _getConcurrencyKey(command, intent));

    // 1. Cancel previous running token for this key
    final previousToken = _activeTokens[execKey];
    if (previousToken != null && !previousToken.isCancelled) {
      previousToken.cancel();
    }

    // 2. Setup fresh cancellation token
    final token = CancellationToken();
    _activeTokens[execKey] = token;

    final executionFuture = _executeCommand(command, intent, token);
    _activeExecutions[execKey] = executionFuture;

    try {
      await executionFuture;
    } finally {
      if (_activeTokens[execKey] == token) {
        _activeTokens.remove(execKey);
        unawaited(_activeExecutions.remove(execKey));
      }
    }
  }

  Future<void> _runQueue(Command<dynamic, S, E> command, CommandIntent intent) {
    final execKey = _ExecutionKey(command, _getConcurrencyKey(command, intent));
    final queue =
        _queues.putIfAbsent(execKey, () => Queue<_QueuedExecution<S, E>>());
    final completer = Completer<void>();
    final token = CancellationToken();

    final queuedItem = _QueuedExecution<S, E>(
      command: command,
      intent: intent,
      token: token,
      completer: completer,
      execKey: execKey,
    );

    queue.add(queuedItem);

    if (queue.length == 1) {
      unawaited(_processQueue(execKey));
    }

    return completer.future;
  }

  Future<void> _processQueue(_ExecutionKey execKey) async {
    final queue = _queues[execKey];
    if (queue == null) return;

    while (queue.isNotEmpty && !_isDisposed) {
      final current = queue.first;
      _activeTokens[execKey] = current.token;

      try {
        await _executeCommand(current.command, current.intent, current.token);
        if (!current.completer.isCompleted) {
          current.completer.complete();
        }
      } catch (error, stackTrace) {
        if (!current.completer.isCompleted) {
          current.completer.completeError(error, stackTrace);
        }
      } finally {
        if (queue.isNotEmpty && queue.first == current) {
          queue.removeFirst();
        }
        _activeTokens.remove(execKey);
      }
    }

    if (queue.isEmpty) {
      _queues.remove(execKey);
    }
  }

  Future<void> _runConcurrent(
      Command<dynamic, S, E> command, CommandIntent intent) async {
    final token = CancellationToken();
    await _executeCommand(command, intent, token);
  }

  Future<void> _executeCommand(
    Command<dynamic, S, E> command,
    CommandIntent intent,
    CancellationToken token,
  ) async {
    _inFlightTokens.add(token);
    final scope = _ControlledCommandScope<S, E>(
      getState: _getState,
      updateState: _updateState,
      emitSideEffect: _emitSideEffect,
      cancellationToken: token,
    );

    Commander.observer?.onBeforeExecute(_controller, command, intent);
    for (final interceptor in _interceptors) {
      try {
        interceptor.onBeforeExecute(command, intent);
      } catch (_) {}
    }

    try {
      await command.execute(scope, intent);
    } on CancellationException {
      // Operation was cancelled collaboratively; expected flow for restart/cancellation.
    } catch (error, stackTrace) {
      Commander.observer
          ?.onError(_controller, command, intent, error, stackTrace);
      for (final interceptor in _interceptors) {
        try {
          interceptor.onError(command, intent, error, stackTrace);
        } catch (_) {}
      }
      if (_onError != null) {
        _onError!(command, intent, error, stackTrace);
      } else {
        rethrow;
      }
    } finally {
      _inFlightTokens.remove(token);
      Commander.observer?.onAfterExecute(_controller, command, intent);
      for (final interceptor in _interceptors) {
        try {
          interceptor.onAfterExecute(command, intent);
        } catch (_) {}
      }
    }
  }

  /// Cancels all active, queued, debounce, and in-flight operations and cleans up runner resources.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

    // Cancel all debounce timers
    for (final state in _debounceTimers.values) {
      state.timer.cancel();
      if (!state.completer.isCompleted) {
        state.completer.complete();
      }
    }
    _debounceTimers.clear();

    // Cancel all in-flight tokens across all policies (including concurrent)
    for (final token in _inFlightTokens) {
      token.cancel();
    }
    _inFlightTokens.clear();

    for (final token in _activeTokens.values) {
      token.cancel();
    }
    _activeTokens.clear();
    _activeExecutions.clear();

    for (final queue in _queues.values) {
      while (queue.isNotEmpty) {
        final item = queue.removeFirst();
        item.token.cancel();
        if (!item.completer.isCompleted) {
          item.completer.completeError(
            const CancellationException('CommanderController was disposed.'),
          );
        }
      }
    }
    _queues.clear();
  }
}

class _DebounceState {
  final Timer timer;
  final Completer<void> completer;

  _DebounceState(this.timer, this.completer);
}

class _ExecutionKey {
  final Command<dynamic, dynamic, dynamic> command;
  final Object? key;

  const _ExecutionKey(this.command, this.key);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ExecutionKey &&
          runtimeType == other.runtimeType &&
          identical(command, other.command) &&
          key == other.key;

  @override
  int get hashCode => Object.hash(identityHashCode(command), key);

  @override
  String toString() => '_ExecutionKey(${command.runtimeType}, key: $key)';
}

class _QueuedExecution<S, E> {
  final Command<dynamic, S, E> command;
  final CommandIntent intent;
  final CancellationToken token;
  final Completer<void> completer;
  final _ExecutionKey execKey;

  _QueuedExecution({
    required this.command,
    required this.intent,
    required this.token,
    required this.completer,
    required this.execKey,
  });
}

class _ControlledCommandScope<S, E> implements CommandScope<S, E> {
  final S Function() _getState;
  final void Function(S Function(S current) reducer) _updateState;
  final void Function(E effect) _emitSideEffect;
  @override
  final CancellationToken cancellationToken;

  _ControlledCommandScope({
    required S Function() getState,
    required void Function(S Function(S current) reducer) updateState,
    required void Function(E effect) emitSideEffect,
    required this.cancellationToken,
  })  : _getState = getState,
        _updateState = updateState,
        _emitSideEffect = emitSideEffect;

  @override
  S get state => _getState();

  @override
  bool get isCancelled => cancellationToken.isCancelled;

  @override
  void updateState(S Function(S current) reducer) {
    // Prevent stale or cancelled commands from mutating state
    if (cancellationToken.isCancelled) return;
    _updateState(reducer);
  }

  @override
  void emitSideEffect(E effect) {
    // Prevent stale or cancelled commands from emitting side effects
    if (cancellationToken.isCancelled) return;
    _emitSideEffect(effect);
  }
}
