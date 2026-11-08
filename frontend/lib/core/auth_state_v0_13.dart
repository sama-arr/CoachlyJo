import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_v0_13.dart';
import 'push_v0_13.dart';

/// Holds the logged-in user and token; persists token across launches.
class AuthState extends ChangeNotifier {
  String? token;
  Map<String, dynamic>? user;

  String? get role => user?['role'] as String?;
  /// (v0.14) Shown in the navigation drawer header.
  String? get email => user?['email'] as String?;
  bool get isLoggedIn => token != null;

  Future<void> loadFromStorage() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    if (token != null) {
      ApiClient.instance.setToken(token);
      try {
        user = Map<String, dynamic>.from(await ApiClient.instance.get('/api/auth/me'));
      } catch (_) {
        await logout();
      }
    }
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final res = await ApiClient.instance.post('/api/auth/login', {
      'email': email,
      'password': password,
    });
    token = res['token'];
    user = Map<String, dynamic>.from(res['user']);
    ApiClient.instance.setToken(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token!);
    // (v0.14 item 13) Deliver notifications to this device.
    await PushService.instance.registerDevice();
    notifyListeners();
  }

  Future<void> logout() async {
    // Stop OS notifications for this account on this device.
    await PushService.instance.unregisterDevice();
    token = null;
    user = null;
    ApiClient.instance.setToken(null);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    notifyListeners();
  }
}
