import '../../../core/models/order.dart';

/// Sealed hierarchy of one-shot side effects for the Shop feature.
///
/// Handled by UI listeners (navigation, alerts, snackbars) without polluting
/// persistent widget state.
sealed class ShopEffect {
  const ShopEffect();
}

/// Dispatched to display an informative snackbar or toast.
final class ShowSnackbarEffect extends ShopEffect {
  final String message;
  const ShowSnackbarEffect(this.message);
}

/// Dispatched when payment completes to navigate to confirmation dialog/screen.
final class OrderConfirmedEffect extends ShopEffect {
  final OrderConfirmation confirmation;
  const OrderConfirmedEffect(this.confirmation);
}
