import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import '../config/secure_config.dart';
import '../providers/locationiq_debug_provider.dart';

/// Service for LocationIQ API geocoding and search
class LocationIQService {
  static const String _baseUrl = 'https://us1.locationiq.com/v1';
  late final String _apiKey;
  LocationIQDebugNotifier? _debugNotifier;
  
  LocationIQService({String? apiKey, LocationIQDebugNotifier? debugNotifier}) {
    _apiKey = apiKey ?? SecureConfig.locationIQApiKey;
    _debugNotifier = debugNotifier;
  }
  
  /// Search for locations using LocationIQ geocoding API
  /// Returns top 10 results sorted by distance from the given center point
  Future<List<LocationIQResult>> searchLocations({
    required String query,
    required LatLng center,
    int limit = 10,
  }) async {
    List<LocationIQResult> results = [];
    String? error;
    String? responseBody;
    bool success = false;
    
    try {
      print('LocationIQ Service: Searching for "$query" near ${center.latitude}, ${center.longitude}');
      
      final uri = Uri.parse('$_baseUrl/search.php').replace(queryParameters: {
        'key': _apiKey,
        'q': query,
        'format': 'json',
        'limit': limit.toString(),
        'addressdetails': '1',
        'namedetails': '1',
        'dedupe': '1',
      });
      
      print('LocationIQ Service: Request URL: $uri');
      
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'PopiIsBikingZenMode/1.0',
        },
      );
      
      // Capture response body for debug purposes
      responseBody = response.body;
      
      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        print('LocationIQ Service: Received ${data.length} results');
        
        results = data.map((item) => LocationIQResult.fromJson(item)).toList();
        
        // Sort by distance from center point
        results.sort((a, b) {
          final distanceA = _calculateDistance(center, a.latLng);
          final distanceB = _calculateDistance(center, b.latLng);
          return distanceA.compareTo(distanceB);
        });
        
        print('LocationIQ Service: Sorted results by distance');
        success = true;
      } else {
        print('LocationIQ Service: Error ${response.statusCode}: ${response.body}');
        error = 'LocationIQ API error: ${response.statusCode}';
        throw Exception(error);
      }
    } catch (e) {
      print('LocationIQ Service: Exception during search: $e');
      error = 'Failed to search locations: $e';
      throw Exception(error);
    } finally {
      // Record debug data
      _debugNotifier?.recordSearch(
        query: query,
        success: success,
        resultCount: results.length,
        error: error,
        searchLat: center.latitude,
        searchLng: center.longitude,
        results: success ? results : null,
        responseBody: responseBody,
      );
    }
    
    return results;
  }
  
  /// Calculate distance between two points in meters
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = _degreesToRadians(point2.latitude - point1.latitude);
    final double dLon = _degreesToRadians(point2.longitude - point1.longitude);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(point1.latitude)) * math.cos(_degreesToRadians(point2.latitude)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }
  
  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (3.14159265359 / 180);
  }
}

/// Result from LocationIQ search
class LocationIQResult {
  final String placeId;
  final String displayName;
  final String name;
  final LatLng latLng;
  final String? type;
  final String? category;
  final String? address;
  final double? importance;
  final Map<String, dynamic>? extraTags;
  
  LocationIQResult({
    required this.placeId,
    required this.displayName,
    required this.name,
    required this.latLng,
    this.type,
    this.category,
    this.address,
    this.importance,
    this.extraTags,
  });
  
  factory LocationIQResult.fromJson(Map<String, dynamic> json) {
    return LocationIQResult(
      placeId: json['place_id']?.toString() ?? '',
      displayName: json['display_name'] ?? '',
      name: json['name'] ?? json['display_name'] ?? 'Unknown Location',
      latLng: LatLng(
        double.parse(json['lat']?.toString() ?? '0'),
        double.parse(json['lon']?.toString() ?? '0'),
      ),
      type: json['type'],
      category: json['class'],
      address: _buildAddress(json['address']),
      importance: json['importance']?.toDouble(),
      extraTags: json['extratags'],
    );
  }
  
  static String? _buildAddress(Map<String, dynamic>? address) {
    if (address == null) return null;
    
    final parts = <String>[];
    
    // Add address components in order of specificity
    if (address['house_number'] != null) parts.add(address['house_number']);
    if (address['road'] != null) parts.add(address['road']);
    if (address['suburb'] != null) parts.add(address['suburb']);
    if (address['city'] != null) parts.add(address['city']);
    if (address['state'] != null) parts.add(address['state']);
    if (address['country'] != null) parts.add(address['country']);
    
    return parts.isNotEmpty ? parts.join(', ') : null;
  }
  
  /// Get a user-friendly display text for the result
  String get displayText {
    if (address != null && address!.isNotEmpty) {
      return '$name - $address';
    }
    return displayName;
  }
  
  /// Get distance from a given point in meters
  double getDistanceFrom(LatLng point) {
    const double earthRadius = 6371000; // Earth's radius in meters
    final double dLat = _degreesToRadians(latLng.latitude - point.latitude);
    final double dLon = _degreesToRadians(latLng.longitude - point.longitude);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degreesToRadians(point.latitude)) * math.cos(_degreesToRadians(latLng.latitude)) *
        math.sin(dLon / 2) * math.sin(dLon / 2);
    final double c = 2 * math.asin(math.sqrt(a));
    return earthRadius * c;
  }
  
  /// Convert degrees to radians
  double _degreesToRadians(double degrees) {
    return degrees * (3.14159265359 / 180);
  }
}
