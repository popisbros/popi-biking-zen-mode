
class OSMDebugInfo {
  final DateTime timestamp;
  final String url;
  final Map<String, dynamic> parameters;
  final String query;
  final int? responseStatusCode;
  final String? responseBody;
  final String? error;
  final Duration? duration;

  OSMDebugInfo({
    required this.timestamp,
    required this.url,
    required this.parameters,
    required this.query,
    this.responseStatusCode,
    this.responseBody,
    this.error,
    this.duration,
  });

  Map<String, dynamic> toMap() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'url': url,
      'parameters': parameters,
      'query': query,
      'responseStatusCode': responseStatusCode,
      'responseBody': responseBody,
      'error': error,
      'duration': duration?.inMilliseconds,
    };
  }
}

class OSMDebugService {
  static final OSMDebugService _instance = OSMDebugService._internal();
  factory OSMDebugService() => _instance;
  OSMDebugService._internal();

  final List<OSMDebugInfo> _debugLogs = [];
  bool _showDebugWindow = false;

  List<OSMDebugInfo> get debugLogs => List.unmodifiable(_debugLogs);
  bool get showDebugWindow => _showDebugWindow;

  void toggleDebugWindow() {
    _showDebugWindow = !_showDebugWindow;
  }

  void addDebugInfo(OSMDebugInfo info) {
    _debugLogs.insert(0, info); // Add to beginning for newest first
    // Keep only last 50 entries to prevent memory issues
    if (_debugLogs.length > 50) {
      _debugLogs.removeRange(50, _debugLogs.length);
    }
  }

  void clearDebugLogs() {
    _debugLogs.clear();
  }

  void logOSMRequest({
    required String url,
    required Map<String, dynamic> parameters,
    required String query,
  }) {
    final info = OSMDebugInfo(
      timestamp: DateTime.now(),
      url: url,
      parameters: parameters,
      query: query,
    );
    addDebugInfo(info);
  }

  void logOSMResponse({
    required String url,
    required Map<String, dynamic> parameters,
    required String query,
    required int statusCode,
    required String responseBody,
    required Duration duration,
  }) {
    final info = OSMDebugInfo(
      timestamp: DateTime.now(),
      url: url,
      parameters: parameters,
      query: query,
      responseStatusCode: statusCode,
      responseBody: responseBody,
      duration: duration,
    );
    addDebugInfo(info);
  }

  void logOSMError({
    required String url,
    required Map<String, dynamic> parameters,
    required String query,
    required String error,
    Duration? duration,
  }) {
    final info = OSMDebugInfo(
      timestamp: DateTime.now(),
      url: url,
      parameters: parameters,
      query: query,
      error: error,
      duration: duration,
    );
    addDebugInfo(info);
  }
}
