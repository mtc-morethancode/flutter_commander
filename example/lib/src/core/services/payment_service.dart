import '../models/order.dart';

/// Simulated payment gateway service.
class PaymentService {
  /// Processes order checkout with simulated network latency.
  Future<OrderConfirmation> processPayment({required double amount}) async {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    final orderId = 'ORD-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';

    return OrderConfirmation(
      orderId: orderId,
      totalAmount: amount,
      timestamp: DateTime.now(),
    );
  }
}
