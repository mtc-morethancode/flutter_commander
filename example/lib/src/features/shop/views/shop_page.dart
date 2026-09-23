import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';

import '../commander/shop_commander.dart';
import '../commander/shop_effect.dart';
import '../commander/shop_state.dart';
import 'widgets/analytics_section.dart';
import 'widgets/checkout_section.dart';
import 'widgets/search_section.dart';
import 'widgets/vip_discount_section.dart';

/// Main screen for the Shop feature.
class ShopPage extends StatelessWidget {
  const ShopPage({super.key});

  @override
  Widget build(BuildContext context) {
    return CommanderListener<ShopCommander, ShopEffect>(
      onEffect: (context, effect) {
        switch (effect) {
          case ShowSnackbarEffect(:final message):
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );

          case OrderConfirmedEffect(:final confirmation):
            showDialog<void>(
              context: context,
              builder: (dialogCtx) => AlertDialog(
                icon: const Icon(Icons.check_circle,
                    color: Colors.green, size: 48),
                title: const Text('Order Confirmed!'),
                content: Text(
                  'Order #${confirmation.orderId} was processed for '
                  '\$${confirmation.totalAmount.toStringAsFixed(2)}.',
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Navigator.of(dialogCtx).pop(),
                    child: const Text('Great!'),
                  ),
                ],
              ),
            );
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('flutter_commander Enterprise Store'),
          actions: [
            Builder(
              builder: (context) {
                // Sliced subscription via context.select: rebuilds ONLY when count changes
                final cartCount = context.select<ShopCommander, ShopState, int>(
                  (s) => s.cartItemCount,
                );
                return Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Badge(
                    label: Text('$cartCount'),
                    isLabelVisible: cartCount > 0,
                    child: const Icon(Icons.shopping_cart_outlined),
                  ),
                );
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: const [
            SearchSection(),
            SizedBox(height: 16),
            VipDiscountSection(),
            SizedBox(height: 16),
            CheckoutSection(),
            SizedBox(height: 16),
            AnalyticsSection(),
          ],
        ),
      ),
    );
  }
}
