import 'package:meta/meta.dart';

/// Base marker interface for all user or system intents.
///
/// Intents represent an intention to trigger a business operation or state mutation.
/// They are dispatched from the UI or lifecycle events and routed to their
/// corresponding `Command`.
///
/// Example:
/// ```dart
/// class SubmitOrderIntent extends CommandIntent {
///   final String orderId;
///   const SubmitOrderIntent(this.orderId);
/// }
/// ```
@immutable
abstract class CommandIntent {
  /// Const constructor for intent subclasses.
  const CommandIntent();
}

