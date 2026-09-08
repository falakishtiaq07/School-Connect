import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:school_connect/screens/report_details_screen.dart';

class StudentReportViewScreen extends StatefulWidget {
  const StudentReportViewScreen({super.key});

  @override
  State<StudentReportViewScreen> createState() =>
      _StudentReportViewScreenState();
}

class _StudentReportViewScreenState extends State<StudentReportViewScreen> {
  final String currentStudentId = FirebaseAuth.instance.currentUser?.uid ?? "";

  Set<String> _readReportIds = {};
  bool _isLoadingReads = true;

  @override
  void initState() {
    super.initState();
    _loadReadReports();
  }

  // 1. Firestore se check karein kaun se reports read ho chuke hain
  Future<void> _loadReadReports() async {
    if (currentStudentId.isEmpty) {
      setState(() {
        _isLoadingReads = false;
      });
      return;
    }

    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('report_reads')
          .where('studentId', isEqualTo: currentStudentId)
          .get();

      setState(() {
        _readReportIds = querySnapshot.docs
            .map((doc) => doc['reportId'].toString())
            .toSet();
        _isLoadingReads = false;
      });
    } catch (e) {
      // Agar error aaye tab bhi loading khatam kar ke screen chalne dein
      setState(() {
        _isLoadingReads = false;
      });
    }
  }

  // 2. Report ko read mark karne ka function (Optimized)
  Future<void> _markReportAsRead(String reportId) async {
    if (_readReportIds.contains(reportId)) return;

    _readReportIds.add(reportId);

    try {
      await FirebaseFirestore.instance.collection('report_reads').add({
        'studentId': currentStudentId,
        'reportId': reportId,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Handle error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        title: const Text(
          "My Monthly Reports",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('monthly_reports')
            .where('studentId', isEqualTo: currentStudentId)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return _buildEmptyState();
          }

          var reports = snapshot.data!.docs;

          return ListView.builder(
            padding: const EdgeInsets.all(15),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              var reportDoc = reports[index];
              var report = reportDoc.data() as Map<String, dynamic>;
              String reportId = reportDoc.id;

              // ListTile ke andar isUnread ki line ko yeh bana dein:
              final bool isUnread =
                  (report['isRead'] == false) &&
                  !_readReportIds.contains(reportId);
              return _buildReportCard(context, report, reportId, isUnread);
            },
          );
        },
      ),
    );
  }

  // Report Card Design with Unread Indicator
  Widget _buildReportCard(
    BuildContext context,
    Map<String, dynamic> data,
    String reportId,
    bool isUnread,
  ) {
    String performance = data['overallPerformance'] ?? "N/A";

    Color perfColor = performance == "Excellent"
        ? Colors.green
        : performance == "Good"
        ? Colors.blue
        : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUnread
              ? const Color(0xFF2E86AB).withOpacity(0.5)
              : Colors.grey.shade200,
          width: isUnread ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 10,
        ),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: perfColor.withOpacity(.12),
              child: Icon(Icons.assignment_rounded, color: perfColor),
            ),
            // Red unread dot indicator
            if (isUnread)
              Positioned(
                right: 0,
                top: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                data['month'] ?? "Unknown Month",
                style: TextStyle(
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                  fontSize: 17,
                  color: isUnread ? Colors.black : Colors.grey[800],
                ),
              ),
            ),
            if (isUnread)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "NEW",
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(
            children: [
              const Icon(Icons.school, size: 15, color: Colors.grey),
              const SizedBox(width: 5),
              Text(
                "Class: ${data['class']}",
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: perfColor.withOpacity(.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  performance,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: perfColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        trailing: const Icon(Icons.info_outline, color: Color(0xFF2E86AB)),
        onTap: () async {
          // Jaise hi student tap kare, usko read mark kar dein
          if (isUnread) {
            await _markReportAsRead(reportId);
          }

          // Phir details screen par navigate karein
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  ReportDetailScreen(reportId: reportId, reportData: data),
            ),
          );
        },
      ),
    );
  }

  // Empty State Design
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.folder_open, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 10),
          const Text(
            "No reports found yet.",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
