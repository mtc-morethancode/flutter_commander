import 'package:flutter/widgets.dart';

import '../commander/commander.dart';
import '../core/intent.dart';
import 'commander_scope.dart';

/// Clean ergonomic extension methods on [BuildContext] for `flutter_commander`.
extension CommanderBuildContextX on BuildContext {
  /// Obtains the nearest [Commander] of type [C] without subscribing to rebuilds.
  ///
  /// Example:
  /// ```dart
  /// final commander = context.commander<OrderCommander>();
  /// ```
  C commander<C extends Commander<dynamic, dynamic>>() {
    return CommanderScope.of<C>(this, listen: false);
  }

  /// Dispatches an [intent] to the nearest [Commander] of type [C].
  ///
  /// Example:
  /// ```dart
  /// context.dispatch<OrderCommander>(const SubmitOrderIntent('123'));
  /// ```
  Future<void> dispatch<C extends Commander<dynamic, dynamic>>(
    CommandIntent intent,
  ) {
    return commander<C>().dispatch(intent);
  }

  /// Subscribes this widget to a selected slice [R] from commander [C].
  ///
  /// Supports zero-ceremony type inference:
  /// ```dart
  /// final title = context.select((AppCommander c) => c.state.title);
  /// ```
  /// Or with explicit type arguments:
  /// ```dart
  /// final title = context.select<AppCommander, String>((c) => c.state.title);
  /// ```
  R select<C extends Commander<dynamic, dynamic>, R>(
    R Function(C commander) selector, {
    Object? aspectKey,
  }) {
    return CommanderScope.select<C, R>(this, selector, aspectKey: aspectKey);
  }

  /// Subscribes this widget to a selected slice [R] of state [S] from commander [C].
  ///
  /// Example:
  /// ```dart
  /// final isLoading = context.selectState<OrderCommander, OrderState, bool>(
  ///   (state) => state.isLoading,
  ///   aspectKey: #isLoading,
  /// );
  /// ```
  R selectState<C extends Commander<S, dynamic>, S, R>(
    R Function(S state) selector, {
    Object? aspectKey,
  }) {
    return CommanderScope.selectState<C, S, R>(this, selector,
        aspectKey: aspectKey);
  }
}
