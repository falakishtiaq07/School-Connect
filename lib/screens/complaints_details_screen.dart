import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:school_connect/service/notification_service.dart';

class ComplaintDetailsPage extends StatefulWidget {
  final String docId;
  const ComplaintDetailsPage({super.key, required this.docId});

  @override
  State<ComplaintDetailsPage> createState() => _ComplaintDetailsPageState();
}

class _ComplaintDetailsPageState extends State<ComplaintDetailsPage> {
  // Status update function - Firestore mein update karega
  // Status update function - Firestore mein update karega
  Future<void> _updateStatus(String newStatus) async {
    try {
      // 1. Pehle Firestore se document ka data fetch karein taake student ki ID mil sakay
      DocumentSnapshot docSnapshot = await FirebaseFirestore.instance
          .collection("complaints")
          .doc(widget.docId)
          .get();

      if (!docSnapshot.exists) return;
      final data = docSnapshot.data() as Map<String, dynamic>;

      // Aam tor par complaints mein student ki ID 'studentUid' ya 'userId' ke naam se hoti hai
      // Aapke Firestore document ke field name ke mutabiq yehin par change kar lein (e.g., data['studentUid'] ya data['userId'])
      String targetUserId = data['studentUid'] ?? data['userId'] ?? '';

      // 2. Firestore mein status update karein
      await FirebaseFirestore.instance
          .collection("complaints")
          .doc(widget.docId)
          .update({"status": newStatus});

      // 3. Student ko Push Notification bhejein
      try {
        String title = 'Complaint Status Update';
        String body = 'Your complaint status has been updated to $newStatus.';

        if (newStatus.toLowerCase() == 'resolved') {
          title = 'Complaint Resolved ✅';
          body = 'Good news! Your complaint has been marked as resolved.';
        } else if (newStatus.toLowerCase() == 'in progress') {
          title = 'Complaint In Progress 🔄';
          body = 'Your complaint is now being reviewed.';
        }

        if (targetUserId.isNotEmpty) {
          await NotificationService.sendPushToUser(
            targetUserId: targetUserId,
            title: title,
            body: body,
            notificationType: 'complaint_update',
            relatedId: widget.docId,
          );
        }
      } catch (notificationError) {
        debugPrint('NOTIFICATION ERROR: $notificationError');
        // Notification fail hone par bhi status update nahi rukega
      }

      // Success SnackBar (Green)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Status successfully updated to $newStatus"),
          backgroundColor: Colors.green, // Yahan green color diya
          behavior: SnackBarBehavior
              .floating, // Is se bar thoda utha hua (floating) dikhega
        ),
      );
    } catch (e) {
      // Error SnackBar (Red)
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error updating status: $e"),
          backgroundColor: Colors.red, // Yahan red color diya
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F7FB),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        toolbarHeight: 65,
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Complaint Details",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection("complaints")
            .doc(widget.docId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text("Complaint not found."));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          // Date Formatting
          String dateStr = "N/A";
          if (data['createdAt'] != null) {
            dateStr = DateFormat(
              'dd MMM yyyy, hh:mm a',
            ).format((data['createdAt'] as Timestamp).toDate());
          }

          return SingleChildScrollView(
            padding: EdgeInsets.symmetric(
              horizontal: MediaQuery.of(context).size.width < 700 ? 12 : 24,
              vertical: 20,
            ),
            child: Column(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: Card(
                      elevation: 3,
                      shadowColor: Colors.black12,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(
                                        0xff1746A2,
                                      ).withOpacity(.08),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Icon(
                                      Icons.description_outlined,
                                      color: Color(0xff1746A2),
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: const [
                                        Text(
                                          "Complaint Information",
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          "Review complaint details below",
                                          style: TextStyle(
                                            color: Colors.grey,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const Divider(height: 28),
                            const Divider(),

                            _buildRow(
                              "Submitted By",
                              data['studentName'] ?? "N/A",
                            ),
                            _buildRow("Class", data['class'] ?? "N/A"),
                            _buildRow("Roll No", data['rollNo'] ?? "N/A"),
                            _buildRow("Title", data['title'] ?? "No Title"),
                            _buildRow("Date", dateStr),
                            _buildRow(
                              "Category",
                              data['category'] ?? "No Category",
                            ),
                            _buildRow("Status", data['status'] ?? "Pending"),

                            const SizedBox(height: 20),

                            const Text(
                              "Description",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                                color: Color(0xFF1E3A5F),
                              ),
                            ),

                            const SizedBox(height: 10),

                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                data['details'] ?? "No details provided.",
                                style: const TextStyle(
                                  fontSize: 14,
                                  height: 1.6,
                                  color: Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(.04),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Update Complaint Status",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A5F),
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        "Select the current progress of this complaint.",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),

                      const SizedBox(height: 20),

                      LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 450) {
                            return Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: _statusButton(
                                    "In Progress",
                                    Colors.blue,
                                    data,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: _statusButton(
                                    "Resolved",
                                    Colors.green,
                                    data,
                                  ),
                                ),
                              ],
                            );
                          }

                          return Row(
                            children: [
                              Expanded(
                                child: _statusButton(
                                  "In Progress",
                                  Colors.blue,
                                  data,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: _statusButton(
                                  "Resolved",
                                  Colors.green,
                                  data,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _statusButton(
    String status,
    Color baseColor,
    Map<String, dynamic> data,
  ) {
    final bool isSelected = data['status'] == status;

    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: isSelected
            ? null
            : () {
                _updateStatus(status);
              },

        style: ElevatedButton.styleFrom(
          elevation: isSelected ? 2 : 0,
          backgroundColor: isSelected ? baseColor : Colors.white,
          foregroundColor: isSelected ? Colors.white : baseColor,
          disabledBackgroundColor: baseColor,
          disabledForegroundColor: Colors.white,

          side: BorderSide(color: baseColor, width: 1.5),

          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),

        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              status == "Resolved"
                  ? Icons.check_circle_outline
                  : Icons.pending_actions_outlined,
              size: 20,
            ),

            const SizedBox(width: 8),

            Flexible(
              child: Text(
                status,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
