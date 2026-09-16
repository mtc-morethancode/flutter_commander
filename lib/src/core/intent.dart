import 'package:meta/meta.dart';

/// Base marker interface for all user or system intents.
///
/// Intents represent an intention to trigger a business operation or state mutation.
/// They are dispatched from the UI or lifecycle events and routed to their
/// corresponding `Command`.
///
/// Example:
/// ```dart
/// class SubmitOrderIntent extends Intent {
///   final String orderId;
///   const SubmitOrderIntent(this.orderId);
/// }
/// ```
@immutable
abstract class Intent {
  /// Const constructor for intent subclasses.
  const Intent();
}

/// Canonical alias for [Intent] in case of namespace collisions with Flutter's
/// `actions.dart` [Intent].
typedef CommandIntent = Intent;
