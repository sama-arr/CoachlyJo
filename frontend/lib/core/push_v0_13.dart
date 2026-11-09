import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_v0_13.dart';
import '../firebase_options.dart';

/// =============================================================================
/// OS push notifications (v0.14 item 13).
///
/// Until now notifications only appeared inside the app. This delivers them to
/// the phone's notification tray, so a member is told about a confirmed booking
/// or an upcoming session without opening CoachlyJo.
///
/// SETUP — see README "Push notifications". Nothing here runs until the
/// Firebase config files are present:
///   android/app/google-services.json
///   ios/Runner/GoogleService-Info.plist
///   plus an APNs Auth Key uploaded in the Firebase console (iOS only)
///
/// `init()` fails soft: on a build without those files, Firebase throws on
/// initialise, we log it once and the app carries on with in-app notifications
/// exactly as before. That keeps a release shippable before push is configured.
/// =============================================================================
class PushService {
  static final PushService instance = PushService._();
  PushService._();

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();
  String? _token;
  bool _ready = false;

  /// Android needs an explicit channel or notifications arrive silently.
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'coachlyjo_default',
    'CoachlyJo',
    description: 'Bookings, packages and session reminders',
    importance: Importance.high,
  );

  /// Call once at app start, before the first screen builds.
  Future<void> init() async {
    if (_ready) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // Ask permission. iOS shows the system prompt; Android 13+ does too.
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[push] notifications denied by the user');
        // Still finish setup: they may enable it later in system settings.
      }

      await _local.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(),
        ),
      );
      await _local
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_channel);

      // Foreground messages do not show automatically — draw them ourselves so
      // a member using the app still sees a booking confirmation.
      // (v0.15) Without this, iOS suppresses notifications entirely while the
      // app is in the foreground. Android is handled by _showForeground below.
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: true, badge: true, sound: true,
      );

      FirebaseMessaging.onMessage.listen(_showForeground);

      _ready = true;
    } catch (err) {
      // Most commonly: Firebase config files not added yet.
      debugPrint('[push] not available: $err');
      _ready = false;
    }
  }

  void _showForeground(RemoteMessage message) {
    final n = message.notification;
    if (n == null) return;
    // iOS presents foreground alerts natively via the options set in init();
    // drawing a local copy as well would show every notification twice.
    if (Platform.isIOS) return;
    _local.show(
      n.hashCode,
      n.title,
      n.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// (v0.15 bug 5) iOS hands Firebase an APNs token asynchronously, and
  /// `getToken()` returns NULL until it has arrived. v0.14 called getToken()
  /// immediately after requesting permission, so on iOS the device was never
  /// registered and no notification could ever be delivered — which is exactly
  /// why Android worked and iOS did not. Android has no APNs step, so this
  /// simply returns straight away there.
  Future<bool> _waitForApnsToken() async {
    if (!Platform.isIOS) return true;
    // Apple usually responds in well under a second; allow ~10s on a cold
    // start or a poor connection before giving up for this session.
    for (var attempt = 0; attempt < 20; attempt++) {
      final apns = await FirebaseMessaging.instance.getAPNSToken();
      if (apns != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    debugPrint('[push] no APNs token yet — will retry on next launch');
    return false;
  }

  /// Register this device against the signed-in account. Called after login
  /// and whenever Firebase rotates the token.
  Future<void> registerDevice() async {
    if (!_ready) return;
    try {
      if (!await _waitForApnsToken()) return;
      _token = await FirebaseMessaging.instance.getToken();
      if (_token == null) {
        debugPrint('[push] FCM token unavailable on this device');
        return;
      }
      await ApiClient.instance.post('/api/push/register', {
        'token': _token,
        'platform': Platform.isIOS ? 'ios' : 'android',
      });
      // Firebase rotates tokens; keep the server in step.
      FirebaseMessaging.instance.onTokenRefresh.listen((t) async {
        _token = t;
        try {
          await ApiClient.instance.post('/api/push/register', {
            'token': t,
            'platform': Platform.isIOS ? 'ios' : 'android',
          });
        } catch (_) {/* retried on next launch */}
      });
    } catch (err) {
      debugPrint('[push] device registration failed: $err');
    }
  }

  /// Called on sign-out so the next person using this phone does not receive
  /// the previous account's notifications.
  Future<void> unregisterDevice() async {
    if (!_ready || _token == null) return;
    try {
      await ApiClient.instance
          .delete('/api/push/register', body: {'token': _token});
    } catch (_) {/* best effort */}
  }
}
