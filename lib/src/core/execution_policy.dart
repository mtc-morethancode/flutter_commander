// ignore_for_file: constant_identifier_names

/// Defines how a [Command] handles concurrent or rapid successive invocations.
enum ExecutionPolicy {
  /// If the command is currently running, incoming intents of this type
  /// are immediately dropped and ignored.
  ///
  /// Ideal for double-tap prevention, checkout buttons, and form submissions.
  drop,

  /// If the command is currently running, the active execution is cancelled
  /// (via collaborative [CancellationToken]) and the new intent starts immediately.
  ///
  /// Ideal for search type-ahead, filters, and autocomplete.
  restart,

  /// Invocations are placed into a FIFO queue and executed sequentially one by one.
  ///
  /// Ideal for transactional operations, event logging, and sequential sync tasks.
  queue,

  /// Invocations execute concurrently in parallel without blocking or dropping.
  ///
  /// Ideal for independent reads or fire-and-forget operations.
  concurrent;

  /// Uppercase alias for [ExecutionPolicy.drop].
  static const ExecutionPolicy DROP = ExecutionPolicy.drop;

  /// Uppercase alias for [ExecutionPolicy.restart].
  static const ExecutionPolicy RESTART = ExecutionPolicy.restart;

  /// Uppercase alias for [ExecutionPolicy.queue].
  static const ExecutionPolicy QUEUE = ExecutionPolicy.queue;

  /// Uppercase alias for [ExecutionPolicy.concurrent].
  static const ExecutionPolicy CONCURRENT = ExecutionPolicy.concurrent;
}
