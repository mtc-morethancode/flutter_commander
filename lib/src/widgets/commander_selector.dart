import 'package:flutter/widgets.dart';

import '../commander/commander.dart';
import 'commander_builder.dart';

/// Rebuilds widget subtrees reactively based on a selected slice [R] of state [S].
///
/// Unlike [CommanderBuilder], [select] is strictly required, providing compile-time
/// safety against missing projection functions.
///
/// Example:
/// ```dart
/// CommanderSelector<CartCommander, CartState, int>(
///   select: (state) => state.itemCount,
///   builder: (context, count) => Text('Items: $count'),
/// )
/// ```
class CommanderSelector<C extends Commander<S, dynamic>, S, R>
    extends StatelessWidget {
  /// Optional commander instance. If omitted, resolved from the nearest [CommanderScope].
  final C? commander;

  /// Selector mapping full state [S] to selected slice [R].
  final R Function(S state) select;

  /// Widget builder function invoked with the selected [R] value.
  final Widget Function(BuildContext context, R value) builder;

  /// Optional condition to control whether [builder] should be called on value changes.
  final bool Function(R previous, R current)? buildWhen;

  /// Creates a [CommanderSelector].
  const CommanderSelector({
    super.key,
    this.commander,
    required this.select,
    required this.builder,
    this.buildWhen,
  });

  @override
  Widget build(BuildContext context) {
    return CommanderBuilder<C, S, R>(
      commander: commander,
      select: select,
      buildWhen: buildWhen,
      builder: builder,
    );
  }
}
