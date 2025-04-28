import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'dart:ui' as ui;
import 'dart:math';
import 'theme_provider.dart';
import 'settings_page.dart';
import 'services/places_service.dart';
import 'services/uber_service.dart';
import 'services/config.dart';
import 'database.dart';
import 'services/surge_service.dart';

class WalkingPickupPoint {
  final LatLng location;
  final double distance; // in meters
  final double surgeMultiplier;
  final double estimatedPrice;
  final String currency;
  final String displayName;

  WalkingPickupPoint({
    required this.location,
    required this.distance,
    required this.surgeMultiplier,
    required this.estimatedPrice,
    required this.currency,
    required this.displayName,
  });
}

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
  final UberService _uberService = UberService();
  final SurgeService _surgeService = SurgeService(); // Add surge service
  List<NominatimPlace> _searchResults = [];
  bool _isLoading = false;
  Timer? _debounceTimer;
  LatLng? _destinationLocation; // To store the selected location coordinates
  
  // Add these properties to store Uber quotes and surge information
  List<UberDeliveryQuote>? _uberQuotes;
  bool _fetchingUberQuotes = false;
  double _surgeMultiplier = 1.0; // Default surge multiplier (no surge)
  bool _showHeatMap = false; // Don't show the heat map overlay - only use it for calculations

  // Add this list to store the generated walking pickup points
  List<WalkingPickupPoint> _walkingPickupPoints = [];
  bool _fetchingWalkingPoints = false;
  bool _showWalkingPointsPanel = false; // Track visibility of walking points panel

  // Method to toggle the surge price heat map overlay
  void _toggleSurgeHeatMap() {
    setState(() {
      _showHeatMap = !_showHeatMap;
    });
    
    // Show a message to the user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_showHeatMap 
          ? 'Surge price heat map activated' 
          : 'Surge price heat map deactivated'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _initializeSurgeService();
  }
  
  // Initialize the surge service
  Future<void> _initializeSurgeService() async {
    await _surgeService.init();
    // Set the geographic range for the heat map (in km)
    _surgeService.setRange(5.0);
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
      
      // Reset walking pickup points and related properties
      _walkingPickupPoints = [];
      _showWalkingPointsPanel = false;
      _currentWalkingPointMarker = null;
    });
    
    // Move map to selected location
    _mapController.move(latLng, 15);
    
    // Close the bottom sheet
    Navigator.pop(context);
    
    // Fetch Uber quotes
    _getUberQuotes();
  }

  // Updated method to fetch Uber quotes with surge pricing
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
      
      // Get the base quotes
      final quotes = await _uberService.getDeliveryQuotes(
        pickupLocation: _currentLocation,
        dropoffLocation: _destinationLocation!,
      );
      
      // Get the surge multiplier for the user's current location (pickup point)
      _surgeMultiplier = await _surgeService.getSurgeMultiplier(
        _currentLocation,
        _currentLocation
      );
      
      debugPrint('Calculated surge multiplier: $_surgeMultiplier');
      
      setState(() {
        _uberQuotes = quotes;
        _fetchingUberQuotes = false;
      });
      
      // Display results with surge pricing applied
      if (quotes.isNotEmpty) {
        // Apply surge pricing to display price
        final double basePrice = quotes[0].fee / 100;
        final double surgePrice = basePrice * _surgeMultiplier;
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _surgeMultiplier > 1.05 
                ? 'Uber quote: \$${surgePrice.toStringAsFixed(2)} ${quotes[0].currency} (${_surgeMultiplier.toStringAsFixed(1)}x surge)'
                : 'Uber quote: \$${surgePrice.toStringAsFixed(2)} ${quotes[0].currency}'
            ),
            duration: const Duration(seconds: 4),
          ),
        );
        Database.addRide(quotes[0].fee/100, _currentLocation, _destinationLocation);
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

  // Generate random walking points around the user's current location
  Future<List<LatLng>> _generateRandomWalkingPoints(int count, double radiusInMeters) async {
    final List<LatLng> points = [];
    final Random random = Random();
    final Distance distance = const Distance();
    
    for (int i = 0; i < count; i++) {
      // Generate random angle and distance
      final double angle = random.nextDouble() * 2 * pi;
      // Random distance within the walking radius (50-100% of max radius)
      final double randomDistance = (0.5 + random.nextDouble() * 0.5) * radiusInMeters;
      
      // Calculate new point
      final LatLng point = distance.offset(
        _currentLocation,
        randomDistance,
        angle * (180 / pi) // Convert to degrees for the offset function
      );
      
      points.add(point);
    }
    
    return points;
  }

  // Find walking pickup points with better prices
  Future<void> _findOptimizedPickupPoints() async {
    if (_destinationLocation == null) return;
    
    setState(() {
      _fetchingWalkingPoints = true;
      _walkingPickupPoints = [];
    });
    
    try {
      // Generate 5 random points within 800 meters (reasonable walking distance)
      final List<LatLng> walkingPoints = await _generateRandomWalkingPoints(5, 800);
      
      // Add the current location as the first point to consider
      walkingPoints.insert(0, _currentLocation);
      
      final List<WalkingPickupPoint> candidatePoints = [];
      final Distance distance = const Distance();
      
      // Base quote for comparison
      final double basePrice = _uberQuotes != null && _uberQuotes!.isNotEmpty 
          ? _uberQuotes![0].fee / 100 * _surgeMultiplier
          : 0;
      
      // Process each walking point
      for (int i = 0; i < walkingPoints.length; i++) {
        final LatLng point = walkingPoints[i];
        
        // Calculate distance from user to this point
        final double walkingDistance = distance.distance(_currentLocation, point);
        
        // Calculate surge multiplier at this location
        final double pointSurgeMultiplier = await _surgeService.getSurgeMultiplier(
          point,
          _currentLocation
        );
        
        // Get ride quotes from this point to destination
        List<UberDeliveryQuote> pointQuotes = [];
        try {
          pointQuotes = await _uberService.getDeliveryQuotes(
            pickupLocation: point,
            dropoffLocation: _destinationLocation!,
          );
        } catch (e) {
          debugPrint('Error getting quotes for point $i: $e');
          continue; // Skip this point if quotes can't be fetched
        }
        
        if (pointQuotes.isEmpty) continue;
        
        // Calculate price with surge for this point
        final double pointBasePrice = pointQuotes[0].fee / 100;
        final double pointTotalPrice = pointBasePrice * pointSurgeMultiplier;
        
        // Get address info for the point
        String pointAddress = 'Walking Point ${i + 1}';
        try {
          final addressInfo = await _uberService.getAddressFromCoordinates(point);
          if (addressInfo != null && addressInfo.containsKey('display_name')) {
            pointAddress = _getMainText(addressInfo['display_name']);
          }
        } catch (e) {
          debugPrint('Error getting address for point $i: $e');
        }
        
        // Add to candidate points
        candidatePoints.add(WalkingPickupPoint(
          location: point,
          distance: walkingDistance,
          surgeMultiplier: pointSurgeMultiplier,
          estimatedPrice: pointTotalPrice,
          currency: pointQuotes[0].currency,
          displayName: i == 0 
            ? 'Current Location (no walking needed)'
            : '$pointAddress (${(walkingDistance).round()}m walk)',
        ));
      }
      
      // Sort by price
      candidatePoints.sort((a, b) => a.estimatedPrice.compareTo(b.estimatedPrice));
      
      setState(() {
        _walkingPickupPoints = candidatePoints;
        _fetchingWalkingPoints = false;
      });
      
      // Show a message about potential savings
      if (candidatePoints.isNotEmpty && basePrice > 0) {
        final double bestPrice = candidatePoints[0].estimatedPrice;
        final double savings = basePrice - bestPrice;
        
        if (savings > 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Found a pickup point that saves \$${savings.toStringAsFixed(2)}!',
              ),
              duration: const Duration(seconds: 6),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error finding optimized pickup points: $e');
      setState(() {
        _fetchingWalkingPoints = false;
      });
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
              // Add surge heat map overlay
              if (_showHeatMap)
                FutureBuilder<ui.Image>(
                  future: _surgeService.heatMapImage,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.hasError) {
                      return const SizedBox.shrink();
                    }
                    return HeatMapLayer(
                      centerPosition: _currentLocation,
                      surgeService: _surgeService,
                      opacity: 0.25, // Reduced opacity to make it very faint
                    );
                  },
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
                  // Add walking point marker if selected
                  if (_currentWalkingPointMarker != null)
                    Marker(
                      point: _currentWalkingPointMarker!,
                      width: 40,
                      height: 40,
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green,
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
                          Icons.directions_walk,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                ],
              ),
              // Add polyline between current location and walking point
              if (_currentWalkingPointMarker != null)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: [_currentLocation, _currentWalkingPointMarker!],
                      strokeWidth: 4.0,
                      color: Colors.green,
                      isDotted: true,
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
          
          // Surge Heat Map toggle button - positioned next to the location button
          Positioned(
            right: 76, // 16 (edge margin) + 44 (button width) + 16 (spacing)
            bottom: MediaQuery.of(context).padding.bottom + 80, // Same level as location button
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(32),
              child: InkWell(
                onTap: _toggleSurgeHeatMap,
                borderRadius: BorderRadius.circular(32),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _showHeatMap ? Theme.of(context).colorScheme.primary : Colors.white,
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
                    Icons.layers,
                    color: _showHeatMap ? Colors.white : Theme.of(context).colorScheme.primary,
                    size: 24,
                  ),
                ),
              ),
            ),
          ),
          
          // Walking points optimization button
          Positioned(
            right: 136, // 76 (position of surge button) + 44 (button width) + 16 (spacing)
            bottom: MediaQuery.of(context).padding.bottom + 80, // Same level as location button
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(32),
              child: InkWell(
                onTap: () {
                  if (_destinationLocation != null) {
                    // If we already have walking points, just show the panel
                    if (_walkingPickupPoints.isNotEmpty) {
                      setState(() {
                        _showWalkingPointsPanel = true;
                      });
                    } else {
                      // Otherwise, find new pickup points
                      _findOptimizedPickupPoints();
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please select a destination first'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  }
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
                    Icons.directions_walk,
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
                            Expanded(
                              child: RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: 'Uber: ',
                                      style: TextStyle(
                                        color: Theme.of(context).colorScheme.secondary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '\$${(_uberQuotes![0].fee / 100).toStringAsFixed(2)} × ${_surgeMultiplier.toStringAsFixed(1)} = ',
                                      style: TextStyle(
                                        color: Colors.grey[600],
                                        fontSize: 14,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '\$${((_uberQuotes![0].fee / 100) * _surgeMultiplier).toStringAsFixed(2)} ${_uberQuotes![0].currency}',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

          // Display walking pickup points panel
          if (_walkingPickupPoints.isNotEmpty && _showWalkingPointsPanel)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 80, // Above the search bar
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.directions_walk,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'Optimized Pickup Points',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() {
                            _showWalkingPointsPanel = false; // Hide panel instead of clearing points
                          }),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Walk to these pickup points to save money:',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // List of walking points
                    SizedBox(
                      height: 200, // Fixed height for scrollable list
                      child: ListView.builder(
                        itemCount: _walkingPickupPoints.length,
                        padding: EdgeInsets.zero,
                        itemBuilder: (context, index) {
                          final point = _walkingPickupPoints[index];
                          return _buildWalkingPointItem(point, index);
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Add button to generate more walking points
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.add_location_alt),
                        label: const Text('Find 5 More Walking Locations'),
                        style: ElevatedButton.styleFrom(
                          foregroundColor: Colors.white,
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: _fetchingWalkingPoints ? null : _addMoreWalkingPoints,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          
          // Loading indicator for walking points
          if (_fetchingWalkingPoints)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Finding optimized pickup points...'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // New method to build walking point item
  Widget _buildWalkingPointItem(WalkingPickupPoint point, int index) {
    final bool isBestOption = index == 0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isBestOption ? Colors.green[50] : null,
      child: InkWell(
        onTap: () {
          // Move the map to this pickup point
          _mapController.move(point.location, 16);
          // Show marker for this walking point
          _showWalkingPointMarker(point);
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isBestOption 
                    ? Colors.green[100] 
                    : Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.directions_walk,
                  color: isBestOption 
                    ? Colors.green[800] 
                    : Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      point.displayName,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isBestOption ? Colors.green[800] : null,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.arrow_downward,
                          color: Colors.green,
                          size: 16,
                        ),
                        Text(
                          ' ${point.surgeMultiplier.toStringAsFixed(1)}x surge',
                          style: TextStyle(
                            color: Colors.green[700],
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Spacer(),
                        Text(
                          '\$${point.estimatedPrice.toStringAsFixed(2)}',
                          style: TextStyle(
                            color: isBestOption ? Colors.green[800] : Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
  
  // Variable to track the currently shown walking point marker
  LatLng? _currentWalkingPointMarker;
  
  // Show marker for the selected walking point
  void _showWalkingPointMarker(WalkingPickupPoint point) {
    setState(() {
      _currentWalkingPointMarker = point.location;
    });
    
    // Show a line connecting current location to the walking point
    _drawWalkingPathToPoint(point);
  }
  
  // Draw a walking path from current location to pickup point
  void _drawWalkingPathToPoint(WalkingPickupPoint point) {
    // In a real app, you might want to use a routing API to get the actual walking path
    // For now, we'll just show a straight line
    
    // Show a message about the walking distance
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Walk ${(point.distance).round()} meters to save \$${(_uberQuotes != null && _uberQuotes!.isNotEmpty ? (_uberQuotes![0].fee / 100 * _surgeMultiplier) - point.estimatedPrice : 0).toStringAsFixed(2)}',
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // Add more walking points to the existing list
  Future<void> _addMoreWalkingPoints() async {
    if (_destinationLocation == null) return;

    setState(() {
      _fetchingWalkingPoints = true;
    });

    try {
      // Generate 5 additional random points within 800 meters
      final List<LatLng> additionalWalkingPoints = await _generateRandomWalkingPoints(5, 800);

      final List<WalkingPickupPoint> newCandidatePoints = [];
      final Distance distance = const Distance();

      // Process each additional walking point
      for (int i = 0; i < additionalWalkingPoints.length; i++) {
        final LatLng point = additionalWalkingPoints[i];

        // Calculate distance from user to this point
        final double walkingDistance = distance.distance(_currentLocation, point);

        // Calculate surge multiplier at this location
        final double pointSurgeMultiplier = await _surgeService.getSurgeMultiplier(
          point,
          _currentLocation
        );

        // Get ride quotes from this point to destination
        List<UberDeliveryQuote> pointQuotes = [];
        try {
          pointQuotes = await _uberService.getDeliveryQuotes(
            pickupLocation: point,
            dropoffLocation: _destinationLocation!,
          );
        } catch (e) {
          debugPrint('Error getting quotes for additional point $i: $e');
          continue; // Skip this point if quotes can't be fetched
        }

        if (pointQuotes.isEmpty) continue;

        // Calculate price with surge for this point
        final double pointBasePrice = pointQuotes[0].fee / 100;
        final double pointTotalPrice = pointBasePrice * pointSurgeMultiplier;

        // Get address info for the point
        String pointAddress = 'Walking Point ${_walkingPickupPoints.length + i + 1}';
        try {
          final addressInfo = await _uberService.getAddressFromCoordinates(point);
          if (addressInfo != null && addressInfo.containsKey('display_name')) {
            pointAddress = _getMainText(addressInfo['display_name']);
          }
        } catch (e) {
          debugPrint('Error getting address for additional point $i: $e');
        }

        // Add to new candidate points
        newCandidatePoints.add(WalkingPickupPoint(
          location: point,
          distance: walkingDistance,
          surgeMultiplier: pointSurgeMultiplier,
          estimatedPrice: pointTotalPrice,
          currency: pointQuotes[0].currency,
          displayName: '$pointAddress (${(walkingDistance).round()}m walk)',
        ));
      }

      // Combine with existing walking pickup points and sort by price
      setState(() {
        _walkingPickupPoints.addAll(newCandidatePoints);
        // Re-sort all points by price after adding new ones
        _walkingPickupPoints.sort((a, b) => a.estimatedPrice.compareTo(b.estimatedPrice));
        _fetchingWalkingPoints = false;
        // Ensure the panel is visible
        _showWalkingPointsPanel = true;
      });

      // Show a message about the new points
      if (newCandidatePoints.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${newCandidatePoints.length} more pickup points',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }

    } catch (e) {
      debugPrint('Error adding more walking points: $e');
      setState(() {
        _fetchingWalkingPoints = false;
      });
    }
  }
}