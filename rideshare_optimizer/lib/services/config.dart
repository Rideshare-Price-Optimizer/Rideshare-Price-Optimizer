import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

/// Service to manage configuration and API keys
class Config {
  static final Config _instance = Config._internal();
  factory Config() => _instance;
  Config._internal();

  // Cached configuration values
  Map<String, String> _configValues = {};
  bool _isLoaded = false;

  // Default values as fallbacks
  static const Map<String, String> _defaultValues = {
    'UBER_CUSTOMER_ID': 'uberID',
    'UBER_AUTH_TOKEN': 'authToken',
  };

  /// Load configuration from keys.env file
  Future<void> load() async {
    if (_isLoaded) return;

    try {
      String configContent;
      if (kIsWeb) {
        // For web, load as asset
        try {
          configContent = await rootBundle.loadString('assets/keys.env');
        } catch (e) {
          debugPrint('Could not load keys.env as asset: $e');
          configContent = '';
        }
      } else {
        // For mobile, try to load from file
        try {
          final file = File('keys.env');
          if (await file.exists()) {
            configContent = await file.readAsString();
          } else {
            // Try loading as asset
            configContent = await rootBundle.loadString('assets/keys.env');
          }
        } catch (e) {
          debugPrint('Could not load keys.env: $e');
          configContent = '';
        }
      }

      // Parse config content
      if (configContent.isNotEmpty) {
        final lines = LineSplitter.split(configContent)
            .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('//'));
        
        for (var line in lines) {
          final parts = line.split('=');
          if (parts.length == 2) {
            final key = parts[0].trim();
            final value = parts[1].trim();
            _configValues[key] = value;
          }
        }
        
        debugPrint('Configuration loaded: ${_configValues.keys.join(', ')}');
      } else {
        debugPrint('Using default configuration values');
        _configValues = Map.from(_defaultValues);
      }
    } catch (e) {
      debugPrint('Error loading configuration: $e');
      _configValues = Map.from(_defaultValues);
    }

    _isLoaded = true;
  }

  /// Get a configuration value by key
  String getValue(String key) {
    return _configValues[key] ?? _defaultValues[key] ?? '';
  }

  /// Save a configuration value
  Future<void> saveValue(String key, String value) async {
    if (kIsWeb) {
      debugPrint('Cannot save configuration values in web mode');
      return;
    }

    _configValues[key] = value;

    try {
      final file = File('keys.env');
      final buffer = StringBuffer();
      
      // Add each key-value pair
      _configValues.forEach((key, value) {
        buffer.writeln('$key=$value');
      });

      // Write to file
      await file.writeAsString(buffer.toString());
      debugPrint('Saved configuration to keys.env');
    } catch (e) {
      debugPrint('Error saving configuration: $e');
    }
  }

  /// Get Uber customer ID
  String get uberCustomerId => getValue('UBER_CUSTOMER_ID');

  /// Get Uber auth token
  String get uberAuthToken => getValue('UBER_AUTH_TOKEN');
}
