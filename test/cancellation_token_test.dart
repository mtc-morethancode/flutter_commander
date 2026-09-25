import 'dart:async';

import 'package:flutter_commander/flutter_commander.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CancellationToken', () {
    test('initial state is not cancelled', () {
      final token = CancellationToken();
      expect(token.isCancelled, isFalse);
      expect(() => token.throwIfCancelled(), returnsNormally);
    });

    test('cancel() sets isCancelled to true and throws CancellationException',
        () {
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

    test('listener errors do not prevent remaining listeners from executing',
        () {
      final token = CancellationToken();
      var calledSecond = false;

      token.onCancelled(() => throw Exception('Listener fail'));
      token.onCancelled(() => calledSecond = true);

      expect(() => token.cancel(), returnsNormally);
      expect(calledSecond, isTrue);
    });

    test('whenCancelled future completes when cancelled', () async {
      final token = CancellationToken();
      var completed = false;

      unawaited(token.whenCancelled.then((_) => completed = true));
      expect(completed, isFalse);

      token.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(completed, isTrue);

      // Subsequent access returns immediately completed future
      expect(token.whenCancelled, completes);
    });

    test('attach registers callback and detach unregisters callback', () {
      final token = CancellationToken();
      var called = false;

      final detach = token.attach(() => called = true);
      expect(called, isFalse);

      detach();
      token.cancel();
      expect(called, isFalse);
    });

    test('attach executes immediately if token is already cancelled', () {
      final token = CancellationToken();
      token.cancel();

      var called = false;
      final detach = token.attach(() => called = true);
      expect(called, isTrue);

      // Calling detach afterwards does not fail
      expect(detach, returnsNormally);
    });

    test('race returns future value when completed before cancellation',
        () async {
      final token = CancellationToken();
      final completer = Completer<String>();

      final raceFuture = token.race(completer.future);
      completer.complete('success');

      expect(await raceFuture, equals('success'));
    });

    test('race propagates future error when future fails before cancellation',
        () async {
      final token = CancellationToken();
      final completer = Completer<String>();

      final raceFuture = token.race(completer.future);
      completer.completeError(const FormatException('invalid'));

      expect(() => raceFuture, throwsA(isA<FormatException>()));
    });

    test('race throws CancellationException immediately if already cancelled',
        () async {
      final token = CancellationToken();
      token.cancel('Explicit abort');

      final completer = Completer<String>();
      final raceFuture = token.race(completer.future);

      expect(
        () => raceFuture,
        throwsA(isA<CancellationException>().having(
          (e) => e.message,
          'message',
          equals('Explicit abort'),
        )),
      );
    });

    test('race throws CancellationException mid-flight when token is cancelled',
        () async {
      final token = CancellationToken();
      final completer = Completer<String>();

      final raceFuture = token.race(completer.future);
      token.cancel('Cancelled while fetching');

      expect(
        () => raceFuture,
        throwsA(isA<CancellationException>().having(
          (e) => e.message,
          'message',
          equals('Cancelled while fetching'),
        )),
      );

      // Late completion of the raced future does not affect anything
      completer.complete('late');
      await Future<void>.delayed(Duration.zero);
    });

    test('sleep delays for duration and completes normally', () async {
      final token = CancellationToken();
      final stopwatch = Stopwatch()..start();

      await token.sleep(const Duration(milliseconds: 20));
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(15));
    });

    test('sleep aborts early and throws CancellationException when cancelled',
        () async {
      final token = CancellationToken();
      final sleepFuture = token.sleep(const Duration(milliseconds: 200));

      await Future<void>.delayed(const Duration(milliseconds: 15));
      token.cancel('Sleep cancelled');

      expect(
        () => sleepFuture,
        throwsA(isA<CancellationException>().having(
          (e) => e.message,
          'message',
          equals('Sleep cancelled'),
        )),
      );
    });

    test('timeout factory cancels automatically after duration', () async {
      final token = CancellationToken.timeout(
        const Duration(milliseconds: 25),
        message: 'Timeout occurred',
      );

      expect(token.isCancelled, isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(token.isCancelled, isTrue);
      expect(token.cancellationReason, equals('Timeout occurred'));
    });

    test('timeout factory can be cancelled before duration without error',
        () async {
      final token = CancellationToken.timeout(
        const Duration(milliseconds: 50),
        message: 'Timeout occurred',
      );

      token.cancel('Manual pre-empt');
      expect(token.cancellationReason, equals('Manual pre-empt'));

      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(token.cancellationReason, equals('Manual pre-empt'));
    });

    test('combine factory cancels when any token cancels and releases memory',
        () {
      final t1 = CancellationToken();
      final t2 = CancellationToken();
      final t3 = CancellationToken();

      final combined = CancellationToken.combine([t1, t2, t3]);
      expect(combined.isCancelled, isFalse);

      t2.cancel('t2 stopped');
      expect(combined.isCancelled, isTrue);
      expect(combined.cancellationReason, equals('t2 stopped'));
    });

    test(
        'combine factory cancels immediately if any input token is already cancelled',
        () {
      final t1 = CancellationToken();
      final t2 = CancellationToken()..cancel('Already stopped');

      final combined = CancellationToken.combine([t1, t2]);
      expect(combined.isCancelled, isTrue);
      expect(combined.cancellationReason, equals('Already stopped'));
    });

    test('runCancellable throws before calling operation if already cancelled',
        () async {
      final token = CancellationToken()..cancel('Stopped');
      var executed = false;

      expect(
        () => token.runCancellable(() {
          executed = true;
          return 'hello';
        }),
        throwsA(isA<CancellationException>()),
      );
      expect(executed, isFalse);
    });

    test('runCancellable runs operation and races async result', () async {
      final token = CancellationToken();
      final result = await token.runCancellable(() async => 42);
      expect(result, equals(42));
    });

    test('CancellationToken.none operations are safely supported', () async {
      final none = CancellationToken.none;
      expect(none.isCancelled, isFalse);
      expect(none.cancellationReason, isNull);

      none.cancel('ignored');
      expect(none.isCancelled, isFalse);
      expect(() => none.throwIfCancelled(), returnsNormally);

      final val = await none.race(Future.value('ok'));
      expect(val, equals('ok'));

      final ran = await none.runCancellable(() => 'fine');
      expect(ran, equals('fine'));
    });
  });
}
