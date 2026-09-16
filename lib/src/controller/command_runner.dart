import 'dart:async';
import 'dart:collection';

import '../core/cancellation_token.dart';
import '../core/command.dart';
import '../core/command_interceptor.dart';
import '../core/command_scope.dart';
import '../core/execution_policy.dart';
import '../core/intent.dart';

/// Runner responsible for orchestrating command execution under their specified
/// [ExecutionPolicy], managing queues, cancellation tokens, and interceptors.
class CommandRunner<S, E> {
  final S Function() _getState;
  final void Function(S Function(S current) reducer) _updateState;
  final void Function(E effect) _emitSideEffect;
  final List<CommandInterceptor> _interceptors;

  // Active state tracked by command identity
  final Map<Command<dynamic, S, E>, CancellationToken> _activeTokens = {};
  final Map<Command<dynamic, S, E>, Future<void>> _activeExecutions = {};
  final Map<Command<dynamic, S, E>, Queue<_QueuedExecution<S, E>>> _queues = {};

  bool _isDisposed = false;

  /// Creates a [CommandRunner] wired to the controller's state and effect channels.
  CommandRunner({
    required S Function() getState,
    required void Function(S Function(S current) reducer) updateState,
    required void Function(E effect) emitSideEffect,
    required List<CommandInterceptor> interceptors,
  })  : _getState = getState,
        _updateState = updateState,
        _emitSideEffect = emitSideEffect,
        _interceptors = interceptors;

  /// Runs [command] with [intent] respecting [command.policy].
  Future<void> run(Command<dynamic, S, E> command, Intent intent) async {
    if (_isDisposed) return;

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

  Future<void> _runDrop(Command<dynamic, S, E> command, Intent intent) async {
    final active = _activeExecutions[command];
    if (active != null) {
      // An execution is currently running; drop this invocation immediately.
      return;
    }

    final token = CancellationToken();
    _activeTokens[command] = token;

    final executionFuture = _executeCommand(command, intent, token);
    _activeExecutions[command] = executionFuture;

    try {
      await executionFuture;
    } finally {
      if (_activeExecutions[command] == executionFuture) {
        unawaited(_activeExecutions.remove(command));
        _activeTokens.remove(command);
      }
    }
  }

  Future<void> _runRestart(Command<dynamic, S, E> command, Intent intent) async {
    // 1. Cancel previous running token
    final previousToken = _activeTokens[command];
    if (previousToken != null && !previousToken.isCancelled) {
      previousToken.cancel();
    }

    // 2. Setup fresh cancellation token
    final token = CancellationToken();
    _activeTokens[command] = token;

    final executionFuture = _executeCommand(command, intent, token);
    _activeExecutions[command] = executionFuture;

    try {
      await executionFuture;
    } finally {
      if (_activeTokens[command] == token) {
        _activeTokens.remove(command);
        unawaited(_activeExecutions.remove(command));
      }
    }
  }

  Future<void> _runQueue(Command<dynamic, S, E> command, Intent intent) {
    final queue = _queues.putIfAbsent(command, () => Queue<_QueuedExecution<S, E>>());
    final completer = Completer<void>();
    final token = CancellationToken();

    final queuedItem = _QueuedExecution<S, E>(
      command: command,
      intent: intent,
      token: token,
      completer: completer,
    );

    queue.add(queuedItem);

    if (queue.length == 1) {
      unawaited(_processQueue(command));
    }

    return completer.future;
  }

  Future<void> _processQueue(Command<dynamic, S, E> command) async {
    final queue = _queues[command];
    if (queue == null) return;

    while (queue.isNotEmpty && !_isDisposed) {
      final current = queue.first;
      _activeTokens[command] = current.token;

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
        _activeTokens.remove(command);
      }
    }

    if (queue.isEmpty) {
      _queues.remove(command);
    }
  }

  Future<void> _runConcurrent(Command<dynamic, S, E> command, Intent intent) async {
    final token = CancellationToken();
    await _executeCommand(command, intent, token);
  }

  Future<void> _executeCommand(
    Command<dynamic, S, E> command,
    Intent intent,
    CancellationToken token,
  ) async {
    final scope = _ControlledCommandScope<S, E>(
      getState: _getState,
      updateState: _updateState,
      emitSideEffect: _emitSideEffect,
      cancellationToken: token,
    );

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
      for (final interceptor in _interceptors) {
        try {
          interceptor.onError(command, intent, error, stackTrace);
        } catch (_) {}
      }
      rethrow;
    } finally {
      for (final interceptor in _interceptors) {
        try {
          interceptor.onAfterExecute(command, intent);
        } catch (_) {}
      }
    }
  }

  /// Cancels all active and queued operations and cleans up runner resources.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;

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

class _QueuedExecution<S, E> {
  final Command<dynamic, S, E> command;
  final Intent intent;
  final CancellationToken token;
  final Completer<void> completer;

  _QueuedExecution({
    required this.command,
    required this.intent,
    required this.token,
    required this.completer,
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
