import 'dart:ui' as ui;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../config/marker_config.dart';

/// Utility class for creating marker icons for Mapbox 3D map
///
/// All methods are static and return PNG image data as Uint8List
/// Icons match the 2D map styling for consistency
class MapboxMarkerUtils {
  /// Get grey color for traveled route segments
  ///
  /// Returns a medium grey color (RGB: 150, 150, 150) with 70% opacity
  /// to clearly distinguish traveled segments from the active route ahead
  static int getTraveledSegmentColor() {
    const greyValue = 150; // Medium grey
    const opacity = 0.7; // 70% opacity

    final a = (255 * opacity).round();

    // Return grey ARGB int
    return (a << 24) | (greyValue << 16) | (greyValue << 8) | greyValue;
  }

  /// Get lighter color with reduced opacity (deprecated - use getTraveledSegmentColor for traveled segments)
  ///
  /// Blends color with white (50% original, 50% white) and reduces opacity to 50%
  @deprecated
  static int getLighterColor(Color color) {
    // Extract ARGB components
    final a = color.alpha;
    final r = color.red;
    final g = color.green;
    final b = color.blue;

    // Blend with white (50% original, 50% white) and reduce opacity to 50%
    final lighterR = (r * 0.5 + 255 * 0.5).round();
    final lighterG = (g * 0.5 + 255 * 0.5).round();
    final lighterB = (b * 0.5 + 255 * 0.5).round();
    final lighterA = (a * 0.5).round(); // 50% opacity for traveled segments

    // Combine into ARGB int
    return (lighterA << 24) | (lighterR << 16) | (lighterG << 8) | lighterB;
  }

