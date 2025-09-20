import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../models/cycling_poi.dart';

class OSMService {
  static const String _overpassUrl = 'https://overpass-api.de/api/interpreter';
  
  /// Query POIs from OSM using Overpass API
  Future<List<OSMPOI>> getPOIsInBounds({
    required double south,
    required double west,
    required double north,
    required double east,
  }) async {
    try {
      final query = _generateOverpassQuery(south, west, north, east);
      print('OSM Service: Starting query for bounds: south=$south, west=$west, north=$north, east=$east');
      print('OSM Service: Query timestamp: ${DateTime.now()}');
      print('OSM Query: $query');
      
      final response = await http.post(
        Uri.parse(_overpassUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'data': query},
      ).timeout(const Duration(seconds: 20));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseOSMResponse(data);
      } else {
        print('OSM API Error: ${response.statusCode} - ${response.body}');
        if (response.statusCode == 504) {
          print('OSM Service: Gateway timeout - trying with smaller bounding box');
          return await _trySmallerBoundingBox(south, west, north, east);
        }
        return [];
      }
    } catch (e) {
      print('OSM Service Error: $e');
      if (e.toString().contains('timeout') || e.toString().contains('504')) {
        print('OSM Service: Timeout error - trying with smaller bounding box');
        return await _trySmallerBoundingBox(south, west, north, east);
      }
      return [];
    }
  }

  /// Fallback method to try with a smaller bounding box
  Future<List<OSMPOI>> _trySmallerBoundingBox(double south, double west, double north, double east) async {
    try {
      // Reduce the bounding box by 50%
      final centerLat = (south + north) / 2;
      final centerLon = (west + east) / 2;
      final latDiff = (north - south) * 0.5;
      final lonDiff = (east - west) * 0.5;
      
      final newSouth = centerLat - latDiff;
      final newNorth = centerLat + latDiff;
      final newWest = centerLon - lonDiff;
      final newEast = centerLon + lonDiff;
      
      print('OSM Service: Retrying with smaller bounds: south=$newSouth, west=$newWest, north=$newNorth, east=$newEast');
      
      final query = _generateOverpassQuery(newSouth, newWest, newNorth, newEast);
      final response = await http.post(
        Uri.parse(_overpassUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'data': query},
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseOSMResponse(data);
      } else {
        print('OSM Service: Second attempt also failed: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('OSM Service: Second attempt error: $e');
      return [];
    }
  }
  
  String _generateOverpassQuery(double south, double west, double north, double east) {
    // Reduce timeout to 15 seconds and simplify query
    return '''
[out:json][timeout:15];
(
  node["amenity"="bicycle_parking"]($south,$west,$north,$east);
  node["amenity"="repair_station"]($south,$west,$north,$east);
  node["shop"="bicycle"]($south,$west,$north,$east);
  node["amenity"="drinking_water"]($south,$west,$north,$east);
  node["amenity"="toilets"]($south,$west,$north,$east);
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
        print('Error parsing OSM element: $e');
      }
    }
    
    print('Loaded ${pois.length} OSM POIs');
    return pois;
  }
}
