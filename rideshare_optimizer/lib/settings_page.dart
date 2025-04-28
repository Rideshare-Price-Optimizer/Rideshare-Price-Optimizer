import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'theme_provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();

static double getMaxWalkingDist()
{
  return _SettingsPageState._maxWalkingDistance;
}


}


class _SettingsPageState extends State<SettingsPage> {
  static double _maxWalkingDistance = 1.0; // kilometers
  String _selectedLanguage = 'English';
  final List<Color> _themeColors = [
    const Color(0xFF2E7D32), // Forest Green
    const Color(0xFF1976D2), // Blue
    const Color(0xFF9C27B0), // Purple
    const Color(0xFFE91E63), // Pink
    const Color(0xFFF57C00), // Orange
  ];

static double getMaxWalkingDist()
{
  return _maxWalkingDistance;
}


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        centerTitle: true,
      ),
      body: ListView(
        children: [
          // Account Section
          _buildSection(
            'Account',
            ListTile(
              leading: const Icon(Icons.account_circle),
              title: const Text('Account Settings'),
              subtitle: const Text('Manage your profile and preferences'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                // Navigate to account settings
              },
            ),
          ),

          // App Preferences Section
          _buildSection(
            'App Preferences',
            Column(
              children: [
                // Max Walking Distance
                ListTile(
                  leading: const Icon(Icons.directions_walk),
                  title: const Text('Maximum Walking Distance'),
                  subtitle: Text('${_maxWalkingDistance.toStringAsFixed(1)} km'),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Slider(
                    value: _maxWalkingDistance,
                    min: 0.1,
                    max: 5.0,
                    divisions: 49,
                    label: '${_maxWalkingDistance.toStringAsFixed(1)} km',
                    onChanged: (value) {
                      setState(() {
                        _maxWalkingDistance = value;
                      });
                    },
                  ),
                ),

                // Language Selection
                ListTile(
                  leading: const Icon(Icons.language),
                  title: const Text('App Language'),
                  subtitle: Text(_selectedLanguage),
                  onTap: () {
                    _showLanguageDialog();
                  },
                ),

                // Theme Color Selection
                ListTile(
                  leading: const Icon(Icons.palette),
                  title: const Text('Theme Color'),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Row(
                      children: _themeColors.map((color) {
                        return GestureDetector(
                          onTap: () {
                            Provider.of<ThemeProvider>(context, listen: false)
                                .setThemeColor(color);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                            child: color == Provider.of<ThemeProvider>(context).themeColor
                                ? const Icon(Icons.check, color: Colors.white, size: 20)
                                : null,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Additional Settings
          _buildSection(
            'Additional Settings',
            Column(
              children: [
                SwitchListTile(
                  title: const Text('Push Notifications'),
                  subtitle: const Text('Receive price alerts and updates'),
                  value: true,
                  onChanged: (bool value) {
                    // Handle notification toggle
                  },
                ),
                SwitchListTile(
                  title: const Text('Location Services'),
                  subtitle: const Text('Enable background location access'),
                  value: true,
                  onChanged: (bool value) {
                    // Handle location services toggle
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, Widget content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
        content,
        const Divider(),
      ],
    );
  }

  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Language'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              'English',
              'Español',
              'Français',
              'Deutsch',
              '中文',
            ].map((language) {
              return ListTile(
                title: Text(language),
                trailing: language == _selectedLanguage
                    ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
                    : null,
                onTap: () {
                  setState(() {
                    _selectedLanguage = language;
                  });
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
