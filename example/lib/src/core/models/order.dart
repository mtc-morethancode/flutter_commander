/// Order confirmation model emitted upon successful checkout.
class OrderConfirmation {
  final String orderId;
  final double totalAmount;
  final DateTime timestamp;

  const OrderConfirmation({
    required this.orderId,
    required this.totalAmount,
    required this.timestamp,
  });

  @override
  String toString() => 'OrderConfirmation(#$orderId, \$$totalAmount)';
}
