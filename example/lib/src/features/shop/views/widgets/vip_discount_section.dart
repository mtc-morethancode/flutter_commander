import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';

import '../../controller/shop_commander.dart';
import '../../controller/shop_state.dart';
import '../../intents/shop_intents.dart';

/// Inline DSL demonstration section.
class VipDiscountSection extends StatelessWidget {
  const VipDiscountSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Inline DSL (on<ToggleVipDiscountIntent>)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Quick UI action without creating a separate class file.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            CommanderSelector<ShopCommander, ShopState, bool>(
              select: (s) => s.hasVipDiscount,
              builder: (context, hasDiscount) {
                return Switch(
                  value: hasDiscount,
                  onChanged: (_) {
                    context.dispatch<ShopCommander>(
                        const ToggleVipDiscountIntent());
                    context.dispatch<ShopCommander>(
                      TrackAnalyticsIntent('vip_toggle:$hasDiscount'),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
