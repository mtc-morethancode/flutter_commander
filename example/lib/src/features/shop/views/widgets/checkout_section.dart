import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';

import '../../controller/shop_controller.dart';
import '../../controller/shop_state.dart';
import '../../intents/shop_intents.dart';

/// Checkout button section showcasing [ExecutionPolicy.drop].
class CheckoutSection extends StatelessWidget {
  const CheckoutSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Checkout (ExecutionPolicy.DROP)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Double-tap prevention: subsequent taps while in-flight are instantly dropped.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            // Rebuilds only when checkout progress, items, or total changes
            CommanderSelector<ShopController, ShopState,
                (bool, int, double, double)>(
              select: (s) =>
                  (s.isCheckingOut, s.cartItemCount, s.subtotal, s.total),
              builder: (context, slice) {
                final (isCheckingOut, count, subtotal, total) = slice;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Subtotal ($count items):'),
                        Text('\$${subtotal.toStringAsFixed(2)}'),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Total (with discounts):',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '\$${total.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.green,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: count == 0 || isCheckingOut
                          ? null
                          : () {
                              context.dispatch<ShopController>(
                                  const CheckoutIntent());
                              context.dispatch<ShopController>(
                                const TrackAnalyticsIntent(
                                    'checkout_submitted'),
                              );
                            },
                      icon: isCheckingOut
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.shopping_bag_outlined),
                      label: Text(
                        isCheckingOut
                            ? 'Authorizing Payment...'
                            : (count > 0
                                ? 'Pay \$${total.toStringAsFixed(2)}'
                                : 'Cart Empty'),
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
