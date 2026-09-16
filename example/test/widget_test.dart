import 'package:flutter/material.dart';
import 'package:flutter_commander_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CommanderEnterpriseApp renders and interacts with shop features',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(const CommanderEnterpriseApp());
    await tester.pumpAndSettle();

    expect(find.text('flutter_commander Enterprise Store'), findsOneWidget);
    expect(find.text('Live Search (ExecutionPolicy.RESTART)'), findsOneWidget);
    expect(find.text('Checkout (ExecutionPolicy.DROP)'), findsOneWidget);
    expect(find.text('FIFO Analytics Queue (ExecutionPolicy.QUEUE)'), findsOneWidget);

    // Toggle VIP discount switch
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Side effect SnackBar should appear
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.text('VIP 15% discount applied!'), findsOneWidget);
  });
}
