/// Enterprise MVI + Command Pattern architecture for Flutter with declarative
/// concurrency, strict decoupling, one-shot side effects, and zero code-gen.
library;

// Core
export 'src/core/cancellation_token.dart';
export 'src/core/command.dart';
export 'src/core/command_interceptor.dart';
export 'src/core/command_scope.dart';
export 'src/core/execution_policy.dart';
export 'src/core/intent.dart';
export 'src/core/logging_interceptor.dart';

// Controller
export 'src/controller/commander_controller.dart';

// Widgets
export 'src/widgets/commander_builder.dart';
export 'src/widgets/commander_consumer.dart';
export 'src/widgets/commander_extensions.dart';
export 'src/widgets/commander_listener.dart';
export 'src/widgets/commander_scope.dart';

// Testing
export 'src/testing/test_command_scope.dart';
