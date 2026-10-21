import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import '../constants/app_constants.dart';

class DeviceService {
  static const _uuid = Uuid();

  /// Returns a persistent device_id (stored in SharedPreferences).
  static Future<String> getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(AppConstants.keyDeviceId);
    if (id == null) {
      id = _uuid.v4();
      await prefs.setString(AppConstants.keyDeviceId, id);
    }
    return id;
  }

  static Future<String> getDeviceName() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final a = await info.androidInfo;
        return '${a.manufacturer} ${a.model}';
      } else if (Platform.isIOS) {
        final i = await info.iosInfo;
        return '${i.name} ${i.model}';
      } else {
        final w = await info.webBrowserInfo;
        return '${w.browserName} ${w.platform ?? "Web"}';
      }
    } catch (_) {
      return 'Unknown Device';
    }
  }

  /// Registers device in user_devices. Returns true if allowed, false if limit reached.
  /// Throws if Supabase trigger rejects (max 2 devices).
  static Future<bool> registerDevice() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final deviceId = await getDeviceId();
    final deviceName = await getDeviceName();

    try {
      await supabase.from('user_devices').upsert(
        {
          'user_id': userId,
          'device_id': deviceId,
          'device_name': deviceName,
          'last_seen': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,device_id',
      );
      return true;
    } on PostgrestException catch (e) {
      if (e.message.contains('Maximum 2 devices')) return false;
      rethrow;
    }
  }

  /// Checks if current device is already registered or can be registered.
  static Future<bool> canLogin() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return false;

    final deviceId = await getDeviceId();

    // If device already registered, allow
    final existing = await supabase
        .from('user_devices')
        .select('device_id')
        .eq('user_id', userId)
        .eq('device_id', deviceId)
        .maybeSingle();
    if (existing != null) {
      // Update last_seen
      await supabase.from('user_devices').update(
        {'last_seen': DateTime.now().toIso8601String()},
      ).eq('user_id', userId).eq('device_id', deviceId);
      return true;
    }

    // Check count
    final all = await supabase
        .from('user_devices')
        .select('device_id')
        .eq('user_id', userId);
    if ((all as List).length >= 2) return false;

    return true;
  }
}
