import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'theme_provider.dart';
import 'settings_page.dart';
import 'services/places_service.dart';
import 'services/uber_service.dart';
import 'services/config.dart';
import 'Database.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  //Initialize env File
  await dotenv.load(fileName: "keys.env");

  // Initialize config (this is fast now, no file loading)
  await Config().load();
  debugPrint('Configuration initialized in main');
  
  // Initialize Supabase 
  await Supabase.initialize(
    url: dotenv.env["SUPABASE_URL"]!,
    anonKey: dotenv.env["SUPABASE_KEY"]!,
  );



  runApp(
    ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const RideshareOptimizerApp(),
    ),
  );
}

class RideshareOptimizerApp extends StatelessWidget {
  const RideshareOptimizerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'Rideshare Price Optimizer',
          debugShowCheckedModeBanner: false,
          theme: themeProvider.theme,
          home: const PriceOptimizerScreen(),
        );
      },
    );
  }
}

class PriceOptimizerScreen extends StatefulWidget {
  const PriceOptimizerScreen({super.key});

  @override
  State<PriceOptimizerScreen> createState() => _PriceOptimizerScreenState();
}

class _PriceOptimizerScreenState extends State<PriceOptimizerScreen> {
  String? _selectedDestination;
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  LatLng _currentLocation = const LatLng(37.7749, -122.4194); // Default to San Francisco
  
  // New properties for search functionality
  final PlacesService _placesService = PlacesService();
  final UberService _uberService = UberService(); // Add this line
  List<NominatimPlace> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounceTimer;
  LatLng? _destinationLocation; // To store the selected location coordinates
  
