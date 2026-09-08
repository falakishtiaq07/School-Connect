import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ReportDetailScreen extends StatefulWidget {
  final Map<String, dynamic> reportData;
  final String reportId; // Yeh yahan define hai

  const ReportDetailScreen({
    super.key,
    required this.reportData,
    required this.reportId,
  });

  @override
  State<ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<ReportDetailScreen> {
  @override
  void initState() {
    super.initState();
    _markReportAsRead(); // Jaise hi screen khulay gi, yeh function chal jaye ga
  }

  Future<void> _markReportAsRead() async {
    try {
      await FirebaseFirestore.instance
          .collection('monthly_reports')
          .doc(widget.reportId)
          .update({'isRead': true});
    } catch (e) {
      print("Error updating read status: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4F8),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.grey.shade100,
        foregroundColor: Colors.white,
        title: Text(
          "Report - ${widget.reportData['month']}",
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF16304E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            _buildDetailCard("Academic Performance", [
              _buildPerformanceRow(
                "Overall",
                widget.reportData['overallPerformance'] ?? "N/A",
              ),
              _buildRow(
                "Homework:",
                widget.reportData['homeworkCompletion'] ?? "N/A",
              ),
              _buildRow(
                "Participation:",
                widget.reportData['classParticipation'] ?? "N/A",
              ),
            ]),
            const SizedBox(height: 2),
            _buildDetailCard("Attendance", [
              Row(
                children: [
                  Expanded(
                    child: _buildAttendanceBox(
                      "Total",
                      widget.reportData['totalDays']?.toString() ?? "0",
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildAttendanceBox(
                      "Present",
                      widget.reportData['presentDays']?.toString() ?? "0",
                      Colors.green,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildAttendanceBox(
                      "Absent",
                      widget.reportData['absentDays']?.toString() ?? "0",
                      Colors.red,
                    ),
                  ),
                ],
              ),
            ]),
            const SizedBox(height: 2),
            _buildDetailCard("Teacher Remarks", [
              Text(widget.reportData['remarks'] ?? "No remarks added."),
            ]),
            const SizedBox(height: 2),
            if (widget.reportData['attachmentUrls'] != null &&
                (widget.reportData['attachmentUrls'] as List).isNotEmpty)
              _buildDetailCard("Attachments", [
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: (widget.reportData['attachmentUrls'] as List).map((
                    url,
                  ) {
                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => FullScreenImage(imageUrl: url),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(.08),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.network(
                            url,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ]),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
              color: Color(0xFF1E3A5F),
            ),
          ),
          const SizedBox(height: 10),
          Divider(color: Colors.grey.shade300),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A5F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceRow(String label, String value) {
    Color color;

    switch (value.toLowerCase()) {
      case "excellent":
        color = Colors.green;
        break;
      case "good":
        color = Colors.blue;
        break;
      case "average":
        color = Colors.orange;
        break;
      default:
        color = Colors.grey;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceBox(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class FullScreenImage extends StatelessWidget {
  final String imageUrl;
  const FullScreenImage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(child: Image.network(imageUrl)),
    );
  }
}
