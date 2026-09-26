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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ShowSnackbarEffect &&
          runtimeType == other.runtimeType &&
          message == other.message;

  @override
  int get hashCode => message.hashCode;

  @override
  String toString() => 'ShowSnackbarEffect($message)';
}

/// Dispatched when payment completes to navigate to confirmation dialog/screen.
final class OrderConfirmedEffect extends ShopEffect {
  final OrderConfirmation confirmation;
  const OrderConfirmedEffect(this.confirmation);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrderConfirmedEffect &&
          runtimeType == other.runtimeType &&
          confirmation == other.confirmation;

  @override
  int get hashCode => confirmation.hashCode;

  @override
  String toString() => 'OrderConfirmedEffect(${confirmation.orderId})';
}
