import 'command.dart';
import 'intent.dart';

/// Interceptor interface for cross-cutting observability, telemetry, and debugging.
abstract class CommandInterceptor {
  /// Base const constructor.
  const CommandInterceptor();

  /// Invoked immediately before a command starts execution.
  void onBeforeExecute(Command<dynamic, dynamic, dynamic> command, CommandIntent intent) {}

  /// Invoked after a command finishes execution (successful or cancelled).
  void onAfterExecute(Command<dynamic, dynamic, dynamic> command, CommandIntent intent) {}

  /// Invoked whenever the controller's state is updated.
  void onStateChanged(dynamic oldState, dynamic newState) {}

  /// Invoked whenever a side effect is emitted.
  void onEffectEmitted(dynamic effect) {}

  /// Invoked if a command execution throws an unhandled error.
  void onError(
    Command<dynamic, dynamic, dynamic> command,
    CommandIntent intent,
    Object error,
    StackTrace stackTrace,
  ) {}
}
