import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../commander/commander.dart';
import '../core/intent.dart';
import 'commander_scope.dart';

/// A clean, declarative base widget for building full screens and features in `flutter_commander`.
///
/// [CommanderView] eliminates the need for nesting builder, listener, or consumer widgets.
/// It automatically:
/// 1. Resolves the nearest [Commander] of type [C] from [CommanderScope] (or uses an explicitly provided [commander]).
/// 2. Subscribes to one-shot [E] side-effects and invokes [onEffect] without triggering UI rebuilds.
/// 3. Rebuilds reactively when [S] state changes, passing the latest state directly to [build].
/// 4. Provides convenient [dispatch] and [commanderOf] helper methods.
///
/// ### Example:
/// ```dart
/// class CartPage extends CommanderView<CartCommander, CartState, CartEffect> {
///   const CartPage({super.key, super.commander});
///
///   @override
///   void onEffect(BuildContext context, CartEffect effect) {
///     switch (effect) {
///       case ShowToastEffect(:final message):
///         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
///       case NavigateToCheckoutEffect():
///         Navigator.of(context).pushNamed('/checkout');
///     }
///   }
///
///   @override
///   Widget build(BuildContext context, CartState state) {
///     return Scaffold(
///       appBar: AppBar(title: Text('Cart (${state.itemCount})')),
///       body: DumbProductList(items: state.items),
///       floatingActionButton: FloatingActionButton(
///         onPressed: () => dispatch(context, const CheckoutIntent()),
///         child: const Icon(Icons.payment),
///       ),
///     );
///   }
/// }
/// ```
abstract class CommanderView<C extends Commander<S, E>, S, E>
    extends StatefulWidget {
  /// Optional explicit [commander] instance.
  /// If omitted, resolved from the nearest [CommanderScope] in the widget tree.
  final C? commander;

  /// Creates a [CommanderView].
  const CommanderView({super.key, this.commander});

  /// Builds the widget tree given the current [context] and [state].
  Widget build(BuildContext context, S state);

  /// Callback executed whenever a one-shot side [effect] is emitted by the [Commander].
  ///
  /// This execution is purely imperative and does NOT trigger a widget rebuild.
  /// It is guaranteed to only be invoked when the widget is actively mounted in the tree (`mounted == true`).
  void onEffect(BuildContext context, E effect) {}

  /// Optional filter to condition which effects trigger [onEffect].
  ///
  /// Defaults to returning `true` for all effects.
  bool listenWhen(E effect) => true;

  /// Optional condition to control whether this view should rebuild when the commander's state changes.
  ///
  /// Defaults to checking value inequality (`previous != current`).
  ///
  /// Override this method to selectively ignore specific state mutations:
  /// ```dart
  /// @override
  /// bool shouldRebuild(CartState previous, CartState current) {
  ///   return previous.items != current.items;
  /// }
  /// ```
  bool shouldRebuild(S previous, S current) =>
      !identical(previous, current) && previous != current;

  /// Dispatches a [CommandIntent] to the bound [Commander].
  ///
  /// Resolves the commander from [commander] or from [context] via [CommanderScope].
  Future<void> dispatch(BuildContext context, CommandIntent intent) {
    return commanderOf(context).dispatch(intent);
  }

  /// Obtains the bound [Commander] from [commander] or [CommanderScope].
  C commanderOf(BuildContext context) {
    return commander ?? CommanderScope.of<C>(context, listen: false);
  }

  @override
  State<CommanderView<C, S, E>> createState() => _CommanderViewState<C, S, E>();
}

class _CommanderViewState<C extends Commander<S, E>, S, E>
    extends State<CommanderView<C, S, E>> {
  C? _commander;
  StreamSubscription<E>? _effectSubscription;
  late S _currentState;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _subscribe();
  }

  @override
  void didUpdateWidget(CommanderView<C, S, E> oldWidget) {
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

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(fn);
        }
      });
    } else {
      setState(fn);
    }
  }

  void _subscribe() {
    final commander =
        widget.commander ?? CommanderScope.dependOnCommander<C>(context);
    if (_commander == commander) return;

    final isInitial = _commander == null;
    _unsubscribe();
    _commander = commander;
    _currentState = commander.state;

    commander.addListener(_onStateChanged);
    _effectSubscription = commander.effects.listen(_onEffect);
    if (!isInitial && mounted) {
      _safeSetState(() {});
    }
  }

  void _onStateChanged() {
    final commander = _commander;
    if (commander == null) return;

    final newState = commander.state;
    final shouldRebuild = widget.shouldRebuild(_currentState, newState);
    _currentState = newState;

    if (shouldRebuild && mounted) {
      _safeSetState(() {});
    }
  }

  void _onEffect(E effect) {
    if (!mounted || !context.mounted) return;
    if (widget.listenWhen(effect)) {
      widget.onEffect(context, effect);
    }
  }

  void _unsubscribe() {
    _commander?.removeListener(_onStateChanged);
    _effectSubscription?.cancel();
    _effectSubscription = null;
    _commander = null;
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_commander != null) {
      _currentState = _commander!.state;
    }
    return widget.build(context, _currentState);
  }
}
