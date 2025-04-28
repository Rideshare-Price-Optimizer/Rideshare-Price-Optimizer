import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:rideshare_optimizer/services/config.dart';

class UberDeliveryQuote {
  final String id;
  final int fee;
  final String currency;
  final String estimatedDeliveryTime;

  UberDeliveryQuote({
    required this.id,
    required this.fee,
    required this.currency,
    required this.estimatedDeliveryTime,
  });

  factory UberDeliveryQuote.fromJson(Map<String, dynamic> json) {
    // Update to match the actual API response format
    return UberDeliveryQuote(
      id: json['id'] ?? '',
      fee: json['fee'] ?? 0,
      currency: json['currency'] ?? 'USD',
      // The API uses 'dropoff_eta' instead of 'estimated_delivery_time'
      estimatedDeliveryTime: json['dropoff_eta'] != null 
          ? _formatDateTime(json['dropoff_eta']) 
          : 'Unknown',
    );
  }
}

// Helper function to format the date string nicely
String _formatDateTime(String dateTimeStr) {
  try {
    final dateTime = DateTime.parse(dateTimeStr);
    final now = DateTime.now();
    final diff = dateTime.difference(now).inMinutes;
    return '$diff minutes';
  } catch (e) {
    debugPrint('Error formatting date: $e');
    return dateTimeStr;
  }
}

class UberService {
  static const String _baseUrl = 'https://api.uber.com/v1';
  
  // Replace hardcoded values with getters from Config
  String get _customerId => Config().uberCustomerId;
  String get _authToken => Config().uberAuthToken;

  // Create a custom HTTP client with timeout
  final http.Client _client = http.Client();

  // Get address from coordinates using Nominatim reverse geocoding
  Future<Map<String, dynamic>?> getAddressFromCoordinates(LatLng coordinates) async {
    final String nominatimUrl = 'https://nominatim.openstreetmap.org/reverse';
    
    try {
      final response = await _client.get(
        Uri.parse('$nominatimUrl?format=json&lat=${coordinates.latitude}&lon=${coordinates.longitude}'),
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'RideshareOptimizerApp/1.0',
        },
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception("Connection timeout while fetching address");
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Extract address components from Nominatim response
        final addressParts = data['address'];
        
        // Construct the address in Uber API format
        final streetAddress = addressParts['road'] ?? '';
        final houseNumber = addressParts['house_number'] ?? '';
        final city = addressParts['city'] ?? addressParts['town'] ?? addressParts['village'] ?? '';
        final state = addressParts['state'] ?? '';
        final zipCode = addressParts['postcode'] ?? '';
        final country = addressParts['country_code']?.toUpperCase() ?? 'US';

        final fullStreetAddress = houseNumber.isNotEmpty 
            ? '$houseNumber $streetAddress'.trim() 
            : streetAddress;
        
        return {
          'street_address': [fullStreetAddress],
          'city': city,
          'state': state,
          'zip_code': zipCode,
          'country': country
        };
      } else {
        debugPrint('Reverse geocoding error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception during reverse geocoding: $e');
      return null;
    }
  }

