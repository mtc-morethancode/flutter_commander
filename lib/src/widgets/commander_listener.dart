import 'dart:async';

import 'package:flutter/widgets.dart';

import '../commander/commander.dart';
import 'commander_scope.dart';

/// Listens exclusively to one-shot side effect emissions of type [E] from a [Commander]
/// without rebuilding the widget tree.
///
/// Ideal for navigation, showing SnackBar messages, alerts, and modal dialogs.
///
/// Example:
/// ```dart
/// CommanderListener<OrderCommander, OrderEffect>(
///   onEffect: (context, effect) {
///     switch (effect) {
///       case NavigateToConfirmationEffect():
///         Navigator.of(context).pushNamed('/confirmation');
///       case ShowErrorSnackbarEffect(:final message):
///         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
///     }
///   },
///   child: const OrderFormView(),
/// )
/// ```
class CommanderListener<C extends Commander<dynamic, E>, E>
    extends StatefulWidget {
  /// Optional commander instance. If omitted, resolved from the nearest [CommanderScope].
  final C? commander;

  /// Callback executed whenever an effect is emitted.
  final void Function(BuildContext context, E effect) onEffect;

  /// Optional filter to condition which effects trigger [onEffect].
  final bool Function(E effect)? listenWhen;

  /// Child widget.
  final Widget child;

  /// Creates a [CommanderListener].
  const CommanderListener({
    super.key,
    this.commander,
    required this.onEffect,
    this.listenWhen,
    required this.child,
  });

  @override
  State<CommanderListener<C, E>> createState() =>
      _CommanderListenerState<C, E>();
}

class _CommanderListenerState<C extends Commander<dynamic, E>, E>
    extends State<CommanderListener<C, E>> {
  C? _commander;
  StreamSubscription<E>? _subscription;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(CommanderListener<C, E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.commander != oldWidget.commander) {
      _subscribe();
    } else if (widget.commander == null) {
      final current = CommanderScope.of<C>(context, listen: false);
      if (_commander != current) {
        _subscribe();
      }
    }
  }

  void _subscribe() {
    final commander =
        widget.commander ?? CommanderScope.dependOnCommander<C>(context);
    if (_commander == commander) return;

    _subscription?.cancel();
    _commander = commander;

    _subscription = _commander!.effects.listen((effect) {
      if (!mounted || !context.mounted) return;
      if (widget.listenWhen != null && !widget.listenWhen!(effect)) {
        return;
      }
      widget.onEffect(context, effect);
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
