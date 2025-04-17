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
      String configContent = "";
      if (kIsWeb) {
        // For web, load as asset
        try {
          configContent = await rootBundle.loadString('assets/keys.env');
        } catch (e) {
          debugPrint('Could not load keys.env as asset: $e');
          configContent = '';
        }
      } else {
        // For mobile, try multiple possible locations for the keys.env file
        try {
          // Try the project directory first (where pubspec.yaml is located)
          final projectDir = Directory.current.absolute.path;
          debugPrint('Current directory: $projectDir');
          
          // List of possible file locations to try
          final locations = [
            // The exact location in GitHub repo
            '/Users/zacharytgray/Documents/GitHub/Rideshare-Price-Optimizer/rideshare_optimizer/keys.env',
            // Current directory
            '$projectDir/keys.env',
            // One level up
            '${projectDir}/../keys.env',
            // Try the standard asset location
            '$projectDir/lib/keys.env',
          ];
          
          bool fileFound = false;
          for (final path in locations) {
            debugPrint('Trying to load keys.env from: $path');
            final file = File(path);
            if (await file.exists()) {
              configContent = await file.readAsString();
              debugPrint('Successfully loaded keys.env from: $path');
              fileFound = true;
              break;
            }
          }
          
          // If file not found in any location, try as asset
          if (!fileFound) {
            debugPrint('Could not find keys.env file, trying as asset');
            try {
              // Try without 'assets/' prefix first (as specified in pubspec.yaml)
              configContent = await rootBundle.loadString('keys.env');
              debugPrint('Successfully loaded keys.env from Flutter assets');
            } catch (assetError) {
              debugPrint('Could not load keys.env directly: $assetError');
              // Fallback to trying with the 'assets/' prefix
              try {
                configContent = await rootBundle.loadString('assets/keys.env');
                debugPrint('Successfully loaded keys.env from assets/keys.env');
              } catch (e) {
                debugPrint('Could not load keys.env from assets either: $e');
                // Last resort: try to find the keys.env file anywhere in the app bundle
                try {
                  final manifestContent = await rootBundle.loadString('AssetManifest.json');
                  final Map<String, dynamic> manifestMap = json.decode(manifestContent);
                  final keyFiles = manifestMap.keys.where((String key) => key.contains('keys.env')).toList();
                  
                  if (keyFiles.isNotEmpty) {
                    debugPrint('Found keys.env in manifest at: ${keyFiles.first}');
                    configContent = await rootBundle.loadString(keyFiles.first);
                  } else {
                    debugPrint('No keys.env found in AssetManifest');
                  }
                } catch (manifestError) {
                  debugPrint('Error checking asset manifest: $manifestError');
                }
              }
            }
          }
        } catch (e) {
          debugPrint('Could not load keys.env: $e');
          configContent = '';
        }
      }

      // Parse config content
      if (configContent.isNotEmpty) {
        debugPrint('Config content found with length: ${configContent.length}');
        debugPrint('First 10 chars (sanitized): ${configContent.substring(0, configContent.length > 10 ? 10 : configContent.length).replaceAll(RegExp(r'[^\s\w]'), '*')}...');
        
        final lines = LineSplitter.split(configContent)
            .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('//'));
        
        for (var line in lines) {
          debugPrint('Processing config line: ${line.length > 10 ? "${line.substring(0, 10)}..." : line}');
          final parts = line.split('=');
          if (parts.length == 2) {
            final key = parts[0].trim();
            final value = parts[1].trim();
            _configValues[key] = value;
            debugPrint('Added config key: $key with value: ${value.length > 5 ? "${value.substring(0, 5)}***" : "***"}');
          } else {
            debugPrint('Invalid config line format: ${line.length > 10 ? "${line.substring(0, 10)}..." : line}');
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
  
  /// Debug method to print information about the environment variables
  void debugEnvironment() {
    debugPrint('===== Environment Configuration Debug =====');
    debugPrint('Config loaded: $_isLoaded');
    debugPrint('Config keys found: ${_configValues.keys.join(', ')}');
    
    // Check Uber credentials specifically
    final customerId = uberCustomerId;
    final authToken = uberAuthToken;
    
    debugPrint('UBER_CUSTOMER_ID is ${customerId.isEmpty ? 'EMPTY' : 'set'} (${customerId.length} chars)');
    debugPrint('UBER_AUTH_TOKEN is ${authToken.isEmpty ? 'EMPTY' : 'set'} (${authToken.length} chars)');
    
    // Check if using defaults
    debugPrint('Using default UBER_CUSTOMER_ID: ${customerId == _defaultValues['UBER_CUSTOMER_ID']}');
    debugPrint('Using default UBER_AUTH_TOKEN: ${authToken == _defaultValues['UBER_AUTH_TOKEN']}');
    debugPrint('=========================================');
  }
}