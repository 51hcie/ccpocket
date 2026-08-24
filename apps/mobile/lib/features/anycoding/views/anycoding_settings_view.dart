import 'package:flutter/material.dart';
import '../../settings/settings_screen.dart';

class AnyCodingSettingsView extends StatelessWidget {
  final bool focusConnection;
  final bool focusSupport;

  const AnyCodingSettingsView({
    super.key,
    this.focusConnection = false,
    this.focusSupport = false,
  });

  @override
  Widget build(BuildContext context) {
    return SettingsScreen(
      embedded: true,
      focusConnection: focusConnection,
      focusSupport: focusSupport,
    );
  }
}
