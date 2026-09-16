import 'package:flutter_commander/flutter_commander.dart';

import '../../../core/services/payment_service.dart';
import '../controller/shop_effect.dart';
import '../controller/shop_state.dart';
import '../intents/shop_intents.dart';

/// Handles order checkout with [ExecutionPolicy.drop].
///
/// Prevents concurrent double-taps while payment authorization is pending.
/// Any additional taps while this command executes are discarded immediately.
class CheckoutCommand extends Command<CheckoutIntent, ShopState, ShopEffect> {
  final PaymentService _paymentService;

  CheckoutCommand(this._paymentService);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.drop;

  @override
  Future<void> execute(
    CommandScope<ShopState, ShopEffect> scope,
    CheckoutIntent intent,
  ) async {
    if (scope.state.cartItemCount == 0 || scope.state.isCheckingOut) {
      return;
    }

    scope.updateState((s) => s.copyWith(isCheckingOut: true));

    try {
      final total = scope.state.total;
      final confirmation = await _paymentService.processPayment(amount: total);

      scope.updateState((s) => s.copyWith(
            isCheckingOut: false,
            cartItemCount: 0,
          ));

      scope.emitSideEffect(OrderConfirmedEffect(confirmation));
    } catch (e) {
      scope.updateState((s) => s.copyWith(isCheckingOut: false));
      scope.emitSideEffect(ShowSnackbarEffect('Checkout failed: $e'));
    }
  }
}
