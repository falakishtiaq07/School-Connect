import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'read_status_service.dart';

class UnreadService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static Future<bool> hasUnreadAnnouncements() async {
    final user = _auth.currentUser;

    if (user == null) return false;

    try {
      final studentsSnapshot = await _firestore
          .collection('announcements')
          .where('students', isEqualTo: true)
          .get();

      final teachersSnapshot = await _firestore
          .collection('announcements')
          .where('teachers', isEqualTo: true)
          .get();

      final Map<String, DocumentSnapshot> announcements = {};

      for (final doc in studentsSnapshot.docs) {
        announcements[doc.id] = doc;
      }

      for (final doc in teachersSnapshot.docs) {
        announcements[doc.id] = doc;
      }

      if (announcements.isEmpty) {
        return false;
      }

      final readIds = await ReadStatusService.getReadIds(type: 'announcement');

      return announcements.values.any((doc) => !readIds.contains(doc.id));
    } catch (e) {
      print('Error checking unread announcements: $e');
      return false;
    }
  }

  static Future<bool> hasUnreadReports() async {
    final user = _auth.currentUser;

    if (user == null) return false;

    try {
      final readSnapshot = await _firestore
          .collection('report_reads')
          .where('studentId', isEqualTo: user.uid)
          .get();

      final readReportIds = readSnapshot.docs
          .map((doc) => doc['reportId'].toString())
          .toSet();

      final reportsSnapshot = await _firestore
          .collection('monthly_reports')
          .where('studentId', isEqualTo: user.uid)
          .get();

      if (reportsSnapshot.docs.isEmpty) {
        return false;
      }

      return reportsSnapshot.docs.any((doc) {
        final data = doc.data();

        final bool isReadFieldFalse = data['isRead'] == false;

        final bool isNotRead = !readReportIds.contains(doc.id);

        return isReadFieldFalse && isNotRead;
      });
    } catch (e) {
      print('Error checking unread reports: $e');
      return false;
    }
  }

  static Future<bool> hasUnreadHomework() async {
    final user = _auth.currentUser;

    if (user == null) return false;

    try {
      final homeworkSnapshot = await _firestore.collection('homework').get();

      if (homeworkSnapshot.docs.isEmpty) {
        return false;
      }

      final readSnapshot = await _firestore
          .collection('diary_reads')
          .where('studentId', isEqualTo: user.uid)
          .get();

      final readDiaryIds = readSnapshot.docs
          .map((doc) => doc['diaryId'].toString())
          .toSet();

      return homeworkSnapshot.docs.any((doc) => !readDiaryIds.contains(doc.id));
    } catch (e) {
      print('Error checking unread homework: $e');
      return false;
    }
  }

  static Future<bool> hasUnreadAttendanceAlerts() async {
    final user = _auth.currentUser;

    if (user == null) return false;

    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: user.uid)
          .where('type', isEqualTo: 'attendance')
          .where('isRead', isEqualTo: false)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking unread attendance alerts: $e');
      return false;
    }
  }

  static Future<bool> hasUnreadChallans() async {
    return false;
  }

  static Future<bool> hasUnreadVerifyChallan() async {
    try {
      final snapshot = await _firestore
          .collection('fee_receipts')
          .where('status', isEqualTo: 'Pending')
          .get();

      if (snapshot.docs.isEmpty) {
        return false;
      }

      return snapshot.docs.any((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final adminRead = data['adminRead'];
        return adminRead != true;
      });
    } catch (e) {
      print('Error checking unread verify challan: $e');
      return false;
    }
  }

  static Future<bool> hasUnreadComplaints() async {
    final user = _auth.currentUser;

    if (user == null) return false;

    try {
      final snapshot = await _firestore
          .collection('complaints')
          .where('isRead', isEqualTo: false)
          .limit(1)
          .get();

      return snapshot.docs.isNotEmpty;
    } catch (e) {
      print('Error checking unread complaints: $e');
      return false;
    }
  }

  static Future<bool> _hasUnreadLeaves() async {
    final user = _auth.currentUser;

    if (user == null) return false;

    try {
      final userDoc = await _firestore.collection('users').doc(user.uid).get();

      if (!userDoc.exists) return false;

      final teacherClass = userDoc.data()?['class'];

      if (teacherClass == null || teacherClass.toString().isEmpty) {
        return false;
      }

      final snapshot = await _firestore
          .collection('leave_requests')
          .where('class', isEqualTo: teacherClass)
          .get();

      return snapshot.docs.any((doc) {
        final data = doc.data();
        return data['teacherRead'] != true;
      });
    } catch (e) {
      print('Error checking unread leave requests: $e');
      return false;
    }
  }

  static Future<Map<String, bool>> getUnreadStatus() async {
    final results = await Future.wait([
      hasUnreadAnnouncements(),

      hasUnreadReports(),

      hasUnreadAttendanceAlerts(),

      hasUnreadChallans(),

      hasUnreadVerifyChallan(),

      hasUnreadHomework(),

      hasUnreadComplaints(),

      _hasUnreadLeaves(),
    ]);

    return {
      'announcements': results[0],
      'reports': results[1],
      'attendanceAlerts': results[2],
      'challans': results[3],
      'verifyChallan': results[4],
      'homework': results[5],
      'complaints': results[6],
      'leaves': results[7],
    };
  }
}
