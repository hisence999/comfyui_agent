import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  String _ipAddress = '127.0.0.1';
  String _port = '8188';

  ThemeMode get themeMode => _themeMode;
  String get ipAddress => _ipAddress;
  String get port => _port;
  String get fullAddress => 'http://$_ipAddress:$_port';
  String get wsAddress => 'ws://$_ipAddress:$_port';

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt('themeMode') ?? 0;
    _themeMode = ThemeMode.values[themeIndex];
    _ipAddress = prefs.getString('ipAddress') ?? '127.0.0.1';
    _port = prefs.getString('port') ?? '8188';
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('themeMode', mode.index);
    notifyListeners();
  }

  Future<void> setAddress(String ip, String port) async {
    _ipAddress = ip;
    _port = port;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ipAddress', ip);
    await prefs.setString('port', port);
    notifyListeners();
  }
}
