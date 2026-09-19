import '../controller/commander_controller.dart';
import 'command.dart';
import 'intent.dart';

/// Global observer for monitoring lifecycle events, executions, state mutations,
/// side-effects, and unhandled errors across all `CommanderController` instances in an application.
///
/// Ideal for centralized logging, Sentry / Crashlytics error reporting, and analytics.
///
/// Example:
/// ```dart
/// class AppObserver extends CommanderObserver {
///   @override
///   void onError(controller, command, intent, error, stackTrace) {
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

  /// Invoked when a [controller] is instantiated.
  void onControllerCreated(CommanderController<dynamic, dynamic> controller) {}

  /// Invoked immediately before a [command] begins execution.
  void onBeforeExecute(
    CommanderController<dynamic, dynamic>? controller,
    Command<dynamic, dynamic, dynamic> command,
    CommandIntent intent,
  ) {}

  /// Invoked after a [command] finishes execution (successful, cancelled, or error).
  void onAfterExecute(
    CommanderController<dynamic, dynamic>? controller,
    Command<dynamic, dynamic, dynamic> command,
    CommandIntent intent,
  ) {}

  /// Invoked whenever any controller's state changes.
  void onStateChanged(
    CommanderController<dynamic, dynamic>? controller,
    dynamic oldState,
    dynamic newState,
  ) {}

  /// Invoked whenever any controller emits a side effect.
  void onEffectEmitted(
    CommanderController<dynamic, dynamic>? controller,
    dynamic effect,
  ) {}

  /// Invoked whenever an error occurs during the execution of a command or controller lifecycle.
  void onError(
    CommanderController<dynamic, dynamic>? controller,
    Command<dynamic, dynamic, dynamic>? command,
    CommandIntent? intent,
    Object error,
    StackTrace stackTrace,
  ) {}

  /// Invoked when a [controller] is disposed.
  void onControllerDisposed(CommanderController<dynamic, dynamic> controller) {}
}

/// Global registry and configuration entry point for `flutter_commander`.
abstract final class Commander {
  Commander._();

  /// Global observer for monitoring telemetry, analytics, and crashes across
  /// all controllers in the application.
  static CommanderObserver? observer;
}
