import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AttendanceHistoryScreen extends StatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  State<AttendanceHistoryScreen> createState() =>
      _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends State<AttendanceHistoryScreen> {
  bool isSelectionMode = false;
  Map<String, bool> selectedItems = {};
  String? selectedDate; // Filter variable

  void _deleteSelected() async {
    final toDelete = selectedItems.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (toDelete.isEmpty) return;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Bulk Delete"),
        content: Text(
          "Are you sure you want to delete ${toDelete.length} records?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var id in toDelete) {
        batch.delete(
          FirebaseFirestore.instance.collection('attendance_records').doc(id),
        );
      }
      await batch.commit();
      setState(() {
        selectedItems.clear();
        isSelectionMode = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Dynamic Query Logic
    Query query = FirebaseFirestore.instance
        .collection('attendance_records')
        .orderBy('createdAt', descending: true);

    if (selectedDate != null) {
      query = query.where('date', isEqualTo: selectedDate);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          "Attendance History",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF0D47A1),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Calendar Button
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () async {
              DateTime? picked = await showDatePicker(
                context: context,
                initialDate: DateTime.now(),
                firstDate: DateTime(2025),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() => selectedDate = picked.toString().split(' ')[0]);
              }
            },
          ),
          if (selectedDate != null)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () => setState(() => selectedDate = null),
            ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          // 1. Loading state handle karein
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // 2. Error state handle karein
          if (snapshot.hasError) {
            return Center(child: Text("Error: ${snapshot.error}"));
          }

          // 3. Data check: Agar data null hai ya docs khali hain
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.description, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  Text(
                    selectedDate != null
                        ? "No records found for $selectedDate"
                        : "No attendance records found",
                    style: const TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          final records = snapshot.data!.docs;

          return Column(
            children: [
              // Selection Bar
              Container(
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade200,
                child: Row(
                  children: [
                    if (isSelectionMode)
                      Checkbox(
                        value:
                            selectedItems.length == records.length &&
                            records.isNotEmpty,
                        onChanged: (val) => setState(() {
                          for (var doc in records) {
                            selectedItems[doc.id] = val!;
                          }
                        }),
                      ),
                    TextButton(
                      onPressed: () =>
                          setState(() => isSelectionMode = !isSelectionMode),
                      child: Text(isSelectionMode ? "Cancel" : "Select"),
                    ),
                    const Spacer(),
                    if (isSelectionMode)
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: _deleteSelected,
                        icon: const Icon(Icons.delete, color: Colors.white),
                        label: const Text(
                          "Delete Selected",
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                  ],
                ),
              ),
              // List View
              Expanded(
                child: ListView.builder(
                  itemCount: records.length,
                  itemBuilder: (context, index) {
                    final doc = records[index];
                    final data = doc.data() as Map<String, dynamic>;
                    return Card(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      child: ListTile(
                        leading: isSelectionMode
                            ? Checkbox(
                                value: selectedItems[doc.id] ?? false,
                                onChanged: (val) => setState(
                                  () => selectedItems[doc.id] = val!,
                                ),
                              )
                            : CircleAvatar(
                                backgroundColor: data['status'] == 'Present'
                                    ? Colors.green
                                    : Colors.red,
                                child: Icon(
                                  data['status'] == 'Present'
                                      ? Icons.check
                                      : Icons.close,
                                  color: Colors.white,
                                ),
                              ),
                        title: Text(data['studentName'] ?? 'Unknown'),
                        subtitle: Text(
                          "Date: ${data['date']} | Status: ${data['status']}",
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
