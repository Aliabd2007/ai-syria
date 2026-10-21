import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/device_service.dart';
import '../../../../core/services/local_storage_service.dart';

class AuthProvider extends ChangeNotifier {
  bool _loading = false;
  String? _error;
  bool get loading => _loading;
  String? get error => _error;
  bool get isLoggedIn => Supabase.instance.client.auth.currentUser != null;

  StreamSubscription<AuthState>? _authSub;

  AuthProvider() {
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      // Persist user_id in Hive for offline reference
      final uid = data.session?.user.id;
      if (uid != null) {
        Hive.box('settings_box').put('user_id', uid);
      }
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<bool> signUp(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );
      if (res.user == null) {
        _error = 'فشل إنشاء الحساب — تحقق من البريد وكلمة المرور';
        return false;
      }
      // If email confirmation is disabled, session is already available.
      // If confirmation required, try auto sign-in.
      if (res.session == null) {
        try {
          final loginRes = await Supabase.instance.client.auth.signInWithPassword(
            email: email,
            password: password,
          );
          if (loginRes.session == null) {
            _error = 'تم إنشاء الحساب — يلزم تأكيد البريد قبل الدخول';
            return false;
          }
        } on AuthException catch (e) {
          _error = e.message.contains('Email not confirmed')
              ? 'تم إنشاء الحساب — يلزم تأكيد البريد قبل الدخول'
              : e.message;
          return false;
        }
      }
      // Save user_id
      final uid = Supabase.instance.client.auth.currentUser?.id;
      if (uid != null) {
        await Hive.box('settings_box').put('user_id', uid);
      }
      // Device registration
      try {
        await DeviceService.registerDevice();
      } catch (e) {
        debugPrint('Device register after signUp failed: $e');
      }
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> signIn(String email, String password) async {
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final res = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );
      if (res.user == null || res.session == null) {
        _error = 'فشل تسجيل الدخول — تحقق من البيانات';
        return false;
      }
      // Persist token is handled by Supabase (PKCE + storage). Save user_id in Hive.
      final uid = res.user!.id;
      await Hive.box('settings_box').put('user_id', uid);

      // Device limit check
      final canLogin = await DeviceService.canLogin();
      if (!canLogin) {
        await Supabase.instance.client.auth.signOut();
        _error = 'تم الوصول للحد الأقصى (جهازين فقط) — احذف جهازاً من الإعدادات';
        return false;
      }
      try {
        await DeviceService.registerDevice();
      } catch (e) {
        debugPrint('Device register after signIn failed: $e');
      }
      return true;
    } on AuthException catch (e) {
      _error = e.message;
      return false;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    await LocalStorageService.clearAll();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
