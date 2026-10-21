import 'package:flutter/material.dart';
import 'local_storage_service.dart';

class ThemeService extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;

  ThemeService() {
    _load();
  }

  void _load() {
    final saved = LocalStorageService.themeMode;
    switch (saved) {
      case 'light':
        _mode = ThemeMode.light;
        break;
      case 'dark':
        _mode = ThemeMode.dark;
        break;
      default:
        _mode = ThemeMode.system;
    }
  }

  Future<void> toggle() async {
    if (_mode == ThemeMode.light) {
      _mode = ThemeMode.dark;
      await LocalStorageService.setThemeMode('dark');
    } else if (_mode == ThemeMode.dark) {
      _mode = ThemeMode.light;
      await LocalStorageService.setThemeMode('light');
    } else {
      // system -> light -> dark cycle, start with light
      _mode = ThemeMode.light;
      await LocalStorageService.setThemeMode('light');
    }
    notifyListeners();
  }

  Future<void> setMode(ThemeMode m) async {
    _mode = m;
    final v = m == ThemeMode.light ? 'light' : m == ThemeMode.dark ? 'dark' : 'system';
    await LocalStorageService.setThemeMode(v);
    notifyListeners();
  }
}
