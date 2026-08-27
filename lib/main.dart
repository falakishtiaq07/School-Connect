import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:school_connect/screens/attendance_alerts_screen.dart';
import 'package:school_connect/screens/download_challan_screen.dart';

import 'package:school_connect/screens/resolve_complainrs_screen.dart';
import 'package:school_connect/screens/student_dashboard_screen.dart';
import 'package:school_connect/screens/teacher_dashboard_screen.dart';
import 'package:school_connect/screens/verify_challan_screen.dart';
import 'package:school_connect/screens/view_announcements_screen.dart';
import 'package:school_connect/screens/view_homework_screen.dart';
import 'package:school_connect/screens/view_reports_screen.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';
import 'package:school_connect/screens/admin_dashboard_screen.dart';
import 'theme/app_theme.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
    OneSignal.initialize("ed2a3db5-57d7-4e79-a39b-fe367eaa8c55");
    OneSignal.Notifications.addForegroundWillDisplayListener((event) {
      event.notification.display();
    });
    OneSignal.Notifications.requestPermission(true);
    OneSignal.Notifications.addClickListener((event) {
      final data = event.notification.additionalData;
      final type = data?['type'];

      switch (type) {
        case 'complaint':
          navigatorKey.currentState?.pushNamed('/complaints');
          break;
        case 'announcement':
          navigatorKey.currentState?.pushNamed('/announcements');
          break;
        case 'homework':
          navigatorKey.currentState?.pushNamed('/homework');
          break;
        case 'leave_request':
        case 'leave_status':
          navigatorKey.currentState?.pushNamed('/leaves');
          break;
        case 'attendance':
          navigatorKey.currentState?.pushNamed('/attendance');
          break;
        case 'report':
          navigatorKey.currentState?.pushNamed('/reports');
          break;
        case 'challan':
          navigatorKey.currentState?.pushNamed('/challans');
          break;
        case 'receipt':
          navigatorKey.currentState?.pushNamed('/receipts');
          break;
      }
    });

    print("Init successful!");
  } catch (e) {
    print("Firebase FATAL ERROR: $e");
  }
  runApp(const MyApp());
}

Future<void> saveFCMToken(String userId) async {
  try {
    // Notification permission
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // FCM token
    String? token = await FirebaseMessaging.instance.getToken();

    if (token != null) {
      await FirebaseFirestore.instance.collection('users').doc(userId).update({
        'fcmToken': token,
      });

      print("FCM Token saved: $token");
    } else {
      print("FCM Token nahi mila.");
    }
  } catch (e) {
    print("FCM Token Error: $e");
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'SchoolConnect',
      theme: AppTheme.lightTheme,
      routes: {
        '/complaints': (context) => const AdminComplaintsPage(),
        '/announcements': (context) => const ViewAnnouncementsScreen(),
        '/homework': (context) => const StudentHomeworkListScreen(),
        '/attendance': (context) => const AttendanceAlertsScreen(),
        '/reports': (context) => const StudentReportViewScreen(),
        '/challans': (context) => const ViewChallanScreen(),
        '/receipts': (context) => const AdminVerifyChallanScreen(),
      },
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          } else if (snapshot.hasData) {
            return RoleBasedNavigator(user: snapshot.data!);
          } else {
            return const WelcomeScreen();
          }
        },
      ),
    );
  }
}

class RoleBasedNavigator extends StatelessWidget {
  final User user;
  const RoleBasedNavigator({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    saveFCMToken(user.uid);
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          String role = snapshot.data!.get('role').toString().toLowerCase();
          if (role == 'admin') return const AdminDashboardScreen();
          if (role == 'teacher') return const TeacherDashboardScreen();
          if (role == 'student') return const StudentDashboardScreen();
        }
        return const WelcomeScreen(); // Agar role match na ho
      },
    );
  }
}
