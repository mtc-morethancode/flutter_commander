/// Enterprise MVI + Command Pattern architecture for Flutter with declarative
/// concurrency, strict decoupling, one-shot side effects, and zero code-gen.
library;

// Core
export 'src/core/cancellation_token.dart';
export 'src/core/command.dart';
export 'src/core/command_interceptor.dart';
export 'src/core/command_scope.dart';
export 'src/core/commander_observer.dart';
export 'src/core/execution_policy.dart';
export 'src/core/intent.dart';
export 'src/core/logging_interceptor.dart';

// Commander
export 'src/commander/commander.dart';

// Widgets
export 'src/widgets/commander_builder.dart';
export 'src/widgets/commander_extensions.dart';
export 'src/widgets/commander_listener.dart';
export 'src/widgets/commander_scope.dart';
export 'src/widgets/commander_selector.dart';
export 'src/widgets/commander_state_builder.dart';
export 'src/widgets/commander_view.dart';

// Testing
export 'src/testing/test_command_scope.dart';
