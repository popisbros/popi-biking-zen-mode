import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';
import '../utils/app_logger.dart';
import '../utils/api_logger.dart';

/// Route type enumeration
enum RouteType {
  fastest,
  safest,
}

/// Route result containing the route points and metadata
class RouteResult {
  final RouteType type;
  final List<LatLng> points;
  final double distanceMeters;
  final int durationMillis;

  RouteResult({
    required this.type,
    required this.points,
    required this.distanceMeters,
    required this.durationMillis,
  });

  String get distanceKm => (distanceMeters / 1000).toStringAsFixed(2);
  String get durationMin => (durationMillis / 60000).toStringAsFixed(0);
}

/// Service for calculating cycling routes using Graphhopper API
class RoutingService {
  static const String _graphhopperBaseUrl = 'https://graphhopper.com/api/1';

  /// Calculate multiple routes with different profiles (fastest and safest)
  ///
  /// Returns a list of RouteResult objects, or null if all failed
  Future<List<RouteResult>?> calculateMultipleRoutes({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    if (ApiKeys.graphhopperApiKey.isEmpty) {
      AppLogger.error('Graphhopper API key not configured', tag: 'ROUTING');
      return null;
    }

    print('🚴 CALCULATING DUAL ROUTES');
    print('Start: $startLat, $startLon');
    print('End: $endLat, $endLon');

    AppLogger.api('Calculating multiple routes (fastest & safest)', data: {
      'from': '$startLat,$startLon',
      'to': '$endLat,$endLon',
    });

    // Calculate both routes in parallel
    print('⚡ Calling FASTEST route...');
    print('🛡️ Calling SAFEST route...');
    final results = await Future.wait([
      _calculateSingleRoute(
        startLat: startLat,
        startLon: startLon,
        endLat: endLat,
        endLon: endLon,
        type: RouteType.fastest,
      ),
      _calculateSingleRoute(
        startLat: startLat,
        startLon: startLon,
        endLat: endLat,
        endLon: endLon,
        type: RouteType.safest,
      ),
    ]);

    // Filter out null results
    final validRoutes = results.whereType<RouteResult>().toList();

    if (validRoutes.isEmpty) {
      AppLogger.warning('No routes found', tag: 'ROUTING');
      return null;
    }

    AppLogger.success('Calculated ${validRoutes.length} route(s)', tag: 'ROUTING');
    return validRoutes;
  }

  /// Calculate a single route with specific type
  Future<RouteResult?> _calculateSingleRoute({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
    required RouteType type,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      final response = type == RouteType.safest
          ? await _calculateWithCustomModel(
              startLat: startLat,
              startLon: startLon,
              endLat: endLat,
              endLon: endLon,
            )
          : await _calculateStandardRoute(
              startLat: startLat,
              startLon: startLon,
              endLat: endLat,
              endLon: endLon,
            );

      stopwatch.stop();

      // Get request body for logging
      String? requestBodyForLog;
      if (type == RouteType.safest) {
        final customModel = {
          "priority": [
            {"if": "road_class == CYCLEWAY", "multiply_by": 1.5},
            {"if": "road_class == PATH", "multiply_by": 1.3},
            {"if": "road_class == RESIDENTIAL", "multiply_by": 1.2},
            {"if": "road_class == TERTIARY", "multiply_by": 1.1},
            {"if": "road_class == PRIMARY", "multiply_by": 0.5},
            {"if": "road_class == TRUNK", "multiply_by": 0.3},
            {"if": "road_class == MOTORWAY", "multiply_by": 0.1},
            {"if": "bike_network != MISSING", "multiply_by": 1.3},
            {"if": "road_gradient > 10", "multiply_by": 0.8},
          ],
          "speed": [
            {"if": "road_class == PRIMARY", "limit_to": 12},
            {"if": "road_class == SECONDARY", "limit_to": 15},
          ]
        };
        requestBodyForLog = jsonEncode({
          "points": [[startLon, startLat], [endLon, endLat]],
          "profile": "bike",
          "custom_model": customModel,
        });
      }

      // Log API call to Firestore (production + debug)
      await ApiLogger.logApiCall(
        endpoint: 'graphhopper/route',
        method: 'POST',
        url: '$_graphhopperBaseUrl/route',
        parameters: {
          'start': '$startLat,$startLon',
          'end': '$endLat,$endLon',
          'profile': 'bike',
          'routeType': type.name,
          'customModel': type == RouteType.safest ? 'safest' : 'default',
          if (requestBodyForLog != null) 'requestBody': requestBodyForLog,
        },
        statusCode: response.statusCode,
        responseBody: response.body,
        error: response.statusCode != 200 ? 'HTTP ${response.statusCode}' : null,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (response.statusCode != 200) {
        AppLogger.error('Graphhopper API error for ${type.name} route', tag: 'ROUTING', data: {
          'statusCode': response.statusCode,
          'body': response.body,
        });
        // Extra debug logging for safest route
        if (type == RouteType.safest) {
          AppLogger.debug('Safest route failed with ${response.statusCode}: ${response.body}', tag: 'ROUTING');
        }
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['paths'] == null || (data['paths'] as List).isEmpty) {
        AppLogger.warning('No ${type.name} route found', tag: 'ROUTING');
        return null;
      }

      final path = (data['paths'] as List)[0] as Map<String, dynamic>;
      final points = path['points'] as Map<String, dynamic>;
      final coordinates = points['coordinates'] as List;

      final routePoints = coordinates.map((coord) {
        final coordList = coord as List;
        return LatLng(
          coordList[1] as double, // latitude
          coordList[0] as double, // longitude
        );
      }).toList();

      final distance = (path['distance'] as num).toDouble();
      final duration = (path['time'] as num).toInt();

      AppLogger.success('${type.name} route calculated', tag: 'ROUTING', data: {
        'points': routePoints.length,
        'distance': '${(distance / 1000).toStringAsFixed(2)} km',
        'duration': '${(duration / 60000).toStringAsFixed(0)} min',
      });

      return RouteResult(
        type: type,
        points: routePoints,
        distanceMeters: distance,
        durationMillis: duration,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();

      // Log error to Firestore
      await ApiLogger.logApiCall(
        endpoint: 'graphhopper/route',
        method: 'POST',
        url: 'Error before request',
        parameters: {
          'start': '$startLat,$startLon',
          'end': '$endLat,$endLon',
          'routeType': type.name,
        },
        statusCode: 0,
        responseBody: '',
        error: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );

      AppLogger.error('Failed to calculate ${type.name} route', tag: 'ROUTING', error: e, stackTrace: stackTrace);
      return null;
    }
  }

  /// Calculate standard route using POST with JSON body (uniform with custom model)
  Future<http.Response> _calculateStandardRoute({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    final uri = Uri.parse('$_graphhopperBaseUrl/route?key=${ApiKeys.graphhopperApiKey}');

    final requestBody = jsonEncode({
      "points": [
        [startLon, startLat],
        [endLon, endLat],
      ],
      "profile": "bike",
      "locale": "en",
      "points_encoded": false,
      "elevation": false,
    });

    return await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('Request timed out after 10 seconds');
      },
    );
  }

  /// Calculate route with custom model using POST with JSON body
  Future<http.Response> _calculateWithCustomModel({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    final uri = Uri.parse('$_graphhopperBaseUrl/route?key=${ApiKeys.graphhopperApiKey}');

    // Build custom model as a map (not JSON string)
    final customModel = {
      "priority": [
        // Strongly prefer dedicated cycle infrastructure
        {"if": "road_class == CYCLEWAY", "multiply_by": 1.5},
        {"if": "road_class == PATH", "multiply_by": 1.3},

        // Prefer residential and tertiary roads (quieter)
        {"if": "road_class == RESIDENTIAL", "multiply_by": 1.2},
        {"if": "road_class == TERTIARY", "multiply_by": 1.1},

        // Avoid busy roads
        {"if": "road_class == PRIMARY", "multiply_by": 0.5},
        {"if": "road_class == TRUNK", "multiply_by": 0.3},
        {"if": "road_class == MOTORWAY", "multiply_by": 0.1},

        // Prefer routes with bike lanes
        {"if": "bike_network != MISSING", "multiply_by": 1.3},

        // Slightly avoid steep hills for safety
        {"if": "road_gradient > 10", "multiply_by": 0.8},
      ],
      "speed": [
        // Reduce speed on busy roads to account for safety
        {"if": "road_class == PRIMARY", "limit_to": 12},
        {"if": "road_class == SECONDARY", "limit_to": 15},
      ]
    };

    final requestBody = jsonEncode({
      "points": [
        [startLon, startLat],
        [endLon, endLat],
      ],
      "profile": "bike",
      "locale": "en",
      "points_encoded": false,
      "elevation": false,
      "custom_model": customModel,
    });

    // Log request body for debugging (console output)
    print('🛡️ SAFEST ROUTE REQUEST:');
    print('URL: $uri');
    print('Body: $requestBody');
    AppLogger.debug('Safest route request body: $requestBody', tag: 'ROUTING');

    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw Exception('Request timed out after 10 seconds');
      },
    );

    print('🛡️ SAFEST ROUTE RESPONSE:');
    print('Status: ${response.statusCode}');
    print('Body: ${response.body.substring(0, response.body.length > 500 ? 500 : response.body.length)}');

    return response;
  }


  /// Calculate a cycling route from start to end location (legacy method)
  ///
  /// Returns a list of LatLng points representing the route, or null if failed
  Future<List<LatLng>?> calculateRoute({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    if (ApiKeys.graphhopperApiKey.isEmpty) {
      AppLogger.error('Graphhopper API key not configured', tag: 'ROUTING');
      return null;
    }

    // Build URI with multiple 'point' parameters
    final uri = Uri.parse(
      '$_graphhopperBaseUrl/route?'
      'key=${ApiKeys.graphhopperApiKey}&'
      'point=$startLat,$startLon&'
      'point=$endLat,$endLon&'
      'vehicle=bike&'
      'locale=en&'
      'points_encoded=false&'
      'elevation=false'
    );

    AppLogger.api('Calculating route', data: {
      'from': '${startLat},${startLon}',
      'to': '${endLat},${endLon}',
      'vehicle': 'bike',
    });

    final stopwatch = Stopwatch()..start();

    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timed out after 10 seconds');
        },
      );

      stopwatch.stop();

      // Log API call to Firestore (production + debug)
      await ApiLogger.logApiCall(
        endpoint: 'graphhopper/route',
        method: 'GET',
        url: uri.toString(),
        parameters: {
          'start': '$startLat,$startLon',
          'end': '$endLat,$endLon',
          'vehicle': 'bike',
          'routeType': 'fastest',
        },
        statusCode: response.statusCode,
        responseBody: response.body,
        error: response.statusCode != 200 ? 'HTTP ${response.statusCode}' : null,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (response.statusCode != 200) {
        AppLogger.error('Graphhopper API error', tag: 'ROUTING', data: {
          'statusCode': response.statusCode,
          'body': response.body,
        });
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;

      if (data['paths'] == null || (data['paths'] as List).isEmpty) {
        AppLogger.warning('No route found', tag: 'ROUTING');
        return null;
      }

      final path = (data['paths'] as List)[0] as Map<String, dynamic>;
      final points = path['points'] as Map<String, dynamic>;
      final coordinates = points['coordinates'] as List;

      // Convert coordinates to LatLng list
      // Graphhopper returns coordinates as [longitude, latitude, elevation]
      final routePoints = coordinates.map((coord) {
        final coordList = coord as List;
        return LatLng(
          coordList[1] as double, // latitude
          coordList[0] as double, // longitude
        );
      }).toList();

      final distance = path['distance'] as num;
      final duration = path['time'] as num;

      AppLogger.success('Route calculated', tag: 'ROUTING', data: {
        'points': routePoints.length,
        'distance': '${(distance / 1000).toStringAsFixed(2)} km',
        'duration': '${(duration / 60000).toStringAsFixed(0)} min',
      });

      return routePoints;
    } catch (e, stackTrace) {
      stopwatch.stop();

      // Log error to Firestore
      await ApiLogger.logApiCall(
        endpoint: 'graphhopper/route',
        method: 'GET',
        url: 'Error before request',
        parameters: {
          'start': '$startLat,$startLon',
          'end': '$endLat,$endLon',
        },
        statusCode: 0,
        responseBody: '',
        error: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );

      AppLogger.error('Failed to calculate route', tag: 'ROUTING', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
