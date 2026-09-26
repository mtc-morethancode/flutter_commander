# Two-Tier Testing Guide (`commanderTest` & `TestCommandScope`) 🧪

Testing in `flutter_commander` is designed around zero flakiness, fast execution, and strict determinism. The framework provides a two-tier testing suite from `package:flutter_commander/testing.dart`:

1. **Tier 1 (Declarative Orchestrator Testing):** `commanderTest` for end-to-end integration contracts.
2. **Tier 2 (Atomic Command Testing):** `TestCommandScope` for isolated, synchronous unit tests.

---

## 1. Orchestrator Testing (`commanderTest`)

For declarative, end-to-end unit testing of `Commander` instances with state sequences, side-effects, seeding, debounce waits, and mock verification:

```dart
import 'package:flutter_commander/testing.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MockPaymentService mockPaymentService;

  setUp(() {
    mockPaymentService = MockPaymentService();
  });

  commanderTest<CartCommander, CartState, CartEffect>(
    'emits checkout state and OrderConfirmedEffect on checkout',
    build: () => CartCommander(paymentService: mockPaymentService),
    seed: () => const CartState(items: ['MacBook Pro']),
    act: (commander) => commander.dispatch(const CheckoutIntent()),
    expectStates: () => [
      const CartState(items: ['MacBook Pro'], isCheckingOut: true),
      const CartState(items: [], isCheckingOut: false),
    ],
    expectEffects: () => [
      const OrderConfirmedEffect('ORD-777'),
    ],
    verify: (commander) {
      verify(() => mockPaymentService.pay(any())).called(1);
    },
  );
}
```

### Key Parameters of `commanderTest`:

* `build`: Factory to instantiate the commander under test with injected mocks or fakes.
* `seed`: Optional state to prime the commander with prior to executing `act`.
* `act`: The action to perform (e.g. `commander.dispatch(intent)`).
* `wait`: Optional `Duration` to wait for debounced or asynchronous operations before running assertions.
* `skip`: Number of emitted states to skip before asserting against `expectStates`.
* `expectStates`: Function returning the expected list of state transitions (or `expect` alias).
* `expectEffects`: Function returning the expected list of emitted one-shot side effects.
* `errors`: Function returning the expected list of thrown exceptions if testing error boundaries.
* `verify`: Post-execution callback for mock verification (e.g. `verify(() => mock.call()).called(1)`).

---

## 2. Atomic Command Testing (`TestCommandScope`)

For isolated, widget-free, stream-free testing of individual `Command` units with zero timers and synchronous execution:

```dart
test('CheckoutCommand processes payment, clears cart and emits confirmation', () async {
  final fakePayment = FakePaymentService(mockOrderId: 'ORD-777');
  final command = CheckoutCommand(fakePayment);

  // Initialize test harness with 2 items in cart
  final testScope = TestCommandScope<CartState, CartEffect>(
    const CartState(items: ['MacBook Pro', 'Mouse']),
  );

  // Execute the command directly:
  await command.execute(testScope, const CheckoutIntent());

  // 1. Verify chronological state transitions:
  expect(testScope.states, [
    const CartState(items: ['MacBook Pro', 'Mouse'], isCheckingOut: true),
    const CartState(items: [], isCheckingOut: false),
  ]);

  // 2. Verify emitted one-shot side effects:
  expect(testScope.effects, [
    const OrderConfirmedEffect('ORD-777'),
  ]);
});
```

### Benefits of `TestCommandScope`:
* **Synchronous & Linear**: No streams, no microtask queues, and no async delays.
* **Inspectable Properties**: `testScope.states` holds all recorded state emissions; `testScope.effects` holds all side effects.
* **Cancellation Testing**: Inspect `testScope.cancellationToken.isCancelled` directly to test cooperative cancellation.
