import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'dart:math' as math;

class SurgeService {
  // Singleton instance
  static final SurgeService _instance = SurgeService._internal();
  factory SurgeService() => _instance;
  SurgeService._internal();
  
  // The loaded heat map image
  ui.Image? _heatMapImage;
  // Completer to ensure image is loaded
  final Completer<ui.Image> _imageCompleter = Completer<ui.Image>();
  
  // Size of the heat map in pixels
  int get imageWidth => _heatMapImage?.width ?? 0;
  int get imageHeight => _heatMapImage?.height ?? 0;
  
  // Geographic bounds for the heat map (will be centered on user's location)
  // This will be a square area around the user's current location
  // The size will be determined by the range parameter (in kilometers)
  double _range = 5.0; // Default 5km range
  
  // Get the image when ready
  Future<ui.Image> get heatMapImage => _imageCompleter.future;
  
  // Initialize and load the image
  Future<void> init() async {
    if (_heatMapImage != null) return;
    
    try {
      // Load the asset as bytes
      final ByteData data = await rootBundle.load('assets/random_blobs.jpg');
      final Uint8List bytes = data.buffer.asUint8List();
      
      // Decode the image
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      _heatMapImage = frameInfo.image;
      
      if (!_imageCompleter.isCompleted) {
        _imageCompleter.complete(_heatMapImage);
      }
      
      debugPrint('Heat map image loaded: ${_heatMapImage!.width}x${_heatMapImage!.height}');
    } catch (e) {
      debugPrint('Failed to load heat map image: $e');
      if (!_imageCompleter.isCompleted) {
        _imageCompleter.completeError(e);
      }
    }
  }
  
  // Set the geographic range of the heat map (in kilometers)
  void setRange(double kilometers) {
    _range = kilometers;
  }
  
  // Calculate the surge multiplier at a given location
  // Returns a value between 1.0 (base price) and 3.0 (maximum surge)
  Future<double> getSurgeMultiplier(LatLng position, LatLng userLocation) async {
    try {
      final ui.Image image = await heatMapImage;
      
      // Convert geographical coordinates to pixel positions in the image
      final Point<int> pixelPoint = geoToPixel(position, userLocation);
      
      // If outside the image bounds, return base price
      if (pixelPoint.x < 0 || pixelPoint.x >= image.width || 
          pixelPoint.y < 0 || pixelPoint.y >= image.height) {
        return 1.0;
      }
      
      // Get pixel color at the location
      final double grayscaleValue = await _getPixelGrayscaleValue(pixelPoint.x, pixelPoint.y);
      
      // Convert grayscale value to surge multiplier
      // Black (0) = highest surge (3.0)
      // White (255) = lowest surge (1.0)
      final double normalizedValue = 1.0 - (grayscaleValue / 255.0);
      final double multiplier = 1.0 + (normalizedValue * 2.0); // Scale to 1.0-3.0 range
      
      return multiplier;
    } catch (e) {
      debugPrint('Error calculating surge multiplier: $e');
      return 1.0; // Default to base price on error
    }
  }
  
  // Get the grayscale value (0-255) of a pixel in the image
  Future<double> _getPixelGrayscaleValue(int x, int y) async {
    if (_heatMapImage == null) {
      await init(); // Make sure image is loaded
    }
    
    if (_heatMapImage == null) {
      return 255.0; // Default to white (no surge) if image failed to load
    }
    
    // Create a small buffer to store the pixel data
    final ByteData? byteData = await _heatMapImage!.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (byteData == null) return 255.0;
    
    // Calculate the position in the buffer
    final int pixelIndex = (y * _heatMapImage!.width + x) * 4;
    
    // Extract RGB values
    final int r = byteData.getUint8(pixelIndex);
    final int g = byteData.getUint8(pixelIndex + 1);
    final int b = byteData.getUint8(pixelIndex + 2);
    
    // Calculate grayscale value (luminance formula)
    // Using standard RGB to grayscale conversion: Gray = 0.299R + 0.587G + 0.114B
    return (0.299 * r + 0.587 * g + 0.114 * b);
  }
  
