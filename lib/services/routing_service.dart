import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';
import '../utils/app_logger.dart';
import '../utils/api_logger.dart';
import 'route_hazard_detector.dart';

/// Route type enumeration
enum RouteType {
  fastest,
  safest,
  shortest, // Car route (testing)
}

/// Route result containing the route points and metadata
class RouteResult {
  final RouteType type;
  final List<LatLng> points;
  final double distanceMeters;
  final int durationMillis;
  final List<RouteInstruction>? instructions; // GraphHopper turn-by-turn instructions
  final Map<String, dynamic>? pathDetails; // Path details (lanes, street names, etc)
  final List<RouteHazard>? routeHazards; // Community hazards on or near this route

  RouteResult({
    required this.type,
    required this.points,
    required this.distanceMeters,
    required this.durationMillis,
    this.instructions,
    this.pathDetails,
    this.routeHazards,
  });

  String get distanceKm => (distanceMeters / 1000).toStringAsFixed(2);
  String get durationMin => (durationMillis / 60000).toStringAsFixed(0);

  /// Create a copy with updated hazards
  RouteResult copyWithHazards(List<RouteHazard> hazards) {
    return RouteResult(
      type: type,
      points: points,
      distanceMeters: distanceMeters,
      durationMillis: durationMillis,
      instructions: instructions,
      pathDetails: pathDetails,
      routeHazards: hazards,
    );
  }
}

/// GraphHopper turn-by-turn instruction
class RouteInstruction {
  final double distance; // Distance for this instruction in meters
  final int sign; // Turn direction sign (-7 to 7)
  final List<int> interval; // [start_index, end_index] in route points
  final String text; // Human readable instruction
  final int time; // Time for this segment in milliseconds
  final String? streetName; // Street name (if available)
  final String? streetDestination; // Destination info from OSM
  final String? streetRef; // Street reference (e.g., "A1")

  RouteInstruction({
    required this.distance,
    required this.sign,
    required this.interval,
    required this.text,
    required this.time,
    this.streetName,
    this.streetDestination,
    this.streetRef,
  });

  factory RouteInstruction.fromJson(Map<String, dynamic> json) {
    return RouteInstruction(
      distance: (json['distance'] as num).toDouble(),
      sign: json['sign'] as int,
      interval: (json['interval'] as List).cast<int>(),
      text: json['text'] as String,
      time: json['time'] as int,
      streetName: json['street_name'] as String?,
      streetDestination: json['street_destination'] as String?,
      streetRef: json['street_ref'] as String?,
    );
  }
}

/// Service for calculating cycling routes using Graphhopper API
class RoutingService {
  static const String _graphhopperBaseUrl = 'https://graphhopper.com/api/1';

  /// Calculate multiple routes with different profiles (fastest, safest, shortest)
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

    AppLogger.api('Calculating multiple routes (fastest, safest, shortest)', data: {
      'from': '$startLat,$startLon',
      'to': '$endLat,$endLon',
    });

    // Calculate all three routes in parallel
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
      _calculateSingleRoute(
        startLat: startLat,
        startLon: startLon,
        endLat: endLat,
        endLon: endLon,
        type: RouteType.shortest,
      ),
    ]);

    // Filter out null results
    final validRoutes = results.whereType<RouteResult>().toList();

    if (validRoutes.isEmpty) {
      AppLogger.warning('No routes found', tag: 'ROUTING');
      return null;
    }

    AppLogger.success('Calculated ${validRoutes.length} route(s)', tag: 'ROUTING', data: {
      'types': validRoutes.map((r) => r.type.name).join(', '),
    });
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
          : type == RouteType.shortest
              ? await _calculateShortestRoute(
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

      // Parse instructions if available
      List<RouteInstruction>? instructions;
      if (path['instructions'] != null) {
        final instructionsList = path['instructions'] as List;
        instructions = instructionsList.map((inst) => RouteInstruction.fromJson(inst as Map<String, dynamic>)).toList();
        AppLogger.debug('Parsed ${instructions.length} instructions', tag: 'ROUTING');
      }

      // Extract path details if available
      Map<String, dynamic>? pathDetails;
      if (path['details'] != null) {
        pathDetails = path['details'] as Map<String, dynamic>;
        AppLogger.debug('Path details available: ${pathDetails.keys.join(", ")}', tag: 'ROUTING');
      }

      AppLogger.success('${type.name} route calculated', tag: 'ROUTING', data: {
        'points': routePoints.length,
        'distance': '${(distance / 1000).toStringAsFixed(2)} km',
        'duration': '${(duration / 60000).toStringAsFixed(0)} min',
        'instructions': instructions?.length ?? 0,
        'details': pathDetails?.keys.length ?? 0,
      });

      return RouteResult(
        type: type,
        points: routePoints,
        distanceMeters: distance,
        durationMillis: duration,
        instructions: instructions,
        pathDetails: pathDetails,
      );
    } catch (e, stackTrace) {
      stopwatch.stop();

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
      "profile": "car", // Fastest route uses car
      "locale": "en",
      "points_encoded": false,
      "elevation": false,
      "instructions": true, // Enable turn-by-turn instructions
      "details": ["street_name", "street_ref", "street_destination", "lanes", "road_class", "max_speed", "surface"], // Request all useful path details
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

  /// Calculate shortest route (foot/walking profile for testing)
  Future<http.Response> _calculateShortestRoute({
    required double startLat,
    required double startLon,
    required double endLat,
    required double endLon,
  }) async {
    final uri = Uri.parse('$_graphhopperBaseUrl/route?key=${ApiKeys.graphhopperApiKey}');

    // Use foot profile for walking route
    final requestBody = jsonEncode({
      "points": [
        [startLon, startLat],
        [endLon, endLat],
      ],
      "profile": "foot", // Walking/foot profile
      "locale": "en",
      "points_encoded": false,
      "elevation": false,
      "instructions": true, // Enable turn-by-turn instructions
      "details": ["street_name", "street_ref", "street_destination", "lanes", "road_class", "max_speed", "surface"], // Request all useful path details
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
//    final customModel = {
//      "priority": [
//        // Strongly prefer dedicated cycle infrastructure
//        {"if": "road_class == CYCLEWAY", "multiply_by": 1.5},
//        {"if": "road_class == PATH", "multiply_by": 1.3},
//
//        // Prefer residential and tertiary roads (quieter)
//        {"if": "road_class == RESIDENTIAL", "multiply_by": 1.2},
//        {"if": "road_class == TERTIARY", "multiply_by": 1.1},
//
//        // Avoid busy roads
//        {"if": "road_class == PRIMARY", "multiply_by": 0.5},
//        {"if": "road_class == TRUNK", "multiply_by": 0.3},
//        {"if": "road_class == MOTORWAY", "multiply_by": 0.1},
//
//        // Prefer routes with bike lanes
//        {"if": "bike_network != MISSING", "multiply_by": 1.3},
//      ],
//      "speed": [
//        // Reduce speed on busy roads to account for safety
//        {"if": "road_class == PRIMARY", "limit_to": 12},
//        {"if": "road_class == SECONDARY", "limit_to": 15},
//      ]
//    };

    final requestBody = jsonEncode({
      "points": [
        [startLon, startLat],
        [endLon, endLat],
      ],
      "profile": "bike", // Safest route uses bike profile
      "locale": "en",
      "points_encoded": false,
      "elevation": false,
      "instructions": true, // Enable turn-by-turn instructions
      "details": ["street_name", "street_ref", "street_destination", "lanes", "road_class", "max_speed", "surface"], // Request all useful path details
//      "ch.disable": true,
//      "custom_model": customModel,
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
