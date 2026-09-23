import 'package:flutter_commander/flutter_commander.dart';

import '../../../core/services/analytics_service.dart';
import '../commander/shop_effect.dart';
import '../commander/shop_state.dart';
import '../intents/shop_intents.dart';

/// Handles tracking events with [ExecutionPolicy.queue].
///
/// Guarantees chronological FIFO ordering for analytics/telemetry without
/// dropped packets or race conditions.
class TrackAnalyticsCommand
    extends Command<TrackAnalyticsIntent, ShopState, ShopEffect> {
  final AnalyticsService _analyticsService;

  TrackAnalyticsCommand(this._analyticsService);

  @override
  ExecutionPolicy get policy => ExecutionPolicy.queue;

  @override
  Future<void> execute(
    CommandScope<ShopState, ShopEffect> scope,
    TrackAnalyticsIntent intent,
  ) async {
    final entry = await _analyticsService.recordEvent(intent.event);

    scope.updateState((s) => s.copyWith(
          analyticsLog: [...s.analyticsLog, entry],
        ));
  }
}
