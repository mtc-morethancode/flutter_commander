import 'command.dart';
import 'command_interceptor.dart';
import 'intent.dart';

/// Default structured console logger for `flutter_commander`.
///
/// Produces standardized output:
/// ```text
/// [flutter_commander] [Intent] SubmitOrderIntent -> [Command] SubmitOrderCommand (Policy: DROP)
/// [flutter_commander] [State] OrderState(isSubmitting: true)
/// [flutter_commander] [Effect] NavigateToConfirmationEffect
/// [flutter_commander] [Error] SubmitOrderCommand: Exception message
/// ```
class LoggingCommandInterceptor extends CommandInterceptor {
  /// Custom print function for tests or structured remote logging.
  final void Function(String message)? printFn;

  /// Whether to log state mutations.
  final bool logStates;

  /// Whether to log side effects.
  final bool logEffects;

  /// Whether to log errors with stack traces.
  final bool logErrors;

  /// Creates a [LoggingCommandInterceptor] with optional customization flags.
  const LoggingCommandInterceptor({
    this.printFn,
    this.logStates = true,
    this.logEffects = true,
    this.logErrors = true,
  });

  void _log(String message) {
    if (printFn != null) {
      printFn!(message);
    } else {
      // ignore: avoid_print
      print(message);
    }
  }

  @override
  void onBeforeExecute(Command<dynamic, dynamic, dynamic> command, CommandIntent intent) {
    final policyName = command.policy.name.toUpperCase();
    _log(
      '[flutter_commander] [Intent] ${intent.runtimeType} -> [Command] ${command.runtimeType} (Policy: $policyName)',
    );
  }

  @override
  void onStateChanged(dynamic oldState, dynamic newState) {
    if (logStates) {
      _log('[flutter_commander] [State] $newState');
    }
  }

  @override
  void onEffectEmitted(dynamic effect) {
    if (logEffects) {
      _log('[flutter_commander] [Effect] $effect');
    }
  }

  @override
  void onError(
    Command<dynamic, dynamic, dynamic> command,
    CommandIntent intent,
    Object error,
    StackTrace stackTrace,
  ) {
    if (logErrors) {
      _log(
        '[flutter_commander] [Error] ${command.runtimeType} for ${intent.runtimeType}: $error\n$stackTrace',
      );
    }
  }
}
