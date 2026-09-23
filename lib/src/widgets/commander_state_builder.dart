import 'package:flutter/widgets.dart';

import '../commander/commander.dart';
import 'commander_builder.dart';

/// Rebuilds widget subtrees reactively based on a [Commander]'s full state [S].
///
/// A simplified alternative to [CommanderBuilder] that requires only 2 generic type parameters
/// (`C` and `S`) instead of 3, avoiding the need to specify the state type twice.
///
/// Example:
/// ```dart
/// CommanderStateBuilder<CartCommander, CartState>(
///   builder: (context, state) => Text('Items: ${state.count}'),
/// )
/// ```
class CommanderStateBuilder<C extends Commander<S, dynamic>, S>
    extends StatelessWidget {
  /// Optional commander instance. If omitted, resolved from the nearest [CommanderScope].
  final C? commander;

  /// Widget builder function invoked with the full current [S] state.
  final Widget Function(BuildContext context, S state) builder;

  /// Optional condition to control whether [builder] should be called on state changes.
  final bool Function(S previous, S current)? buildWhen;

  /// Creates a [CommanderStateBuilder].
  const CommanderStateBuilder({
    super.key,
    this.commander,
    required this.builder,
    this.buildWhen,
  });

  @override
  Widget build(BuildContext context) {
    return CommanderBuilder<C, S, S>(
      commander: commander,
      builder: builder,
      buildWhen: buildWhen,
    );
  }
}
