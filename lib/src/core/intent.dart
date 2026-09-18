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
abstract class CommandIntent {
  /// Const constructor for intent subclasses.
  const CommandIntent();
}

/// Convenience alias for [CommandIntent].
///
/// Note: When importing `package:flutter/widgets.dart` or `package:flutter/material.dart`,
/// prefer using [CommandIntent] directly to avoid namespace collisions with Flutter's
/// built-in `actions.dart` [Intent].
typedef Intent = CommandIntent;
