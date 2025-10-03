import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/cycling_poi.dart';
import '../utils/app_logger.dart';
import 'osm_debug_service.dart';

class OSMService {
  static const String _overpassUrl = 'https://overpass-api.de/api/interpreter';
  final OSMDebugService _debugService = OSMDebugService();
  
  /// Query POIs from OSM using Overpass API
  Future<List<OSMPOI>> getPOIsInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    final stopwatch = Stopwatch()..start();
    final query = _generateOverpassQuery(south, west, north, east);
    final parameters = {
      'south': south,
      'west': west,
      'north': north,
      'east': east,
    };
    
    // Log the request
    _debugService.logOSMRequest(
      url: _overpassUrl,
      parameters: parameters,
      query: query,
    );
    
    try {
      AppLogger.api('Starting OSM query', data: {
        'south': south,
        'west': west,
        'north': north,
        'east': east,
        'timestamp': DateTime.now().toIso8601String(),
        'query': query,
      });

      final response = await http.post(
        Uri.parse(_overpassUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'data': query},
      ).timeout(const Duration(seconds: 20));
      
      stopwatch.stop();
      
      if (response.statusCode == 200) {
        // Log successful response
        _debugService.logOSMResponse(
          url: _overpassUrl,
          parameters: parameters,
          query: query,
          statusCode: response.statusCode,
          responseBody: response.body,
          duration: stopwatch.elapsed,
        );
        
        final data = json.decode(response.body);
        return _parseOSMResponse(data);
      } else {
        // Log error response
        _debugService.logOSMError(
          url: _overpassUrl,
          parameters: parameters,
          query: query,
          error: 'HTTP ${response.statusCode}: ${response.body}',
          duration: stopwatch.elapsed,
        );

        AppLogger.api('OSM API Error', error: Exception('HTTP ${response.statusCode}'), data: {
          'statusCode': response.statusCode,
          'body': response.body,
        });
        if (response.statusCode == 504) {
          AppLogger.api('Gateway timeout - trying with smaller bounding box');
          return await _trySmallerBoundingBox(south, west, north, east);
        }
        return [];
      }
    } catch (e) {
      stopwatch.stop();

      // Log exception
      _debugService.logOSMError(
        url: _overpassUrl,
        parameters: parameters,
        query: query,
        error: e.toString(),
        duration: stopwatch.elapsed,
      );

      AppLogger.api('OSM Service Error', error: e);
      if (e.toString().contains('timeout') || e.toString().contains('504')) {
        AppLogger.api('Timeout error - trying with smaller bounding box');
        return await _trySmallerBoundingBox(south, west, north, east);
      }
      return [];
    }
  }

  /// Fallback method to try with a smaller bounding box
  Future<List<OSMPOI>> _trySmallerBoundingBox(double south, double west, double north, double east) async {
    final stopwatch = Stopwatch()..start();
    
    // Reduce the bounding box by 50%
    final centerLat = (south + north) / 2;
    final centerLon = (west + east) / 2;
    final latDiff = (north - south) * 0.5;
    final lonDiff = (east - west) * 0.5;
    
    final newSouth = centerLat - latDiff;
    final newNorth = centerLat + latDiff;
    final newWest = centerLon - lonDiff;
    final newEast = centerLon + lonDiff;
    
    final query = _generateOverpassQuery(newSouth, newWest, newNorth, newEast);
    final parameters = {
      'south': newSouth,
      'west': newWest,
      'north': newNorth,
      'east': newEast,
      'fallback': true,
      'original_south': south,
      'original_west': west,
      'original_north': north,
      'original_east': east,
    };
    
    // Log the fallback request
    _debugService.logOSMRequest(
      url: '$_overpassUrl (FALLBACK)',
      parameters: parameters,
      query: query,
    );

    try {
      AppLogger.api('Retrying with smaller bounds', data: {
        'south': newSouth,
        'west': newWest,
        'north': newNorth,
        'east': newEast,
      });

      final response = await http.post(
        Uri.parse(_overpassUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'data': query},
      ).timeout(const Duration(seconds: 15));
      
      stopwatch.stop();
      
      if (response.statusCode == 200) {
        // Log successful fallback response
        _debugService.logOSMResponse(
          url: '$_overpassUrl (FALLBACK)',
          parameters: parameters,
          query: query,
          statusCode: response.statusCode,
          responseBody: response.body,
          duration: stopwatch.elapsed,
        );
        
        final data = json.decode(response.body);
        return _parseOSMResponse(data);
      } else {
        // Log failed fallback response
        _debugService.logOSMError(
          url: '$_overpassUrl (FALLBACK)',
          parameters: parameters,
          query: query,
          error: 'HTTP ${response.statusCode}: ${response.body}',
          duration: stopwatch.elapsed,
        );

        AppLogger.api('Second attempt also failed', error: Exception('HTTP ${response.statusCode}'), data: {
          'statusCode': response.statusCode,
        });
        return [];
      }
    } catch (e) {
      stopwatch.stop();

      // Log fallback exception
      _debugService.logOSMError(
        url: '$_overpassUrl (FALLBACK)',
        parameters: parameters,
        query: query,
        error: e.toString(),
        duration: stopwatch.elapsed,
      );

      AppLogger.api('Second attempt error', error: e);
      return [];
    }
  }
  
  String _generateOverpassQuery(double south, double west, double north, double east) {
    // Full query with all POI types, reduced timeout to 15 seconds
    return '''
[out:json][timeout:15];
(
  node["amenity"="bicycle_parking"]($south,$west,$north,$east);
  node["amenity"="repair_station"]($south,$west,$north,$east);
  node["amenity"="charging_station"]["bicycle"="yes"]($south,$west,$north,$east);
  node["shop"="bicycle"]($south,$west,$north,$east);
  node["amenity"="drinking_water"]($south,$west,$north,$east);
  node["man_made"="water_tap"]($south,$west,$north,$east);
  node["amenity"="toilets"]($south,$west,$north,$east);
  node["amenity"="shelter"]($south,$west,$north,$east);
);
out;
''';
  }
  
  List<OSMPOI> _parseOSMResponse(Map<String, dynamic> data) {
    final elements = data['elements'] as List<dynamic>? ?? [];
    final pois = <OSMPOI>[];

    for (final element in elements) {
      try {
        final poi = OSMPOI.fromOSMData(element);
        if (poi.type != 'unknown') {
          pois.add(poi);
        }
      } catch (e) {
        AppLogger.error('Error parsing OSM element', error: e);
      }
    }

    AppLogger.success('Loaded ${pois.length} OSM POIs');
    return pois;
  }
}
