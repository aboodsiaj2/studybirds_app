import 'dart:developer' as developer;

/// Thin analytics stub. Logs events to the Dart developer console now;
/// replace the body of _send() with firebase_analytics calls once the
/// google-services.json / GoogleService-Info.plist is in place.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  bool _enabled = true;

  void disable() => _enabled = false;

  void logEvent(String name, {Map<String, Object>? parameters}) {
    if (!_enabled) return;
    _send(name, parameters ?? {});
  }

  void logScreen(String screenName) {
    logEvent('screen_view', parameters: {'screen_name': screenName});
  }

  void logError(String message, {Object? error, StackTrace? stack}) {
    developer.log(
      '[analytics] error: $message',
      name: 'AnalyticsService',
      error: error,
      stackTrace: stack,
    );
  }

  void _send(String name, Map<String, Object> params) {
    developer.log(
      '[analytics] $name ${params.isEmpty ? '' : params.toString()}',
      name: 'AnalyticsService',
    );
    // TODO: FirebaseAnalytics.instance.logEvent(name: name, parameters: params);
  }
}