  /// Create an image from emoji text for use as marker icon
  ///
  /// Uses proper background and border colors matching the 2D map configuration
  static Future<Uint8List> createEmojiIcon(
    String emoji,
    POIMarkerType markerType, {
    double size = 48,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Get colors from MarkerConfig
    final fillColor = MarkerConfig.getFillColorForType(markerType);
    final borderColor = MarkerConfig.getBorderColorForType(markerType);

    // Draw filled circle background
    final circlePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Draw emoji text
    final textPainter = TextPainter(
      text: TextSpan(
        text: emoji,
        style: TextStyle(fontSize: size * 0.6),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Create user location marker icon matching 2D map style
  ///
  /// White circle with colored border and Icons.navigation arrow
  /// If heading is provided, shows navigation arrow pointing in that direction
  /// If no heading, shows exploration mode with colored dot and transparent grey background
  ///
  /// Parameters:
  /// - heading: Direction in degrees (null for exploration mode)
  /// - size: Icon size in pixels (default 48)
  /// - borderColor: Border and icon color (default purple for navigation, grey for debug)
  static Future<Uint8List> createUserLocationIcon({
    double? heading,
    double size = 48,
    Color borderColor = Colors.purple,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Use white background with colored border
    final fillColor = Colors.white;

    // Save canvas state for rotation
    canvas.save();

    // If we have a heading, rotate the entire marker
    final hasHeading = heading != null && heading >= 0;
    if (hasHeading) {
      // Rotate around center
      // IMPORTANT: Arrow is drawn pointing UP (North/0°)
      // Breadcrumb bearing gives direction FROM first TO last breadcrumb (forward direction)
      // But Icons.navigation in Flutter points UP when heading=0, so we rotate by the bearing angle
      canvas.translate(size / 2, size / 2);
      canvas.rotate(heading * 3.14159 / 180); // Convert to radians
      canvas.translate(-size / 2, -size / 2);
    }

    // Draw filled circle background
    final circlePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Draw navigation arrow or my_location icon
    // Match 2D map: icon size is 60% of marker size
    final iconSize = size * 0.6;

    if (hasHeading) {
      // Draw navigation arrow (custom path matching Icons.navigation)
      final arrowPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.fill;

      // Create triangular navigation arrow pointing up
      final arrowPath = Path();
      final centerX = size / 2;
      final centerY = size / 2;
      final halfIcon = iconSize / 2;

      // Top point (pointing up/north)
      arrowPath.moveTo(centerX, centerY - halfIcon * 0.9);
      // Bottom right
      arrowPath.lineTo(centerX + halfIcon * 0.35, centerY + halfIcon * 0.9);
      // Bottom center notch
      arrowPath.lineTo(centerX, centerY + halfIcon * 0.5);
      // Bottom left
      arrowPath.lineTo(centerX - halfIcon * 0.35, centerY + halfIcon * 0.9);
      // Back to top
      arrowPath.close();

      canvas.drawPath(arrowPath, arrowPaint);
    } else {
      // Exploration mode: Purple dot inside purple circle with grey transparent background

      // Large grey transparent circle (background)
      final greyBgPaint = Paint()
        ..color = Colors.grey.withValues(alpha: 0.1)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        size / 2 - 1, // Almost full size
        greyBgPaint,
      );

      // Purple outer circle (border)
      final purpleCirclePaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0;
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        iconSize / 2.5, // Medium circle
        purpleCirclePaint,
      );

      // Purple center dot (filled)
      final dotPaint = Paint()
        ..color = borderColor
        ..style = PaintingStyle.fill;
      canvas.drawCircle(
        Offset(size / 2, size / 2),
        iconSize / 5, // Small dot
        dotPaint,
      );
    }

    // Restore canvas state
    canvas.restore();

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Create road sign warning image (orange circle matching community hazards style)
  ///
  /// Used for surface type warnings during navigation
  static Future<Uint8List> createRoadSignImage(
    String surfaceType, {
    double size = 48,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Orange circle with ~90% opacity to match other markers
    final bgPaint = Paint()
      ..color = const Color(0xE6FFE0B2) // orange.shade100 with ~90% opacity
      ..style = PaintingStyle.fill;
    final borderPaint = Paint()
      ..color = Colors.orange // Orange border (solid)
      ..style = PaintingStyle.stroke
      ..strokeWidth = MarkerConfig.circleStrokeWidth;

    final center = Offset(size / 2, size / 2);
    final radius = size / 2 - MarkerConfig.circleStrokeWidth;

    // Draw orange filled circle
    canvas.drawCircle(center, radius, bgPaint);
    // Draw orange border
    canvas.drawCircle(center, radius, borderPaint);

    // Get surface-specific icon (matching 2D map)
    final surfaceStr = surfaceType.toLowerCase();
    IconData iconData;

    if (surfaceStr.contains('gravel') || surfaceStr.contains('unpaved')) {
      iconData = Icons.texture; // Gravel/unpaved
    } else if (surfaceStr.contains('dirt') ||
        surfaceStr.contains('sand') ||
        surfaceStr.contains('grass') ||
        surfaceStr.contains('mud')) {
      iconData = Icons.warning; // Poor surfaces
    } else if (surfaceStr.contains('cobble') || surfaceStr.contains('sett')) {
      iconData = Icons.grid_4x4; // Cobblestone
    } else {
      iconData = Icons.warning; // Default warning
    }

    // Draw Material Icon using TextPainter with icon font
    final textPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(iconData.codePoint),
        style: TextStyle(
          fontFamily: iconData.fontFamily,
          package: iconData.fontPackage,
          color: Colors.orange.shade900,
          fontSize: size * 0.5,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(size / 2 - textPainter.width / 2, size / 2 - textPainter.height / 2),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Create search result marker icon (grey circle with + symbol)
  ///
  /// Matches user location marker size and uses same transparency
  static Future<Uint8List> createSearchResultIcon({double size = 48}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Grey colors with transparency matching other markers
    final fillColor = const Color(0xE6757575); // Grey with ~90% opacity
    final borderColor = Colors.grey.shade700;

    // Draw filled circle background
    final circlePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Draw + symbol in red
    final plusPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    final plusSize = size * 0.5;
    final center = size / 2;

    // Horizontal line of +
    canvas.drawLine(
      Offset(center - plusSize / 2, center),
      Offset(center + plusSize / 2, center),
      plusPaint,
    );

    // Vertical line of +
    canvas.drawLine(
      Offset(center, center - plusSize / 2),
      Offset(center, center + plusSize / 2),
      plusPaint,
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  /// Create favorites or destinations marker icon
  ///
  /// Uses star emoji for favorites, pin emoji for destinations
  /// Orange/amber colors with high opacity for visibility
  static Future<Uint8List> createFavoritesIcon({
    required bool isDestination,
    double size = 48,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Colors based on type - light yellow for both
    final fillColor = const Color(0xE6FFF9C4); // Light yellow with ~90% opacity
    final borderColor = Colors.yellow.shade600;

    // Draw filled circle background
    final circlePaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2, circlePaint);

    // Draw border
    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(Offset(size / 2, size / 2), size / 2 - 1.5, borderPaint);

    // Draw emoji icon (teardrop for destinations, star for favorites)
    final textPainter = TextPainter(
      text: TextSpan(
        text: isDestination ? '📍' : '⭐',
        style: TextStyle(fontSize: size * 0.5, fontFamily: 'sans-serif'),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(
      canvas,
      Offset(
        (size - textPainter.width) / 2,
        (size - textPainter.height) / 2,
      ),
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
