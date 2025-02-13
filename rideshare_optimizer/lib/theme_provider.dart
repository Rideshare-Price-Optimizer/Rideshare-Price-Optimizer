import 'package:flutter/material.dart';

class ThemeProvider with ChangeNotifier {
  Color _themeColor = const Color(0xFF2E7D32); // Default forest green

  Color get themeColor => _themeColor;

  void setThemeColor(Color color) {
    _themeColor = color;
    notifyListeners();
  }

  ThemeData get theme => ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _themeColor,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      );
}
