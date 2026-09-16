/// Simulated analytics logging service.
class AnalyticsService {
  /// Sends an event sequentially to the ingestion backend.
  Future<String> recordEvent(String eventName) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    final now = DateTime.now();
    return '[${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}] $eventName';
  }
}
