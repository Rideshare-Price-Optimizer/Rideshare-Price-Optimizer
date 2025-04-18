import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:provider/provider.dart';

class SurgeService {
  // Singleton instance
  static final SurgeService _instance = SurgeService._internal();
  factory SurgeService() => _instance;
  SurgeService._internal();
  
  // The loaded heat map image
  ui.Image? _heatMapImage;
  // Use a completer that we can reset and recreate when needed
  Completer<ui.Image>? _imageCompleter;
  // Track if image is currently loading
  bool _isLoading = false;
  // Keep the raw bytes of the image to allow reloading if needed
  Uint8List? _imageBytes;
  
  // Size of the heat map in pixels
  int get imageWidth => _heatMapImage?.width ?? 0;
  int get imageHeight => _heatMapImage?.height ?? 0;
  
  // Geographic bounds for the heat map (will be centered on user's location)
  // This will be a square area around the user's current location
  // The size will be determined by the range parameter (in kilometers)
  double _range = 5.0; // Default 5km range
  
  // Get the image when ready - with error handling for disposed images
  Future<ui.Image> get heatMapImage async {
    // If we don't have a completer or the image is disposed, reload the image
    if (_imageCompleter == null || _heatMapImage == null) {
      await _reloadImage();
    }
    
    try {
      // Try to clone the image as a simple check if it's still valid
      if (_heatMapImage != null) {
        _heatMapImage!.clone();
      }
    } catch (e) {
      // Image was disposed, need to reload
      debugPrint('Heat map image was disposed, reloading...');
      await _reloadImage();
    }
    
    return _imageCompleter!.future;
  }
  
  // Initialize and load the image
  Future<void> init() async {
    await _loadImage();
  }
  
  // Private method to load the image
  Future<void> _loadImage() async {
    if (_isLoading) return;
    _isLoading = true;
    
    try {
      // Load the asset as bytes if we don't have them yet
      if (_imageBytes == null) {
        final ByteData data = await rootBundle.load('assets/random_blobs.png');
        _imageBytes = data.buffer.asUint8List();
      }
      
      // Decode the image
      final ui.Codec codec = await ui.instantiateImageCodec(_imageBytes!);
      final ui.FrameInfo frameInfo = await codec.getNextFrame();
      _heatMapImage = frameInfo.image;
      
      // Create a new completer if needed
      _imageCompleter ??= Completer<ui.Image>();
      
      if (!_imageCompleter!.isCompleted) {
        _imageCompleter!.complete(_heatMapImage);
      }
      
      debugPrint('Heat map image loaded: ${_heatMapImage!.width}x${_heatMapImage!.height}');
    } catch (e) {
      debugPrint('Failed to load heat map image: $e');
      if (_imageCompleter != null && !_imageCompleter!.isCompleted) {
        _imageCompleter!.completeError(e);
      }
    } finally {
      _isLoading = false;
    }
  }
  
  // Method to reload the image if it was disposed
  Future<void> _reloadImage() async {
    // Reset the completer
    _imageCompleter = Completer<ui.Image>();
    // Reset the image reference
    _heatMapImage = null;
    // Load the image again
    await _loadImage();
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

// Custom heat map layer for FlutterMap - uses OverlayImageLayer for proper geo-anchoring
class HeatMapLayer extends StatefulWidget {
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
  State<HeatMapLayer> createState() => _HeatMapLayerState();
}

class _HeatMapLayerState extends State<HeatMapLayer> {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ui.Image>(
      future: widget.surgeService.heatMapImage,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.hasError) {
          debugPrint("HeatMapLayer: Image not available or error: ${snapshot.error}");
          return const SizedBox.shrink();
        }

        // Calculate bounds for the heat map overlay based on the center and range
        // Using a scale factor to make the heat map smaller (0.5 = half the size)
        final double scaleFactor = 0.5; // Scale down to 50% of original size
        final double rangeInKm = widget.surgeService._range;
        final Distance distance = const Distance();
        
        // Calculate the bounds (create a square around the center position)
        final LatLng northEast = distance.offset(
          widget.centerPosition,
          rangeInKm * 1000 * scaleFactor / math.sqrt(2),
          45.0 // Northeast bearing
        );
        
        final LatLng southWest = distance.offset(
          widget.centerPosition,
          rangeInKm * 1000 * scaleFactor / math.sqrt(2),
          225.0 // Southwest bearing
        );
        
        return OverlayImageLayer(
          overlayImages: [
            OverlayImage(
              // Use the bounds calculated from your center position and range
              bounds: LatLngBounds(
                northEast,
                southWest
              ),
              opacity: widget.opacity * 2.0,
              imageProvider: _HeatMapImageProvider(snapshot.data!),
            ),
          ],
        );
      },
    );
  }
}

// Custom ImageProvider that converts a ui.Image to an ImageProvider
class _HeatMapImageProvider extends ImageProvider<_HeatMapImageProvider> {
  final ui.Image image;
  
  _HeatMapImageProvider(this.image);
  
  @override
  Future<_HeatMapImageProvider> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<_HeatMapImageProvider>(this);
  }
  
  @override
  ImageStreamCompleter loadImage(_HeatMapImageProvider key, ImageDecoderCallback decode) {
    return OneFrameImageStreamCompleter(_loadImage());
  }
  
  Future<ImageInfo> _loadImage() async {
    return ImageInfo(image: image);
  }
}
