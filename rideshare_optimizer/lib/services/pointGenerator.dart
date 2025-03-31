import 'dart:math';
import 'package:geolocator/geolocator.dart';

class PointGenerator {
  final double mainCircleRadius;
  final double subCircleRadius;

  PointGenerator({required this.mainCircleRadius, required this.subCircleRadius});

  List<Position> generateDestinationPoints(Position origin) {
    List<Position> destinationPoints = [];

    for (int i = 0; i < 4; i++) {
      double angle = i * (pi / 2); // Bearings in radians: 0, π/2, π, 3π/2
      Position mainPoint = calculateDestination(origin, mainCircleRadius, angle);

      for (int j = 0; j < 3; j++) {
        double subAngle = j * (2 * pi / 3); // Bearings: 0, 120°, 240° in radians
        Position subPoint = calculateDestination(mainPoint, subCircleRadius, subAngle);
        destinationPoints.add(subPoint);
      }
    }

    return destinationPoints;
  }

  Position calculateDestination(Position origin, double distance, double bearingRad) {
    const double earthRadius = 6371000; // meters

    double latRad = degreesToRadians(origin.latitude);
    double lonRad = degreesToRadians(origin.longitude);

    double lat2Rad = asin(
      sin(latRad) * cos(distance / earthRadius) +
      cos(latRad) * sin(distance / earthRadius) * cos(bearingRad)
    );

    double lon2Rad = lonRad + atan2(
      sin(bearingRad) * sin(distance / earthRadius) * cos(latRad),
      cos(distance / earthRadius) - sin(latRad) * sin(lat2Rad)
    );

    return Position(
      latitude: radiansToDegrees(lat2Rad),
      longitude: radiansToDegrees(lon2Rad),
      timestamp: DateTime.now(),
      accuracy: 0,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }

  double degreesToRadians(double degrees) => degrees * pi / 180;
  double radiansToDegrees(double radians) => radians * 180 / pi;
}
