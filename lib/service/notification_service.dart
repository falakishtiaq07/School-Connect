import 'dart:convert';
import 'package:http/http.dart' as http;

class NotificationService {
  static const String oneSignalAppId = "ed2a3db5-57d7-4e79-a39b-fe367eaa8c55";
  static const String restApiKey =
"Your API Key"
  static Future<void> sendPushNotification({
    required String targetRole,
    required String title,
    required String body,
    required String notificationType,
    String? relatedId,
    String? targetClass,
  }) async {
    final url = Uri.parse("https://onesignal.com/api/v1/notifications");

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": "Basic $restApiKey",
      },
      body: jsonEncode({
        "app_id": oneSignalAppId,
        "filters": [
          {"field": "tag", "key": "role", "relation": "=", "value": targetRole},
        ],
        "headings": {"en": title},
        "contents": {"en": body},
        "data": {"type": notificationType, "id": relatedId},
      }),
    );

    print("OneSignal response: ${response.body}");
  }

  static Future<void> sendPushToUser({
    required String userId,
    required String title,
    required String body,
    required String notificationType,
    String? relatedId,
    String? targetClass,
  }) async {
    final url = Uri.parse("https://onesignal.com/api/v1/notifications");

    final response = await http.post(
      url,
      headers: {
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": "Basic $restApiKey",
      },
      body: jsonEncode({
        "app_id": oneSignalAppId,
        "include_aliases": {
          "external_id": [userId],
        },
        "target_channel": "push",
        "headings": {"en": title},
        "contents": {"en": body},
        "data": {"type": notificationType, "id": relatedId},
      }),
    );

    print("OneSignal response: ${response.body}");
  }
}
