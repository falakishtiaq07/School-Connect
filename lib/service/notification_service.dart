import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class NotificationService {
  static const String oneSignalAppId = "ed2a3db5-57d7-4e79-a39b-fe367eaa8c55";
  static const String restApiKey =
      "os_v2_app_5uvd3nkx25hhti437y3h5kumku6wxmppzgfebnvgwbbbbkpkoqzqrvkk2pve3rnqxtp5fjn47j6ya43eyfxuilzhn22f5t3rppxh5ra";

  static const String _sendUrl = "https://api.onesignal.com/notifications";

  static Future<void> sendPushToUser({
    required String title,
    required String body,
    required String notificationType,
    String? targetUserId,
    String? targetRole,
    String? targetClass,
    String? relatedId,
  }) async {
    final Map<String, dynamic> payload = {
      "app_id": oneSignalAppId,
      "target_channel": "push",
      "headings": {"en": title},
      "contents": {"en": body},
      "data": {"type": notificationType, "relatedId": relatedId ?? ""},
    };

    if (targetUserId != null && targetUserId.trim().isNotEmpty) {
      payload["include_aliases"] = {
        "external_id": [targetUserId.trim()],
      };
      debugPrint("OneSignal Target External ID: ${targetUserId.trim()}");
    } else if (targetRole != null && targetRole.trim().isNotEmpty) {
      final String normalizedRole = targetRole.trim().toLowerCase();
      final List<Map<String, dynamic>> filters = [
        {
          "field": "tag",
          "key": "role",
          "relation": "=",
          "value": normalizedRole,
        },
      ];
      if (targetClass != null && targetClass.trim().isNotEmpty) {
        filters.add({"operator": "AND"});
        filters.add({
          "field": "tag",
          "key": "class",
          "relation": "=",
          "value": targetClass.trim(),
        });
      }
      payload["filters"] = filters;
      debugPrint("OneSignal Target Role: $normalizedRole");
    } else {
      throw Exception(
        "OneSignal target is missing. Provide targetUserId or targetRole.",
      );
    }

    await _send(payload);
  }

  static Future<void> sendPushToUsers({
    required List<String> userIds,
    required String title,
    required String body,
    required String notificationType,
    String? relatedId,
  }) async {
    final cleanIds = userIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    if (cleanIds.isEmpty) {
      debugPrint('sendPushToUsers: no user ids provided, skipping.');
      return;
    }

    await _send({
      "app_id": oneSignalAppId,
      "target_channel": "push",
      "include_aliases": {"external_id": cleanIds},
      "headings": {"en": title},
      "contents": {"en": body},
      "data": {"type": notificationType, "relatedId": relatedId ?? ""},
    });
  }

  static Future<void> sendPushNotification({
    required String targetRole,
    required String title,
    required String body,
    required String notificationType,
    String? relatedId,
    String? targetClass,
  }) async {
    final String normalizedRole = targetRole.trim().toLowerCase();

    final List<Map<String, dynamic>> filters = [
      {"field": "tag", "key": "role", "relation": "=", "value": normalizedRole},
    ];

    if (targetClass != null && targetClass.trim().isNotEmpty) {
      filters.add({"operator": "AND"});
      filters.add({
        "field": "tag",
        "key": "class",
        "relation": "=",
        "value": targetClass.trim(),
      });
    }

    await _send({
      "app_id": oneSignalAppId,
      "target_channel": "push",
      "headings": {"en": title},
      "contents": {"en": body},
      "data": {"type": notificationType, "relatedId": relatedId ?? ""},
      "filters": filters,
    });
  }

  static Future<void> sendTestToStudents() async {
    await sendPushNotification(
      targetRole: "student",
      title: "Test Notification",
      body: "OneSignal notification is working!",
      notificationType: "test",
    );
  }

  static Future<void> sendTestToUser(String uid) async {
    if (uid.trim().isEmpty) {
      throw Exception("Student UID is empty.");
    }
    await sendPushToUser(
      targetUserId: uid.trim(),
      title: "Test Notification",
      body: "This is a test notification.",
      notificationType: "test",
    );
  }

  static Future<void> _send(Map<String, dynamic> payload) async {
    try {
      debugPrint("================================================");
      debugPrint("ONESIGNAL REQUEST:");
      debugPrint(const JsonEncoder.withIndent("  ").convert(payload));
      debugPrint("================================================");

      final response = await http.post(
        Uri.parse(_sendUrl),
        headers: {
          "Content-Type": "application/json",
          "Authorization": "key $restApiKey",
        },
        body: jsonEncode(payload),
      );

      debugPrint("ONESIGNAL STATUS: ${response.statusCode}");
      debugPrint("ONESIGNAL RESPONSE: ${response.body}");

      Map<String, dynamic> decoded = {};
      try {
        final dynamic json = jsonDecode(response.body);
        if (json is Map<String, dynamic>) decoded = json;
      } catch (_) {
        debugPrint("OneSignal response is not valid JSON.");
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          "OneSignal API Error ${response.statusCode}: ${response.body}",
        );
      }

      final String? notificationId = decoded["id"]?.toString();

      if (notificationId == null || notificationId.isEmpty) {
        throw Exception(
          "OneSignal did not return notification ID. Response: ${response.body}",
        );
      }

      debugPrint("================================================");
      debugPrint("ONESIGNAL SUCCESS");
      debugPrint("Notification ID: $notificationId");
      debugPrint("================================================");
    } catch (e, stackTrace) {
      debugPrint("================================================");
      debugPrint("ONESIGNAL SEND ERROR:");
      debugPrint(e.toString());
      debugPrint("STACK TRACE:");
      debugPrint(stackTrace.toString());
      debugPrint("================================================");
      rethrow;
    }
  }
}
