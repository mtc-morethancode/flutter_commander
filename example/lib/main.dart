import 'package:flutter/material.dart';
import 'package:flutter_commander/flutter_commander.dart';

import 'src/core/services/analytics_service.dart';
import 'src/core/services/catalog_service.dart';
import 'src/core/services/payment_service.dart';
import 'src/features/shop/controller/shop_commander.dart';
import 'src/features/shop/views/shop_page.dart';

void main() {
  runApp(const CommanderEnterpriseApp());
}

/// Root application widget configuring themes and Commander dependency scope.
class CommanderEnterpriseApp extends StatelessWidget {
  const CommanderEnterpriseApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Instantiate core services
    final catalogService = CatalogService();
    final paymentService = PaymentService();
    final analyticsService = AnalyticsService();

    return MaterialApp(
      title: 'flutter_commander Architecture Showcase',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: CommanderScope<ShopCommander>(
        create: (context) => ShopCommander(
          catalogService: catalogService,
          paymentService: paymentService,
          analyticsService: analyticsService,
        ),
        child: const ShopPage(),
      ),
    );
  }
}
