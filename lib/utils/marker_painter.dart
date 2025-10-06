import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Utility class for creating custom marker icons
class MarkerPainter {
  /// Create a teardrop marker with checkered flag pattern
  /// Inspired by racing finish line flags
  static Future<Uint8List> createCheckeredTeardropMarker({
    double size = 60,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Teardrop dimensions
    final dropWidth = size * 0.7; // Width of the teardrop
    final dropHeight = size * 1.2; // Total height including tail
    final circleRadius = dropWidth / 2; // Radius of the round part

    // Calculate center for the round part
    final centerX = size / 2;
    final centerY = circleRadius;

    // Save canvas state
    canvas.save();

    // Draw teardrop shape using bezier curves for smoother appearance
    final teardropPath = Path();

    // Start at top center of circle
    teardropPath.moveTo(centerX, 0);

    // Right semicircle using arc
    teardropPath.arcToPoint(
      Offset(centerX + circleRadius, circleRadius),
      radius: Radius.circular(circleRadius),
      clockwise: true,
    );

    // Bottom of circle to tip of teardrop using quadratic bezier
    teardropPath.quadraticBezierTo(
      centerX + circleRadius * 0.7, // Control point X
      circleRadius + (dropHeight - circleRadius * 2) * 0.5, // Control point Y
      centerX, // End point X
      dropHeight, // End point Y (tip)
    );

    // Tip back to bottom left of circle
    teardropPath.quadraticBezierTo(
      centerX - circleRadius * 0.7, // Control point X
      circleRadius + (dropHeight - circleRadius * 2) * 0.5, // Control point Y
      centerX - circleRadius, // End point X
      circleRadius, // End point Y
    );

    // Left semicircle back to top
    teardropPath.arcToPoint(
      Offset(centerX, 0),
      radius: Radius.circular(circleRadius),
      clockwise: true,
    );

    teardropPath.close();

    // Clip to teardrop shape
    canvas.clipPath(teardropPath);

    // Draw checkered flag pattern (like racing flag)
    final squareSize = circleRadius / 2.5; // Size of each square
    final Paint blackPaint = Paint()..color = Colors.black;
    final Paint whitePaint = Paint()..color = Colors.white;

    // Draw checkered pattern
    for (double y = 0; y < dropHeight + squareSize; y += squareSize) {
      for (double x = 0; x < size + squareSize; x += squareSize) {
        // Alternate colors in checkerboard pattern
        final isBlack = ((x / squareSize).floor() + (y / squareSize).floor()) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(x, y, squareSize, squareSize),
          isBlack ? blackPaint : whitePaint,
        );
      }
    }

    // Restore to remove clip
    canvas.restore();

    // Draw teardrop outline for definition
    final outlinePaint = Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawPath(teardropPath, outlinePaint);

    final picture = recorder.endRecording();
    final image = await picture.toImage(size.toInt(), dropHeight.ceil());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }
}
