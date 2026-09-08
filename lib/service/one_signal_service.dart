import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class OneSignalService {
  static const String appId = 'ed2a3db5-57d7-4e79-a39b-fe367eaa8c55';

  static bool _sdkInitialized = false;
  static String? _lastConfiguredUid;

  /// Call once from main() before runApp().
  static Future<void> initialize({
    void Function(OSNotificationClickEvent event)? onNotificationClick,
  }) async {
    if (_sdkInitialized) return;

    if (kIsWeb) {
      debugPrint('OneSignal: web push is not configured in this app.');
      _sdkInitialized = true;
      return;
    }

    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize(appId);

    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.notification.display();
    });

    if (onNotificationClick != null) {
      OneSignal.Notifications.addClickListener(onNotificationClick);
    }

    _sdkInitialized = true;
    debugPrint('OneSignal SDK initialized');
  }

  /// Ensures the device has an active push subscription before login/tags.
  static Future<bool> ensurePushSubscription({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (kIsWeb) return false;

    final bool permissionGranted =
        await OneSignal.Notifications.requestPermission(true);

    if (!permissionGranted) {
      debugPrint('OneSignal: notification permission denied by user.');
      return false;
    }

    final bool subscribed = await _waitForActiveSubscription(timeout: timeout);

    if (!subscribed) {
      debugPrint(
        'OneSignal: push subscription not active after ${timeout.inSeconds}s. '
        'optedIn=${OneSignal.User.pushSubscription.optedIn}, '
        'id=${OneSignal.User.pushSubscription.id}',
      );
    }

    return subscribed;
  }

  static Future<bool> _waitForActiveSubscription({
    required Duration timeout,
  }) async {
    final DateTime deadline = DateTime.now().add(timeout);

    while (DateTime.now().isBefore(deadline)) {
      final String? subscriptionId = OneSignal.User.pushSubscription.id;
      final bool? optedIn = OneSignal.User.pushSubscription.optedIn;

      if (optedIn == true &&
          subscriptionId != null &&
          subscriptionId.isNotEmpty) {
        debugPrint('OneSignal: active subscription id=$subscriptionId');
        return true;
      }

      await Future.delayed(const Duration(milliseconds: 400));
    }

    return false;
  }

  /// Links this device to Firebase UID and sets targeting tags.
  /// Tags are always stored in lowercase so NotificationService filters match.
  static Future<void> setupOneSignal(
    String uid,
    String role, {
    String? studentClass,
    bool forceRefresh = false,
  }) async {
    if (kIsWeb) return;

    final String normalizedUid = uid.trim();
    final String normalizedRole = role.trim().toLowerCase();
    final String? normalizedClass = studentClass?.trim();

    if (normalizedUid.isEmpty) {
      debugPrint('OneSignal: UID is empty, skipping setup.');
      return;
    }

    if (!forceRefresh && _lastConfiguredUid == normalizedUid) {
      debugPrint('OneSignal: already configured for uid=$normalizedUid');
      return;
    }

    try {
      await ensurePushSubscription();

      await OneSignal.login(normalizedUid);
      debugPrint('OneSignal login called with external_id=$normalizedUid');

      // Give the SDK a moment to attach external_id to the subscription.
      await Future.delayed(const Duration(milliseconds: 800));

      final Map<String, String> tags = {'role': normalizedRole};

      if (normalizedRole == 'student' &&
          normalizedClass != null &&
          normalizedClass.isNotEmpty) {
        tags['class'] = normalizedClass;
      } else {
        await OneSignal.User.removeTag('class');
      }

      await OneSignal.User.addTags(tags);

      _lastConfiguredUid = normalizedUid;

      final externalId = await OneSignal.User.getExternalId();
      final onesignalId = await OneSignal.User.getOnesignalId();
      final subscriptionId = OneSignal.User.pushSubscription.id;
      final optedIn = OneSignal.User.pushSubscription.optedIn;

      debugPrint('OneSignal setup complete:');
      debugPrint('  external_id=$externalId');
      debugPrint('  onesignal_id=$onesignalId');
      debugPrint('  subscription_id=$subscriptionId');
      debugPrint('  opted_in=$optedIn');
      debugPrint('  tags=$tags');
    } catch (e, stackTrace) {
      debugPrint('OneSignal setup failed: $e');
      debugPrint('OneSignal stack trace: $stackTrace');
    }
  }

  static Future<void> logout() async {
    if (kIsWeb) return;

    try {
      _lastConfiguredUid = null;
      await OneSignal.logout();
      debugPrint('OneSignal logout successful');
    } catch (e) {
      debugPrint('OneSignal logout error: $e');
    }
  }
}
