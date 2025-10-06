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

    // Calculate positions - drawing with TIP at TOP
    final centerX = size / 2;
    final tipY = 0.0; // Tip at the very top
    final circleBottomY = dropHeight; // Circle at bottom

    // Save canvas state
    canvas.save();

    // Draw teardrop shape using bezier curves - TIP AT TOP, CIRCLE AT BOTTOM
    final teardropPath = Path();

    // Start at tip (top center)
    teardropPath.moveTo(centerX, tipY);

    // Tip to bottom right of circle using quadratic bezier
    teardropPath.quadraticBezierTo(
      centerX + circleRadius * 0.7, // Control point X
      tipY + (dropHeight - circleRadius * 2) * 0.5, // Control point Y
      centerX + circleRadius, // End point X (right side of circle)
      circleBottomY - circleRadius, // End point Y
    );

    // Right semicircle using arc
    teardropPath.arcToPoint(
      Offset(centerX, circleBottomY),
      radius: Radius.circular(circleRadius),
      clockwise: true,
    );

    // Bottom semicircle to left side
    teardropPath.arcToPoint(
      Offset(centerX - circleRadius, circleBottomY - circleRadius),
      radius: Radius.circular(circleRadius),
      clockwise: true,
    );

    // Left side of circle back to tip using quadratic bezier
    teardropPath.quadraticBezierTo(
      centerX - circleRadius * 0.7, // Control point X
      tipY + (dropHeight - circleRadius * 2) * 0.5, // Control point Y
      centerX, // End point X (back to tip)
      tipY, // End point Y
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
