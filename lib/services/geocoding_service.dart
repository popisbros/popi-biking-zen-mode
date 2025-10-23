import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:riverpod/riverpod.dart';
import '../config/api_keys.dart';
import '../models/search_result.dart';
import '../utils/app_logger.dart';
import '../utils/api_logger.dart';

/// Service for geocoding and coordinate parsing
class GeocodingService {
  static const String _locationiqBaseUrl = 'https://us1.locationiq.com/v1';
  static const String _nominatimBaseUrl = 'https://nominatim.openstreetmap.org';

  /// Search for addresses/places using LocationIQ API (bounded to viewbox)
  /// Falls back to Nominatim if LocationIQ fails
  Future<List<SearchResult>> searchAddress(String query, LatLng mapCenter, {Ref? ref}) async {
    AppLogger.api('Searching for address (bounded)', data: {
      'query': query,
      'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
      'bounded': '1',
    });

    try {
      // Try LocationIQ first with bounded=1
      final results = await _searchLocationIQ(query, mapCenter, bounded: '1');
      if (results.isNotEmpty) {
        AppLogger.success('LocationIQ bounded search successful', tag: 'GEOCODING', data: {
          'results': results.length,
        });
        return results;
      }
    } catch (e) {
      AppLogger.warning('LocationIQ bounded search failed, trying Nominatim', tag: 'GEOCODING', data: {
        'error': e.toString(),
      });
    }

    // Fallback to Nominatim
    try {
      final results = await _searchNominatim(query, mapCenter);
      AppLogger.success('Nominatim search successful', tag: 'GEOCODING', data: {
        'results': results.length,
      });
      return results;
    } catch (e) {
      AppLogger.error('Nominatim search failed', tag: 'GEOCODING', error: e);
      return [];
    }
  }

  /// Search for addresses/places using LocationIQ API (unbounded - search everywhere)
  /// Used when user clicks "Extend the search"
  /// Requests 20 results (limit=20) to ensure we get ~10 unique results after deduplication
  Future<List<SearchResult>> searchAddressUnbounded(String query, LatLng mapCenter, {Ref? ref}) async {
    AppLogger.api('Searching for address (unbounded)', data: {
      'query': query,
      'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
      'bounded': '0',
      'limit': 20,
    });

    try {
      final results = await _searchLocationIQ(query, mapCenter, bounded: '0', limit: 20);
      AppLogger.success('LocationIQ unbounded search successful', tag: 'GEOCODING', data: {
        'results': results.length,
      });
      return results;
    } catch (e) {
      AppLogger.error('LocationIQ unbounded search failed', tag: 'GEOCODING', error: e);
      return [];
    }
  }

