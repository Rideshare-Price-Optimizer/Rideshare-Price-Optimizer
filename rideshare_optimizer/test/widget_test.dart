// Import required Flutter packages for widget testing
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// Import the main app file that contains our root widget
import 'package:rideshare_optimizer/main.dart';

void main() {
  // Define a widget test using testWidgets function
  // WidgetTester provides utilities to interact with and test widgets
  testWidgets('Counter increments smoke test', (WidgetTester tester) async {
    // pumpWidget creates an instance of your app in the test environment
    // and triggers a frame (renders the UI)
    await tester.pumpWidget(const RideshareOptimizerApp());

    // find.text() is a Finder that locates widgets containing specific text
    // expect() makes assertions about what should be found in the widget tree
    expect(find.text('0'), findsOneWidget);    // Verify exactly one '0' exists
    expect(find.text('1'), findsNothing);      // Verify no '1' exists yet

    // Simulate user interaction: tap the add button
    // find.byIcon locates widgets by their Icons
    await tester.tap(find.byIcon(Icons.add));
    // pump() tells the tester to rebuild the widget tree after the interaction
    await tester.pump();

    // Verify the counter value changed after tapping
    expect(find.text('0'), findsNothing);      // '0' should no longer exist
    expect(find.text('1'), findsOneWidget);    // Exactly one '1' should exist
  });
}
