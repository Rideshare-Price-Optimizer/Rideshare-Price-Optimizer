import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart'; // Add this import

class NominatimPlace {
  final String displayName;
  final String placeId;
  final double lat;
  final double lon;
  final String type;
  double? distance; // Add distance field

  NominatimPlace({
    required this.displayName,
    required this.placeId,
    required this.lat,
    required this.lon,
    required this.type,
    this.distance,
  });

  factory NominatimPlace.fromJson(Map<String, dynamic> json) {
    return NominatimPlace(
      displayName: json['display_name'],
      placeId: json['place_id'].toString(),
      lat: double.parse(json['lat']),
      lon: double.parse(json['lon']),
      type: json['type'],
    );
  }
}

class PlacesService {
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  
  // Calculate distance between two coordinates using Haversine formula
  double calculateDistance(LatLng point1, LatLng point2) {
    const Distance distance = Distance();
    return distance.as(LengthUnit.Kilometer, point1, point2);
  }

  Future<List<NominatimPlace>> searchPlaces(String query, {LatLng? userLocation}) async {
    if (query.isEmpty) return [];

    // Build the base URL with improved parameters
    String urlString = '$_baseUrl/search?format=json&q=$query&limit=15&dedupe=1';
    
    // Add user location to improve proximity-based results
    if (userLocation != null) {
      // Add explicit lat/lon for proximity reference
      urlString += '&lat=${userLocation.latitude}&lon=${userLocation.longitude}';
      
      // Create a viewbox around the user's location (approximately 10km in each direction)
      // This will significantly prioritize local results
      const double viewboxDistance = 0.3; // roughly 10km in decimal degrees
      double minLon = userLocation.longitude - viewboxDistance;
      double maxLon = userLocation.longitude + viewboxDistance;
      double minLat = userLocation.latitude - viewboxDistance;
      double maxLat = userLocation.latitude + viewboxDistance;
      
      // Add the viewbox parameter
      urlString += '&viewbox=$minLon,$maxLat,$maxLon,$minLat';
      
      // Set bounded=1 to strongly prefer results within the viewbox
      urlString += '&bounded=1';
    }
    
    final uri = Uri.parse(urlString);
    
    try {
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'RideshareOptimizerApp/1.0',
        },
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        List<NominatimPlace> places = data.map((json) => NominatimPlace.fromJson(json)).toList();
        
        // Calculate and add distance to each place as additional information
        if (userLocation != null) {
          for (var place in places) {
            place.distance = calculateDistance(
              userLocation, 
              LatLng(place.lat, place.lon)
            );
          }
          
          // Double-check sorting by distance (as a fallback)
          // The API should already be sorting, but this ensures consistent behavior
          places.sort((a, b) => (a.distance ?? double.infinity).compareTo(b.distance ?? double.infinity));
        }
        
        return places;
      } else {
        debugPrint('Error: ${response.statusCode} - ${response.body}');
        return [];
      }
    } catch (e) {
      debugPrint('Exception when searching places: $e');
      return [];
    }
  }
}
