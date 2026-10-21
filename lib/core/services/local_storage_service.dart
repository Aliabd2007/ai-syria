import 'package:hive_flutter/hive_flutter.dart';
import '../constants/app_constants.dart';

class LocalStorageService {
  static late Box _chatsBox;
  static late Box _messagesBox;
  static late Box _settingsBox;

  static Future<void> init() async {
    await Hive.initFlutter();
    _chatsBox = await Hive.openBox(AppConstants.hiveChatsBox);
    _messagesBox = await Hive.openBox(AppConstants.hiveMessagesBox);
    _settingsBox = await Hive.openBox(AppConstants.hiveSettingsBox);
  }

  // Chats: stored as List<Map>
  static List<Map> getCachedChats() {
    final raw = _chatsBox.get('chats');
    if (raw == null) return [];
    return List<Map>.from(raw as List);
  }

  static Future<void> cacheChats(List<Map> chats) async {
    await _chatsBox.put('chats', chats);
  }

  // Messages per chat_id
  static List<Map> getCachedMessages(String chatId) {
    final raw = _messagesBox.get(chatId);
    if (raw == null) return [];
    return List<Map>.from(raw as List);
  }

  static Future<void> cacheMessages(String chatId, List<Map> messages) async {
    await _messagesBox.put(chatId, messages);
  }

  static Future<void> clearAll() async {
    await _chatsBox.clear();
    await _messagesBox.clear();
  }

  // Settings
  static String get themeMode => _settingsBox.get('theme_mode', defaultValue: 'system') as String;
  static Future<void> setThemeMode(String v) => _settingsBox.put('theme_mode', v);
}
