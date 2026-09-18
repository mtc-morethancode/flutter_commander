import 'package:flutter/widgets.dart';

import '../controller/commander_controller.dart';
import 'commander_builder.dart';

/// Rebuilds widget subtrees reactively based on a selected slice [R] of state [S].
///
/// Unlike [CommanderBuilder], [select] is strictly required, providing compile-time
/// safety against missing projection functions.
///
/// Example:
/// ```dart
/// CommanderSelector<CartController, CartState, int>(
///   select: (state) => state.itemCount,
///   builder: (context, count) => Text('Items: $count'),
/// )
/// ```
class CommanderSelector<C extends CommanderController<S, dynamic>, S, R>
    extends StatelessWidget {
  /// Optional controller instance. If omitted, resolved from the nearest [CommanderScope].
  final C? controller;

  /// Selector mapping full state [S] to selected slice [R].
  final R Function(S state) select;

  /// Widget builder function invoked with the selected [R] value.
  final Widget Function(BuildContext context, R value) builder;

  /// Optional condition to control whether [builder] should be called on value changes.
  final bool Function(R previous, R current)? buildWhen;

  /// Creates a [CommanderSelector].
  const CommanderSelector({
    super.key,
    this.controller,
    required this.select,
    required this.builder,
    this.buildWhen,
  });

  @override
  Widget build(BuildContext context) {
    return CommanderBuilder<C, S, R>(
      controller: controller,
      select: select,
      buildWhen: buildWhen,
      builder: builder,
    );
  }
}