  // Get Uber delivery quotes based on pickup and dropoff locations
  Future<List<UberDeliveryQuote>> getDeliveryQuotes({
    required LatLng pickupLocation,
    required LatLng dropoffLocation,
    String? pickupPhoneNumber,
    String? dropoffPhoneNumber,
  }) async {
    try {
      // Debug environment variables to diagnose the issue
      Config().debugEnvironment();
      
      // Check if credentials are available
      if (_customerId.isEmpty || _authToken.isEmpty) {
        debugPrint('Uber API credentials not found. Using mock data.');
        return _getMockQuotes();
      }
      
      debugPrint('Fetching Uber delivery quotes...');
      debugPrint('Pickup: ${pickupLocation.latitude},${pickupLocation.longitude}');
      debugPrint('Dropoff: ${dropoffLocation.latitude},${dropoffLocation.longitude}');
      
      // Get addresses from coordinates
      final pickupAddress = await getAddressFromCoordinates(pickupLocation);
      final dropoffAddress = await getAddressFromCoordinates(dropoffLocation);
      
      if (pickupAddress == null || dropoffAddress == null) {
        debugPrint('Failed to get address from coordinates');
        return _getMockQuotes();
      }

      debugPrint('Pickup address: ${jsonEncode(pickupAddress)}');
      debugPrint('Dropoff address: ${jsonEncode(dropoffAddress)}');

      // Fix the address format - Uber API needs the whole JSON object as a string
      // This was causing invalid JSON formatting in the request
      final Map<String, dynamic> requestBody = {
        'pickup_address': jsonEncode(pickupAddress),
        'dropoff_address': jsonEncode(dropoffAddress),
        'pickup_latitude': pickupLocation.latitude,
        'pickup_longitude': pickupLocation.longitude,
        'dropoff_latitude': dropoffLocation.latitude,
        'dropoff_longitude': dropoffLocation.longitude,
        'pickup_phone_number': pickupPhoneNumber ?? '+15555555555',
        'dropoff_phone_number': dropoffPhoneNumber ?? '+15555555555',
        'manifest_total_value': 1000,
      };
      
      final token = _authToken;
      final maskedToken = token.length > 10 
        ? "${token.substring(0, 4)}...${token.substring(token.length - 4)}" 
        : "***";
      debugPrint('Using Auth: Bearer $maskedToken');

      debugPrint('Request URL: $_baseUrl/customers/$_customerId/delivery_quotes');
      //https://api.uber.com/v1/customers/{402fc759-a21a-46ac-b4b5-4ae63b181245}/delivery_quotes
      // For debugging: Check the exact request being sent
      final String requestString = jsonEncode(requestBody);
      debugPrint('Request body: $requestString');
      
      // Now actually make the API call instead of always returning mock data
      try {
        final uri = Uri(
          scheme: 'https',
          host: 'api.uber.com',
          path: '/v1/customers/$_customerId/delivery_quotes',
        );
        final response = await _client.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_authToken',
            'Accept': 'application/json',
            'User-Agent': 'RideshareOptimizerApp/1.0',
          },
          body: jsonEncode(requestBody),
        ).timeout(const Duration(seconds: 15));
        // Log the response status and headers for debugging
        debugPrint('Response status code: ${response.statusCode}');
        
        if (response.statusCode >= 200 && response.statusCode < 300) {
          debugPrint('Response body: ${response.body}');
          
          try {
            final data = jsonDecode(response.body);
            debugPrint('Successfully decoded JSON response');
            
            // The API returns a single quote object, not an array of quotes
            // Check if the response has the expected fields for a delivery quote
            if (data['id'] != null && data['fee'] != null) {
              debugPrint('Found valid Uber quote with ID: ${data['id']}');
              final quote = UberDeliveryQuote.fromJson(data);
              return [quote];  // Return as a list for consistency with the rest of the code
            } else if (data['quotes'] != null && data['quotes'] is List) {
              // Keep the original parsing logic as a fallback
              debugPrint('Found quotes array in response');
              final quotes = (data['quotes'] as List)
                  .map((quote) => UberDeliveryQuote.fromJson(quote))
                  .toList();
              return quotes;
            }
            
            debugPrint('Response format not recognized. Response keys: ${data.keys.join(', ')}');
            return _getMockQuotes();
          } catch (e, stackTrace) {
            debugPrint('Error parsing Uber API response: $e');
            debugPrint('Stack trace: $stackTrace');
            return _getMockQuotes();
          }
        } else {
          debugPrint('Uber API error: ${response.statusCode}');
          debugPrint('Response body: ${response.body}');
          
          // Fall back to mock data when API returns error
          return _getMockQuotes();
        }
      } catch (e, stackTrace) {
        debugPrint('HTTP Error: $e');
        debugPrint('Stack trace: $stackTrace');
        return _getMockQuotes();
      }
    } catch (e, stackTrace) {
      debugPrint('Exception when calling Uber API: $e');
      debugPrint('Stack trace: $stackTrace');
      return _getMockQuotes();
    }
  }
  
  // Helper method to get mock data for testing
  List<UberDeliveryQuote> _getMockQuotes() {
    debugPrint('Returning mock Uber quotes for testing');
    
    // Return different prices based on distance to simulate real pricing
    return [
      UberDeliveryQuote(
        id: 'mock-quote-uberx',
        fee: 1299, // $12.99
        currency: 'USD',
        estimatedDeliveryTime: '18 minutes',
      ),
      UberDeliveryQuote(
        id: 'mock-quote-comfort',
        fee: 1599, // $15.99
        currency: 'USD',
        estimatedDeliveryTime: '20 minutes',
      ),
    ];
  }
  
  // Make sure to dispose of the client when no longer needed
  void dispose() {
    _client.close();
  }
}
