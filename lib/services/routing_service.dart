import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/api_keys.dart';
import '../utils/app_logger.dart';

/// Service for calculating cycling routes using Graphhopper API
class RoutingService {
  static const String _graphhopperBaseUrl = 'https://graphhopper.com/api/1';

  /// Calculate a cycling route from start to end location
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

    try {
      final response = await http.get(uri).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Request timed out after 10 seconds');
        },
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
      AppLogger.error('Failed to calculate route', tag: 'ROUTING', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}
