import '../commander/commander.dart';
import 'command.dart';
import 'intent.dart';

/// Global observer for monitoring lifecycle events, executions, state mutations,
/// side-effects, and unhandled errors across all [Commander] instances in an application.
///
/// Ideal for centralized logging, Sentry / Crashlytics error reporting, and analytics.
///
/// Example:
/// ```dart
/// class AppObserver extends CommanderObserver {
///   @override
///   void onError(commander, command, intent, error, stackTrace) {
///     FirebaseCrashlytics.instance.recordError(error, stackTrace);
///   }
/// }
///
/// void main() {
///   Commander.observer = AppObserver();
///   runApp(const MyApp());
/// }
/// ```
abstract class CommanderObserver {
  /// Base const constructor.
  const CommanderObserver();

  /// Invoked when a [commander] is instantiated.
  void onCommanderCreated(Commander<dynamic, dynamic> commander) {}

  /// Invoked immediately before a [command] begins execution.
  void onBeforeExecute(
    Commander<dynamic, dynamic>? commander,
    Command<dynamic, dynamic, dynamic> command,
    CommandIntent intent,
  ) {}

  /// Invoked after a [command] finishes execution (successful, cancelled, or error).
  void onAfterExecute(
    Commander<dynamic, dynamic>? commander,
    Command<dynamic, dynamic, dynamic> command,
    CommandIntent intent,
  ) {}

  /// Invoked whenever any commander's state changes.
  void onStateChanged(
    Commander<dynamic, dynamic>? commander,
    dynamic oldState,
    dynamic newState,
  ) {}

  /// Invoked whenever any commander emits a side effect.
  void onEffectEmitted(
    Commander<dynamic, dynamic>? commander,
    dynamic effect,
  ) {}

  /// Invoked whenever an error occurs during the execution of a command or commander lifecycle.
  void onError(
    Commander<dynamic, dynamic>? commander,
    Command<dynamic, dynamic, dynamic>? command,
    CommandIntent? intent,
    Object error,
    StackTrace stackTrace,
  ) {}

  /// Invoked when a [commander] is disposed.
  void onCommanderDisposed(Commander<dynamic, dynamic> commander) {}
}
