import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'map_screen.dart';

/// Stub for Web platform - redirects to 2D map
/// This file is only used on Web builds where Mapbox 3D is not supported
class MapboxMapScreenSimple extends ConsumerStatefulWidget {
  const MapboxMapScreenSimple({super.key});

  @override
  ConsumerState<MapboxMapScreenSimple> createState() => _MapboxMapScreenSimpleStubState();
}

class _MapboxMapScreenSimpleStubState extends ConsumerState<MapboxMapScreenSimple> {
  @override
  Widget build(BuildContext context) {
    // On Web, redirect to 2D map (Mapbox not supported)
    return const MapScreen();
  }
}
