import 'package:flutter/widgets.dart';

import '../controller/commander_controller.dart';
import '../core/intent.dart';
import 'commander_scope.dart';

/// Clean ergonomic extension methods on [BuildContext] for `flutter_commander`.
extension CommanderBuildContextX on BuildContext {
  /// Obtains the nearest [CommanderController] of type [C] without subscribing to rebuilds.
  ///
  /// Example:
  /// ```dart
  /// final controller = context.commander<OrderController>();
  /// ```
  C commander<C extends CommanderController<dynamic, dynamic>>() {
    return CommanderScope.of<C>(this, listen: false);
  }

  /// Dispatches an [intent] to the nearest [CommanderController] of type [C].
  ///
  /// Example:
  /// ```dart
  /// context.dispatch<OrderController>(const SubmitOrderIntent('123'));
  /// ```
  Future<void> dispatch<C extends CommanderController<dynamic, dynamic>>(
    CommandIntent intent,
  ) {
    return commander<C>().dispatch(intent);
  }

  /// Subscribes this widget to a selected slice [R] of state [S] from controller [C].
  ///
  /// Only rebuilds this widget when the returned [R] value changes.
  /// An optional [aspectKey] can be provided for stable aspect equality caching.
  ///
  /// Example:
  /// ```dart
  /// final isLoading = context.select<OrderController, OrderState, bool>(
  ///   (state) => state.isLoading,
  ///   aspectKey: #isLoading,
  /// );
  /// ```
  R select<C extends CommanderController<S, dynamic>, S, R>(
    R Function(S state) selector, {
    Object? aspectKey,
  }) {
    return CommanderScope.select<C, S, R>(this, selector, aspectKey: aspectKey);
  }
}
