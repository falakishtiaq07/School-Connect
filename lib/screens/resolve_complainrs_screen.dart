import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:school_connect/screens/complaints_details_screen.dart';

class AdminComplaintsPage extends StatefulWidget {
  const AdminComplaintsPage({super.key});

  @override
  State<AdminComplaintsPage> createState() => _AdminComplaintsPageState();
}

class _AdminComplaintsPageState extends State<AdminComplaintsPage> {
  String filter = "All";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF5F7FB),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 70,
        title: const Text(
          "Resolve Complaints",
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection("complaints")
            .orderBy("createdAt", descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1E3A5F)),
                  SizedBox(height: 16),
                  Text(
                    "Loading complaints...",
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data!.docs;
          int total = docs.length;
          int pending = docs.where((d) => d['status'] == "Pending").length;
          int inProgress = docs
              .where((d) => d['status'] == "In Progress")
              .length;
          int resolved = docs.where((d) => d['status'] == "Resolved").length;

          // Filtering logic
          final filteredDocs = docs.where((d) {
            if (filter == "All") return true;
            return d['status'] == filter;
          }).toList();

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1300),
              child: Column(
                children: [
                  // 1. Side-by-side Scrollable Stats Cards
                  SizedBox(
                    height: 110,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      children: [
                        SizedBox(
                          width: 210,
                          child: _statCard(
                            "Total",
                            total.toString(),
                            Colors.blue,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 210,
                          child: _statCard(
                            "Pending",
                            pending.toString(),
                            Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 210,
                          child: _statCard(
                            "In Progress",
                            inProgress.toString(),
                            Colors.blueAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 210,
                          child: _statCard(
                            "Resolved",
                            resolved.toString(),
                            Colors.green,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Horizontal Scrollable Filter Options
                  SizedBox(
                    height: 60,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      children: ["All", "Pending", "In Progress", "Resolved"]
                          .map((f) {
                            final selected = filter == f;
                            return Padding(
                              padding: const EdgeInsets.only(right: 10),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(30),
                                onTap: () => setState(() => filter = f),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? const Color(0xFF1E3A5F)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(30),
                                    border: Border.all(
                                      color: selected
                                          ? const Color(0xFF1E3A5F)
                                          : Colors.grey.shade300,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(.05),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    f,
                                    style: TextStyle(
                                      color: selected
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          })
                          .toList(),
                    ),
                  ),

                  // 3. Responsive List View
                  Expanded(
                    child: filteredDocs.isEmpty
                        ? const Center(
                            child: Text(
                              "No complaints found",
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 16,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredDocs.length,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemBuilder: (context, index) {
                              final data =
                                  filteredDocs[index].data()
                                      as Map<String, dynamic>;
                              final isRead = data['isRead'] ?? false;

                              return Container(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(18),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(.05),
                                      blurRadius: 12,
                                      offset: const Offset(0, 5),
                                    ),
                                  ],
                                ),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(18),
                                  onTap: () async {
                                    if (!isRead) {
                                      await FirebaseFirestore.instance
                                          .collection('complaints')
                                          .doc(filteredDocs[index].id)
                                          .update({'isRead': true});
                                    }

                                    if (!context.mounted) return;
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ComplaintDetailsPage(
                                          docId: filteredDocs[index].id,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          height: 52,
                                          width: 52,
                                          decoration: BoxDecoration(
                                            color: const Color(
                                              0xFF1E3A5F,
                                            ).withOpacity(.08),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: const Icon(
                                            Icons.support_agent_rounded,
                                            color: Color(0xFF1E3A5F),
                                          ),
                                        ),
                                        const SizedBox(width: 16),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  if (!isRead) ...[
                                                    Container(
                                                      width: 10,
                                                      height: 10,
                                                      decoration:
                                                          const BoxDecoration(
                                                            color: Colors.red,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  Expanded(
                                                    child: Text(
                                                      data['title'] ??
                                                          "No Title",
                                                      style: const TextStyle(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                      maxLines: 1,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons
                                                        .calendar_today_outlined,
                                                    size: 15,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Text(
                                                    data['createdAt'] != null
                                                        ? DateFormat(
                                                            'dd MMM yyyy',
                                                          ).format(
                                                            (data['createdAt']
                                                                    as Timestamp)
                                                                .toDate(),
                                                          )
                                                        : '',
                                                    style: TextStyle(
                                                      color:
                                                          Colors.grey.shade600,
                                                      fontSize: 13,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              _buildStatusBadge(
                                                data['status'] ?? "Pending",
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        const Align(
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.arrow_forward_ios,
                                            size: 18,
                                            color: Colors.grey,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

Widget _buildStatusBadge(String status) {
  Color color;
  IconData icon;

  switch (status) {
    case "Resolved":
      color = Colors.green;
      icon = Icons.check_circle;
      break;
    case "In Progress":
      color = Colors.blue;
      icon = Icons.sync;
      break;
    default:
      color = Colors.orange;
      icon = Icons.pending_actions;
  }

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: color.withOpacity(.08),
      borderRadius: BorderRadius.circular(30),
      border: Border.all(color: color.withOpacity(.35)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text(
          status,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ],
    ),
  );
}

Widget _statCard(String title, String count, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: color.withOpacity(0.12),
          child: Icon(Icons.bar_chart_rounded, color: color, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                count,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
