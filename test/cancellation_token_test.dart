import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CancellationToken', () {
    test('initial state is not cancelled', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
      expect(() => token.throwIfCancelled(), returnsNormally);
    });

    test('cancel() sets isCancelled to true and throws CancellationException', () {
      final token = CancellationToken();
      token.cancel();

      expect(token.isCancelled, isTrue);
      expect(
        () => token.throwIfCancelled(),
        throwsA(isA<CancellationException>()),
      );
    });

    test('notifies registered listeners upon cancel()', () {
      final token = CancellationToken();
      var called1 = false;
      var called2 = false;

      token.onCancelled(() => called1 = true);
      token.onCancelled(() => called2 = true);

      expect(called1, isFalse);
      expect(called2, isFalse);

      token.cancel();

      expect(called1, isTrue);
      expect(called2, isTrue);
    });

    test('executes listener immediately if already cancelled', () {
      final token = CancellationToken();
      token.cancel();

      var called = false;
      token.onCancelled(() => called = true);

      expect(called, isTrue);
    });

    test('multiple cancel() calls only notify listeners once', () {
      final token = CancellationToken();
      var count = 0;
      token.onCancelled(() => count++);

      token.cancel();
      token.cancel();

      expect(count, equals(1));
    });

    test('listener errors do not prevent remaining listeners from executing', () {
      final token = CancellationToken();
      var calledSecond = false;

      token.onCancelled(() => throw Exception('Listener fail'));
      token.onCancelled(() => calledSecond = true);

      expect(() => token.cancel(), returnsNormally);
      expect(calledSecond, isTrue);
    });
  });
}