  // Convert geographical coordinates to pixel position in the heat map image
  Point<int> geoToPixel(LatLng position, LatLng centerPoint) {
    // Calculate the distance and bearing from the center point
    final Distance distance = const Distance();
    final double distanceInMeters = distance.distance(centerPoint, position);
    final double bearing = distance.bearing(centerPoint, position);
    
    // Convert distance to a proportion of the range
    final double distanceProportion = distanceInMeters / (_range * 1000);
    
    // Calculate pixel position from the center of the image
    final double centerX = imageWidth / 2;
    final double centerY = imageHeight / 2;
    
    // Convert polar coordinates (distance, bearing) to cartesian (x, y)
    final double bearingRadians = bearing * (pi / 180);
    final double x = centerX + (distanceProportion * imageWidth * sin(bearingRadians));
    final double y = centerY - (distanceProportion * imageHeight * cos(bearingRadians));
    
    return Point<int>(x.round(), y.round());
  }
  
  // Convert pixel position in the heat map image to geographical coordinates
  LatLng pixelToGeo(int x, int y, LatLng centerPoint) {
    // Calculate distance from center in proportion of image size
    final double centerX = imageWidth / 2;
    final double centerY = imageHeight / 2;
    
    final double dx = x - centerX;
    final double dy = centerY - y; // Y is inverted in image coordinates
    
    // Convert to polar coordinates
    final double distance = sqrt(dx * dx + dy * dy);
    final double bearing = (atan2(dx, dy) * (180 / pi) + 360) % 360;
    
    // Calculate actual distance in meters
    final double distanceProportion = distance / (imageWidth / 2);
    final double distanceInMeters = distanceProportion * (_range * 1000);
    
    // Calculate new geographical coordinates
    final Distance distCalc = const Distance();
    return distCalc.offset(centerPoint, distanceInMeters, bearing);
  }
  
  // Helper math functions
  double sin(double radians) => Math.sin(radians);
  double cos(double radians) => Math.cos(radians);
  double atan2(double y, double x) => Math.atan2(y, x);
  double sqrt(double value) => Math.sqrt(value);
}

// Math helper for trig functions
class Math {
  static double sin(double radians) => math.sin(radians);
  static double cos(double radians) => math.cos(radians);
  static double atan2(double y, double x) => math.atan2(y, x);
  static double sqrt(double value) => math.sqrt(value);
}

// Custom heat map layer for FlutterMap
class HeatMapLayer extends StatelessWidget {
  final LatLng centerPosition;
  final SurgeService surgeService;
  final double opacity;

  const HeatMapLayer({
    Key? key,
    required this.centerPosition,
    required this.surgeService,
    this.opacity = 0.7,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: surgeService.heatMapImage,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          return const SizedBox.shrink();
        }

        return CustomPaint(
          painter: HeatMapPainter(
            image: snapshot.data!,
            centerPosition: centerPosition,
            surgeService: surgeService,
            opacity: opacity,
          ),
          size: Size.infinite,
        );
      },
    );
  }
}

class HeatMapPainter extends CustomPainter {
  final ui.Image image;
  final LatLng centerPosition;
  final SurgeService surgeService;
  final double opacity;

  HeatMapPainter({
    required this.image,
    required this.centerPosition,
    required this.surgeService,
    required this.opacity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..colorFilter = ColorFilter.mode(
          Colors.blue.withOpacity(opacity), BlendMode.srcATop)
      ..filterQuality = FilterQuality.medium;

    // Get the map's bounds from its size
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      paint,
    );
  }

  @override
  bool shouldRepaint(HeatMapPainter oldDelegate) {
    return oldDelegate.centerPosition != centerPosition ||
           oldDelegate.opacity != opacity;
  }
}
