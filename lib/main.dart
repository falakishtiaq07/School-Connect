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
import 'package:school_connect/service/one_signal_service.dart';
import 'firebase_options.dart';
import 'screens/welcome_screen.dart';
import 'package:school_connect/screens/admin_dashboard_screen.dart';
import 'theme/app_theme.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await OneSignalService.initialize(
      onNotificationClick: (event) {
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
      },
    );

    print('Init successful!');
  } catch (e) {
    print('Firebase FATAL ERROR: $e');
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

class RoleBasedNavigator extends StatefulWidget {
  final User user;
  const RoleBasedNavigator({super.key, required this.user});

  @override
  State<RoleBasedNavigator> createState() => _RoleBasedNavigatorState();
}

class _RoleBasedNavigatorState extends State<RoleBasedNavigator> {
  bool _oneSignalConfigured = false;

  @override
  void initState() {
    super.initState();
    saveFCMToken(widget.user.uid);
  }

  Future<void> _configureOneSignal(Map<String, dynamic> data) async {
    if (_oneSignalConfigured) return;

    final role = data['role'].toString().toLowerCase().trim();
    await OneSignalService.setupOneSignal(
      widget.user.uid,
      role,
      studentClass: role == 'student' ? data['class']?.toString() : null,
    );

    if (mounted) {
      setState(() => _oneSignalConfigured = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>;
          final role = data['role'].toString().toLowerCase();

          if (!_oneSignalConfigured) {
            _configureOneSignal(data);
          }

          if (role == 'admin') return const AdminDashboardScreen();
          if (role == 'teacher') return const TeacherDashboardScreen();
          if (role == 'student') return const StudentDashboardScreen();
        }
        return const WelcomeScreen();
      },
    );
  }
}
