import 'dart:async';

/// User action tracking for debugging
class UserAction {
  final DateTime timestamp;
  final String action;
  final String? screen;
  final Map<String, dynamic>? parameters;
  final String? result;
  final String? error;

  UserAction({
    required this.timestamp,
    required this.action,
    this.screen,
    this.parameters,
    this.result,
    this.error,
  });

  @override
  String toString() {
    return 'UserAction(timestamp: $timestamp, action: $action, screen: $screen, parameters: $parameters, result: $result, error: $error)';
  }
}

/// Debug service for tracking user actions and app state
class DebugService {
  static final DebugService _instance = DebugService._internal();
  factory DebugService() => _instance;
  DebugService._internal();

  final List<UserAction> _actions = [];
  final StreamController<List<UserAction>> _actionsController = 
      StreamController<List<UserAction>>.broadcast();

  /// Stream of user actions
  Stream<List<UserAction>> get actionsStream => _actionsController.stream;

  /// Get all actions
  List<UserAction> get actions => List.unmodifiable(_actions);

  /// Log a user action
  void logAction({
    required String action,
    String? screen,
    Map<String, dynamic>? parameters,
    String? result,
    String? error,
  }) {
    final userAction = UserAction(
      timestamp: DateTime.now(),
      action: action,
      screen: screen,
      parameters: parameters,
      result: result,
      error: error,
    );

    _actions.insert(0, userAction); // Add to beginning for newest first

    // Keep only last 100 actions to prevent memory issues
    if (_actions.length > 100) {
      _actions.removeRange(100, _actions.length);
    }

    _actionsController.add(_actions);
    
    // Also print to console for immediate debugging
    print('DebugService.logAction: $userAction');
  }

  /// Log a button click
  void logButtonClick(String buttonName, {String? screen, Map<String, dynamic>? parameters}) {
    logAction(
      action: 'Button Click: $buttonName',
      screen: screen,
      parameters: parameters,
    );
  }

  /// Log navigation
  void logNavigation(String fromScreen, String toScreen, {Map<String, dynamic>? parameters}) {
    logAction(
      action: 'Navigation: $fromScreen → $toScreen',
      screen: fromScreen,
      parameters: parameters,
    );
  }

  /// Log function call
  void logFunctionCall(String functionName, {String? screen, Map<String, dynamic>? parameters, String? result, String? error}) {
    logAction(
      action: 'Function Call: $functionName',
      screen: screen,
      parameters: parameters,
      result: result,
      error: error,
    );
  }

  /// Log API call
  void logApiCall(String endpoint, {String? method, Map<String, dynamic>? parameters, String? result, String? error}) {
    logAction(
      action: 'API Call: $method $endpoint',
      parameters: {
        'endpoint': endpoint,
        'method': method,
        ...?parameters,
      },
      result: result,
      error: error,
    );
  }

  /// Log state change
  void logStateChange(String stateName, dynamic oldValue, dynamic newValue, {String? screen}) {
    logAction(
      action: 'State Change: $stateName',
      screen: screen,
      parameters: {
        'oldValue': oldValue?.toString(),
        'newValue': newValue?.toString(),
      },
    );
  }

  /// Clear all actions
  void clearActions() {
    _actions.clear();
    _actionsController.add(_actions);
  }

  /// Dispose
  void dispose() {
    _actionsController.close();
  }
}
