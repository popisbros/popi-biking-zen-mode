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
      print('OSM Query: $query');
      
      final response = await http.post(
        Uri.parse(_overpassUrl),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'data': query},
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return _parseOSMResponse(data);
      } else {
        print('OSM API Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      print('OSM Service Error: $e');
      return [];
    }
  }
  
  String _generateOverpassQuery(double south, double west, double north, double east) {
    return '''
[out:json][timeout:25];
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
out geom;
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
