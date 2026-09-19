import 'dart:async';

import '../core/command.dart';
import '../core/command_scope.dart';
import '../core/execution_policy.dart';
import '../core/intent.dart';

/// Type-safe container holding registered commands mapped to their intent types.
class CommandRegistry<S, E> {
  final Map<Type, _CommandEntry<S, E>> _entries = {};

  /// Registers a formal [command] handling [I] intents.
  void register<I extends CommandIntent>(Command<I, S, E> command) {
    _entries[I] = _CommandEntry<S, E>(
      intentType: I,
      command: command,
      isCompatible: (intent) => intent is I,
    );
  }

  /// Registers an inline handler for quick UI actions without creating a separate class.
  void registerInline<I extends CommandIntent>(
    FutureOr<void> Function(CommandScope<S, E> scope, I intent) handler, {
    ExecutionPolicy policy = ExecutionPolicy.concurrent,
    Object? Function(I intent)? concurrencyKey,
    Duration? debounce,
  }) {
    final inlineCommand = _InlineCommand<I, S, E>(handler, policy, concurrencyKey, debounce);
    register<I>(inlineCommand);
  }

  /// Finds the registered command capable of handling [intent].
  ///
  /// First attempts an O(1) exact type lookup. If not found, checks for
  /// polymorphic inheritance compatibility.
  Command<dynamic, S, E>? find(CommandIntent intent) {
    // 1. O(1) exact match
    final exact = _entries[intent.runtimeType];
    if (exact != null) {
      return exact.command;
    }

    // 2. Polymorphic match fallback
    for (final entry in _entries.values) {
      if (entry.isCompatible(intent)) {
        // Cache polymorphic resolution for subsequent O(1) lookups
        _entries[intent.runtimeType] = entry;
        return entry.command;
      }
    }

    return null;
  }

  /// Checks if any command is registered for [I].
  bool contains<I extends CommandIntent>() => _entries.containsKey(I);

  /// Clears all registered commands.
  void clear() => _entries.clear();
}

class _CommandEntry<S, E> {
  final Type intentType;
  final Command<dynamic, S, E> command;
  final bool Function(CommandIntent intent) isCompatible;

  _CommandEntry({
    required this.intentType,
    required this.command,
    required this.isCompatible,
  });
}

class _InlineCommand<I extends CommandIntent, S, E> extends Command<I, S, E> {
  final FutureOr<void> Function(CommandScope<S, E> scope, I intent) _handler;
  final ExecutionPolicy _policy;
  final Object? Function(I intent)? _concurrencyKey;
  final Duration? _debounce;

  _InlineCommand(this._handler, this._policy, [this._concurrencyKey, this._debounce]);

  @override
  ExecutionPolicy get policy => _policy;

  @override
  Object? concurrencyKey(I intent) => _concurrencyKey?.call(intent);

  @override
  Duration? get debounce => _debounce;

  @override
  Future<void> execute(CommandScope<S, E> scope, I intent) async {
    await _handler(scope, intent);
  }

  @override
  String toString() => 'InlineCommand<$I>';
}
