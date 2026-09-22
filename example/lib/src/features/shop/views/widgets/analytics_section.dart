import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';

import '../../controller/shop_commander.dart';
import '../../controller/shop_state.dart';

/// Analytics stream section showcasing [ExecutionPolicy.queue].
class AnalyticsSection extends StatelessWidget {
  const AnalyticsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'FIFO Analytics Queue (ExecutionPolicy.QUEUE)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              'Guaranteed sequential delivery without race conditions.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            // Rebuilds only when the analytics log updates
            CommanderBuilder<ShopCommander, ShopState, List<String>>(
              select: (s) => s.analyticsLog,
              builder: (context, log) {
                if (log.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      'No analytics recorded yet.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  );
                }
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: log.reversed
                        .take(5)
                        .map((entry) => Text(
                              entry,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Colors.lightGreenAccent,
                              ),
                            ))
                        .toList(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
