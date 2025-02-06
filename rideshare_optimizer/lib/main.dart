import 'package:flutter/material.dart';

// Entry point of the Flutter application
void main() {
  runApp(const RideshareOptimizerApp());
}

// Root widget of the app - StatelessWidget since it won't change after creation
class RideshareOptimizerApp extends StatelessWidget {
  // Constructor with optional named parameter 'key' for widget identification
  const RideshareOptimizerApp({super.key});

  @override
  // Build method defines how the widget looks and behaves
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rideshare Price Optimizer',
      // ThemeData configures the overall visual theme of the app
      theme: ThemeData(
        // ColorScheme defines the app's color palette
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(174, 76, 229, 86),
          brightness: Brightness.dark,
        ),
        // Enable Material Design 3 features
        useMaterial3: true,
        // Configure app bar appearance
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 2,
        ),
      ),
      // Set the home screen widget
      home: const PriceOptimizerScreen(),
    );
  }
}

// Main screen widget - StatefulWidget since it will change based on user interaction
class PriceOptimizerScreen extends StatefulWidget {
  const PriceOptimizerScreen({super.key});

  @override
  // Create the mutable state for this widget
  State<PriceOptimizerScreen> createState() => _PriceOptimizerScreenState();
}

// State class that holds the mutable data for the PriceOptimizerScreen
class _PriceOptimizerScreenState extends State<PriceOptimizerScreen> {
  // State variables to track search status and destination input
  bool _isSearching = false;
  String _destination = '';

  // Method to handle location search
  void _searchNearbyLocations() {
    // setState() tells Flutter to rebuild the UI with new state
    setState(() {
      _isSearching = true;
    });
    // Placeholder for actual search implementation
    Future.delayed(const Duration(seconds: 2), () {
      setState(() {
        _isSearching = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold provides the basic material design layout structure
    return Scaffold(
      // App bar at the top of the screen
      appBar: AppBar(
        title: const Text('Price Optimizer'),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      ),
      // Main body content
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // Column arranges children vertically
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Search input card
            Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Text input field for destination
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Where to?',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        prefixIcon: const Icon(Icons.location_on),
                      ),
                      // Update destination state when text changes
                      onChanged: (value) {
                        setState(() {
                          _destination = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    // Search button
                    ElevatedButton.icon(
                      // Disable button if destination is empty
                      onPressed: _destination.isEmpty ? null : _searchNearbyLocations,
                      icon: const Icon(Icons.search),
                      label: const Text('Find Better Prices'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Results area - expands to fill remaining space
            Expanded(
              // Conditional rendering based on state
              child: _isSearching
                  ? const Center(
                      // Loading indicator when searching
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Searching for better prices...')
                        ],
                      ),
                    )
                  : _destination.isEmpty
                      ? // Show helper text when no destination entered
                        const Center(
                          child: Text(
                            'Enter a destination to find better prices',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : // Show results list when search is complete
                        Card(
                          elevation: 4,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: 5, // Placeholder count
                            // Build list items dynamically
                            itemBuilder: (context, index) {
                              return ListTile(
                                leading: const Icon(Icons.directions_walk),
                                title: Text(
                                  'Option ${index + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                subtitle: Text(
                                  'Walk ${index + 2} min to save \$${(index + 1) * 2}.00',
                                ),
                                trailing: const Icon(Icons.arrow_forward_ios),
                                onTap: () {
                                  // TODO: Implement option selection
                                },
                              );
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