  /// Search using LocationIQ API
  /// [bounded] parameter: '1' = restrict to viewbox, '0' = search everywhere but bias to viewbox
  /// [limit] parameter: number of results to return (default: 10)
  Future<List<SearchResult>> _searchLocationIQ(String query, LatLng mapCenter, {required String bounded, int limit = 10}) async {
    final stopwatch = Stopwatch()..start();

    // Calculate viewbox (50km radius around map center)
    final viewbox = _calculateViewbox(mapCenter, radiusKm: 50);

    final uri = Uri.parse('$_locationiqBaseUrl/search').replace(queryParameters: {
      'key': ApiKeys.locationiqApiKey,
      'q': query,
      'format': 'json',
      'limit': limit.toString(),
      'viewbox': viewbox,
      'bounded': bounded, // '1' = restrict to viewbox, '0' = search everywhere
      'addressdetails': '1',
      'postaladdress': '1', // Include postal address in results
      'dedupe': '1', // Enable deduplication to get nice results
      'normalizeaddress': '1', // Normalize addresses to improve consistency
    });

    AppLogger.api('LocationIQ request', data: {
      'url': uri.toString(),
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      stopwatch.stop();

      // Log API call to Firestore (production + debug)
      await ApiLogger.logApiCall(
        endpoint: 'locationiq/search',
        method: 'GET',
        url: uri.toString(),
        parameters: {
          'query': query,
          'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
          'viewbox': viewbox,
          'bounded': bounded,
          'limit': limit,
          'normalizeaddress': '1',
        },
        statusCode: response.statusCode,
        responseBody: response.body,
        error: response.statusCode != 200 ? 'HTTP ${response.statusCode}' : null,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return _parseGeocodingResults(data, mapCenter);
      } else {
        throw Exception('LocationIQ API error: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();

      // Log error to Firestore
      await ApiLogger.logApiCall(
        endpoint: 'locationiq/search',
        method: 'GET',
        url: 'Error before request',
        parameters: {
          'query': query,
          'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
        },
        statusCode: 0,
        responseBody: '',
        error: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );

      rethrow;
    }
  }

  /// Search using Nominatim API (fallback)
  Future<List<SearchResult>> _searchNominatim(String query, LatLng mapCenter) async {
    final stopwatch = Stopwatch()..start();

    // Calculate viewbox (50km radius around map center)
    final viewbox = _calculateViewbox(mapCenter, radiusKm: 50);

    final uri = Uri.parse('$_nominatimBaseUrl/search').replace(queryParameters: {
      'q': query,
      'format': 'json',
      'limit': '10',
      'viewbox': viewbox,
      'bounded': '0',
      'addressdetails': '1',
    });

    AppLogger.api('Nominatim request', data: {
      'url': uri.toString(),
    });

    try {
      final response = await http.get(
        uri,
        headers: {
          'User-Agent': 'PopiIsBiking/1.0 (contact@popiisbiking.com)', // Required by Nominatim usage policy
        },
      ).timeout(const Duration(seconds: 10));

      stopwatch.stop();

      // Log API call to Firestore (production + debug)
      await ApiLogger.logApiCall(
        endpoint: 'nominatim/search',
        method: 'GET',
        url: uri.toString(),
        parameters: {
          'query': query,
          'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
          'viewbox': viewbox,
          'limit': 10,
        },
        statusCode: response.statusCode,
        responseBody: response.body,
        error: response.statusCode != 200 ? 'HTTP ${response.statusCode}' : null,
        durationMs: stopwatch.elapsedMilliseconds,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return _parseGeocodingResults(data, mapCenter);
      } else {
        throw Exception('Nominatim API error: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();

      // Log error to Firestore
      await ApiLogger.logApiCall(
        endpoint: 'nominatim/search',
        method: 'GET',
        url: 'Error before request',
        parameters: {
          'query': query,
          'mapCenter': '${mapCenter.latitude},${mapCenter.longitude}',
        },
        statusCode: 0,
        responseBody: '',
        error: e.toString(),
        durationMs: stopwatch.elapsedMilliseconds,
      );

      rethrow;
    }
  }

  /// Parse geocoding API response into SearchResult list
  List<SearchResult> _parseGeocodingResults(List<dynamic> data, LatLng mapCenter) {
    final results = <SearchResult>[];

    for (final item in data) {
      try {
        final lat = double.tryParse(item['lat']?.toString() ?? '0') ?? 0.0;
        final lon = double.tryParse(item['lon']?.toString() ?? '0') ?? 0.0;
        final distance = calculateDistance(mapCenter, LatLng(lat, lon));

        final result = SearchResult.fromGeocodingResponse(
          item as Map<String, dynamic>,
          distanceFromCenter: distance,
        );

        results.add(result);
      } catch (e) {
        AppLogger.warning('Failed to parse geocoding result', tag: 'GEOCODING', data: {
          'error': e.toString(),
          'item': item.toString(),
        });
      }
    }

    // Sort by distance from map center
    results.sort((a, b) {
      final distA = a.distance ?? double.infinity;
      final distB = b.distance ?? double.infinity;
      return distA.compareTo(distB);
    });

    return results.take(10).toList();
  }

  /// Calculate viewbox around a center point
  /// Returns: "lon_left,lat_bottom,lon_right,lat_top"
  String _calculateViewbox(LatLng center, {required double radiusKm}) {
    // Approximate degrees per km (varies by latitude)
    final latDegreesPerKm = 1 / 111.0;
    final lonDegreesPerKm = 1 / (111.0 * math.cos(center.latitude * math.pi / 180));

    final latOffset = radiusKm * latDegreesPerKm;
    final lonOffset = radiusKm * lonDegreesPerKm;

    final lonLeft = center.longitude - lonOffset;
    final latBottom = center.latitude - latOffset;
    final lonRight = center.longitude + lonOffset;
    final latTop = center.latitude + latOffset;

    return '$lonLeft,$latBottom,$lonRight,$latTop';
  }

  /// Parse GPS coordinates from various formats
  /// Supports:
  /// - Decimal Degrees (DD): "48.8566, 2.3522" or "48.8566 2.3522"
  /// - Degrees Minutes Seconds (DMS): "48°51'24"N 2°21'08"E"
  /// - Degrees Decimal Minutes (DDM): "48°51.4'N 2°21.1'E"
  SearchResult? parseCoordinates(String input, LatLng mapCenter) {
    input = input.trim();

    // Try Decimal Degrees (DD) format
    final ddMatch = RegExp(r'^(-?\d+\.?\d*)[,\s]+(-?\d+\.?\d*)$').firstMatch(input);
    if (ddMatch != null) {
      final lat = double.tryParse(ddMatch.group(1)!);
      final lon = double.tryParse(ddMatch.group(2)!);
      if (lat != null && lon != null && _isValidCoordinate(lat, lon)) {
        final distance = calculateDistance(mapCenter, LatLng(lat, lon));
        return SearchResult.fromCoordinates(lat, lon, distanceFromCenter: distance);
      }
    }

    // Try Degrees Minutes Seconds (DMS) format: 48°51'24"N 2°21'08"E
    // Using Unicode escape \u00B0 for degree symbol
    final dmsMatch = RegExp(
      '(\\d+)\\u00B0\\s*(\\d+)\'\\s*(\\d+(?:\\.\\d+)?)"?\\s*([NS])\\s*(\\d+)\\u00B0\\s*(\\d+)\'\\s*(\\d+(?:\\.\\d+)?)"?\\s*([EW])',
    ).firstMatch(input);
    if (dmsMatch != null) {
      final lat = _dmsToDecimal(
        int.parse(dmsMatch.group(1)!),
        int.parse(dmsMatch.group(2)!),
        double.parse(dmsMatch.group(3)!),
        dmsMatch.group(4)!,
      );
      final lon = _dmsToDecimal(
        int.parse(dmsMatch.group(5)!),
        int.parse(dmsMatch.group(6)!),
        double.parse(dmsMatch.group(7)!),
        dmsMatch.group(8)!,
      );
      if (_isValidCoordinate(lat, lon)) {
        final distance = calculateDistance(mapCenter, LatLng(lat, lon));
        return SearchResult.fromCoordinates(lat, lon, distanceFromCenter: distance);
      }
    }

    // Try Degrees Decimal Minutes (DDM) format: 48°51.4'N 2°21.1'E
    final ddmMatch = RegExp(
      '(\\d+)\\u00B0\\s*(\\d+\\.?\\d*)\'?\\s*([NS])\\s*(\\d+)\\u00B0\\s*(\\d+\\.?\\d*)\'?\\s*([EW])',
    ).firstMatch(input);
    if (ddmMatch != null) {
      final lat = _ddmToDecimal(
        int.parse(ddmMatch.group(1)!),
        double.parse(ddmMatch.group(2)!),
        ddmMatch.group(3)!,
      );
      final lon = _ddmToDecimal(
        int.parse(ddmMatch.group(4)!),
        double.parse(ddmMatch.group(5)!),
        ddmMatch.group(6)!,
      );
      if (_isValidCoordinate(lat, lon)) {
        final distance = calculateDistance(mapCenter, LatLng(lat, lon));
        return SearchResult.fromCoordinates(lat, lon, distanceFromCenter: distance);
      }
    }

    return null;
  }

  /// Convert DMS (Degrees Minutes Seconds) to Decimal Degrees
  double _dmsToDecimal(int degrees, int minutes, double seconds, String direction) {
    double decimal = degrees + (minutes / 60.0) + (seconds / 3600.0);
    if (direction == 'S' || direction == 'W') {
      decimal = -decimal;
    }
    return decimal;
  }

  /// Convert DDM (Degrees Decimal Minutes) to Decimal Degrees
  double _ddmToDecimal(int degrees, double minutes, String direction) {
    double decimal = degrees + (minutes / 60.0);
    if (direction == 'S' || direction == 'W') {
      decimal = -decimal;
    }
    return decimal;
  }

  /// Validate coordinate ranges
  bool _isValidCoordinate(double lat, double lon) {
    return lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180;
  }

  /// Calculate distance between two coordinates using Haversine formula
  /// Returns distance in kilometers
  double calculateDistance(LatLng from, LatLng to) {
    const earthRadius = 6371.0; // Earth radius in kilometers

    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLat = (to.latitude - from.latitude) * math.pi / 180;
    final dLon = (to.longitude - from.longitude) * math.pi / 180;

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadius * c;
  }
}