  // Add this property to store Uber quotes
  List<UberDeliveryQuote>? _uberQuotes;
  bool _fetchingUberQuotes = false;

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debounceTimer?.cancel();
    _uberService.dispose(); // Make sure to dispose of the HTTP client
    super.dispose();
  }

  Future<void> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        Position position = await Geolocator.getCurrentPosition();
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        _mapController.move(_currentLocation, 15);
      }
    } catch (e) {
      // Handle location errors or use default location
      print('Error getting location: $e');
    }
  }

  void _openSearchSheet() {
    // Reset search results
    setState(() {
      _searchResults = [];
      _isLoading = false;
    });
    
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Stack(
              children: [
                // Add a transparent background that handles taps
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () {
                      FocusScope.of(context).unfocus();
                      Navigator.pop(context);
                      setState(() {
                        if (_selectedDestination != null) {
                          _searchController.text = _selectedDestination!;
                        }
                      });
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      color: Colors.transparent,
                    ),
                  ),
                ),
                DraggableScrollableSheet(
                  initialChildSize: 0.6,
                  minChildSize: 0.4,
                  maxChildSize: 0.9,
                  builder: (context, scrollController) {
                    return Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      child: GestureDetector(
                        onTap: () {},
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(top: 12, bottom: 8),
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                decoration: InputDecoration(
                                  hintText: 'Where to?',
                                  hintStyle: TextStyle(color: Colors.grey[600]),
                                  prefixIcon: Icon(Icons.search, color: Colors.grey[600]),
                                  suffixIcon: IconButton(
                                    icon: Icon(Icons.clear, color: Colors.grey[600]),
                                    onPressed: () {
                                      _searchController.clear();
                                      setModalState(() {
                                        _searchResults = [];
                                      });
                                    },
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  filled: true,
                                  fillColor: Colors.grey[100],
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 16,
                                  ),
                                ),
                                onChanged: (value) {
                                  // Debounce search to avoid API rate limiting
                                  if (_debounceTimer?.isActive ?? false) {
                                    _debounceTimer!.cancel();
                                  }
                                  
                                  _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                                    if (value.trim().isNotEmpty) {
                                      setModalState(() {
                                        _isLoading = true;
                                      });
                                      
                                      // Pass user's current location to improve proximity-based results
                                      _placesService.searchPlaces(value, userLocation: _currentLocation).then((results) {
                                        setModalState(() {
                                          _searchResults = results;
                                          _isLoading = false;
                                        });
                                      }).catchError((error) {
                                        debugPrint('Search error: $error');
                                        setModalState(() {
                                          _isLoading = false;
                                        });
                                      });
                                    } else {
                                      setModalState(() {
                                        _searchResults = [];
                                      });
                                    }
                                  });
                                },
                              ),
                            ),
                            Expanded(
                              child: _isLoading
                                ? const Center(child: CircularProgressIndicator())
                                : _searchController.text.isEmpty
                                  ? Center(
                                      child: Text(
                                        'Search for a destination',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 16,
                                        ),
                                      ),
                                    )
                                  : _searchResults.isEmpty
                                    ? Center(
                                        child: Text(
                                          'No results found',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 16,
                                          ),
                                        ),
                                      )
                                    : ListView.builder(
                                        controller: scrollController,
                                        padding: const EdgeInsets.symmetric(horizontal: 16),
                                        itemCount: _searchResults.length,
                                        itemBuilder: (context, index) {
                                          final place = _searchResults[index];
                                          return _buildPlaceItem(place, context);
                                        },
                                      ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      // Update search bar text when bottom sheet is closed
      if (_selectedDestination != null) {
        _searchController.text = _selectedDestination!;
      }
    });
  }

  // New method to build place item
  Widget _buildPlaceItem(NominatimPlace place, BuildContext context) {
    String? distanceText;
    if (place.distance != null) {
      if (place.distance! < 1) {
        // Convert to meters for distances less than 1km
        int meters = (place.distance! * 1000).round();
        distanceText = '$meters m';
      } else {
        distanceText = '${place.distance!.toStringAsFixed(1)} km';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: () => _selectPlace(place),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.place,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _getMainText(place.displayName),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _getSecondaryText(place.displayName),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (distanceText != null)
                          Text(
                            distanceText,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper methods for formatting place names
  String _getMainText(String displayName) {
    final parts = displayName.split(',');
    if (parts.isNotEmpty) {
      return parts[0].trim();
    }
    return displayName;
  }

  String _getSecondaryText(String displayName) {
    final parts = displayName.split(',');
    if (parts.length > 1) {
      return parts.sublist(1).join(',').trim();
    }
    return '';
  }

  void _selectPlace(NominatimPlace place) {
    final latLng = LatLng(place.lat, place.lon);
    
    // Debug output
    debugPrint('Selected place: ${place.displayName}');
    debugPrint('Latitude: ${place.lat}, Longitude: ${place.lon}');
    
    setState(() {
      _selectedDestination = place.displayName;
      _destinationLocation = latLng;
      _uberQuotes = null; // Reset previous quotes
    });
    
    // Move map to selected location
    _mapController.move(latLng, 15);
    
    // Close the bottom sheet
    Navigator.pop(context);
    
    // Fetch Uber quotes
    _getUberQuotes();
  }

  // Updated method to fetch Uber quotes with better error handling
  Future<void> _getUberQuotes() async {
    if (_destinationLocation == null) return;
    
    setState(() {
      _fetchingUberQuotes = true;
    });
    
    try {
      // Show that we're trying to fetch quotes
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fetching Uber ride prices...'),
          duration: Duration(seconds: 2),
        ),
      );
      
      final quotes = await _uberService.getDeliveryQuotes(
        pickupLocation: _currentLocation,
        dropoffLocation: _destinationLocation!,
      );
      
      setState(() {
        _uberQuotes = quotes;
        _fetchingUberQuotes = false;
      });
      
      // Display results
      if (quotes.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Uber quote: \$${(quotes[0].fee / 100).toStringAsFixed(2)} ${quotes[0].currency}'),
            duration: const Duration(seconds: 4),
          ),
        );
        Database.updateDatabase(quotes[0].fee/100, _currentLocation, _destinationLocation);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No Uber quotes available for this route'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching Uber quotes: $e');
      setState(() {
        _fetchingUberQuotes = false;
      });
      
      // Show a more user-friendly error message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not get Uber prices. ${e.toString().contains("Connection timeout") ? "Check your internet connection." : ""}'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'Retry',
            onPressed: _getUberQuotes,
          ),
        ),
      );
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map implementation using Flutter Map
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentLocation,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.app',
              ),
              // Marker layer with both current location and destination (if selected)
              MarkerLayer(
                markers: [
                  Marker(
                    point: _currentLocation,
                    width: 40,
                    height: 40,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.2),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.my_location,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                  // Add destination marker if available
                  if (_destinationLocation != null)
                    Marker(
                      point: _destinationLocation!,
                      width: 40,
                      height: 40,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.place,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
          // Settings button
          Positioned(
            top: MediaQuery.of(context).padding.top + 16,
            right: 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SettingsPage()),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(
                    Icons.settings,
                    color: Colors.black87,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          // Search bar
          Positioned(
            left: 16,
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: _openSearchSheet,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, color: Colors.grey[600]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _selectedDestination ?? 'Where to?',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Location centering button
          Positioned(
            right: 16,
            bottom: MediaQuery.of(context).padding.bottom + 80, // Position above search bar
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(32),
              child: InkWell(
                onTap: () {
                  // Center map on current location
                  _mapController.move(_currentLocation, 15);
                },
                borderRadius: BorderRadius.circular(32),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.my_location,
                    color: Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          // Selected destination overlay
          if (_selectedDestination != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.directions,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Route to $_selectedDestination',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _selectedDestination = null;
                            _uberQuotes = null;
                          }),
                        ),
                      ],
                    ),
                    
                    // Add Uber quote info
                    if (_fetchingUberQuotes)
                      const Padding(
                        padding: EdgeInsets.only(top: 8.0),
                        child: Center(
                          child: SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      )
                    else if (_uberQuotes != null && _uberQuotes!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            // Fix the image path or use icon directly
                            Icon(
                              Icons.local_taxi,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Uber: \$${(_uberQuotes![0].fee / 100).toStringAsFixed(2)} ${_uberQuotes![0].currency}',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}