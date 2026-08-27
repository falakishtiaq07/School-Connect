import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:school_connect/service/notification_service.dart';

/// ============================================================
/// OUTER SHELL — header + tab switcher + IndexedStack
/// (keeps both tab bodies alive so state isn't lost on switch)
/// ============================================================
class AttendanceManagementScreen extends StatefulWidget {
  final String teacherClass;
  const AttendanceManagementScreen({super.key, required this.teacherClass});

  @override
  State<AttendanceManagementScreen> createState() =>
      _AttendanceManagementScreenState();
}

class _AttendanceManagementScreenState
    extends State<AttendanceManagementScreen> {
  int _selectedTab = 0; // 0 = Mark Attendance, 1 = Attendance History
  final GlobalKey<_AttendanceHistoryBodyState> _historyKey =
      GlobalKey<_AttendanceHistoryBodyState>();
  // ---- Dashboard theme ----
  static const Color navy = Color(0xFF1E3A5F);
  static const Color navyDark = Color(0xFF16304E);
  static const Color bg = Color(0xFFF0F4F8);
  static const Color borderColor = Color(0xFFE5E7EB);

  double _horizontalPadding(double width) {
    if (width >= 1200) return 24;
    if (width >= 900) return 20;
    if (width >= 600) return 16;
    return 12;
  }

  void _switchToHistoryTab() => setState(() => _selectedTab = 1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: _buildHeader(),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double hPad = _horizontalPadding(constraints.maxWidth);
            return Column(
              children: [
                _buildTabSelector(hPad),
                Expanded(
                  child: IndexedStack(
                    index: _selectedTab,
                    children: [
                      _MarkAttendanceBody(
                        teacherClass: widget.teacherClass,
                        onOpenHistory: _switchToHistoryTab,
                        horizontalPadding: hPad,
                      ),
                      _AttendanceHistoryBody(
                        key: _historyKey,
                        horizontalPadding: hPad,
                        teacherClass: widget.teacherClass,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildHeader() {
    return AppBar(
      backgroundColor: navy,
      elevation: 0,
      automaticallyImplyLeading: true,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 16,
      toolbarHeight: 68,
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            "Attendance Management",
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 3),
        ],
      ),
      flexibleSpace: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [navy, navyDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
      ),
    );
  }

  Widget _buildTabSelector(double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 4),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              label: "Mark Attendance",
              icon: Icons.edit_calendar_rounded,
              selected: _selectedTab == 0,
              onTap: () => setState(() => _selectedTab = 0),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _tabButton(
              label: "Attendance History",
              icon: Icons.history_rounded,
              selected: _selectedTab == 1,
              onTap: () {
                if (_selectedTab == 1) {
                  _historyKey.currentState?.resetToHistory();
                }

                setState(() {
                  _selectedTab = 1;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? navy : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? navy : borderColor,
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: selected ? Colors.white : navy),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? Colors.white : navy,
                    fontWeight: FontWeight.w600,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// TAB 1 — MARK ATTENDANCE
/// (logic identical to the original MarkAttendanceScreen)
/// ============================================================
class _MarkAttendanceBody extends StatefulWidget {
  final String teacherClass;
  final VoidCallback onOpenHistory;
  final double horizontalPadding;

  const _MarkAttendanceBody({
    required this.teacherClass,
    required this.onOpenHistory,
    required this.horizontalPadding,
  });

  @override
  State<_MarkAttendanceBody> createState() => _MarkAttendanceBodyState();
}

class _MarkAttendanceBodyState extends State<_MarkAttendanceBody> {
  List<Map<String, dynamic>> students = [];
  bool isEditing = false;
  bool isLoading = true;
  String todayDate = "";

  static const Color navy = Color(0xFF1E3A5F);
  static const Color borderColor = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    todayDate = DateTime.now().toString().split(' ')[0];
    fetchStudents();
  }

  Future<void> fetchStudents() async {
    var snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Student')
        .where('class', isEqualTo: widget.teacherClass)
        .get();

    setState(() {
      students = snapshot.docs
          .map(
            (doc) => {
              'id': doc.id,
              'name': doc['name'],
              'rollNo': doc['rollNo'],
              'status': 'Not Marked',
            },
          )
          .toList();
      isLoading = false;
    });
  }

  Future<void> saveAttendance() async {
    String date = DateTime.now().toIso8601String().split('T')[0];
    WriteBatch batch = FirebaseFirestore.instance.batch();

    final firestore = FirebaseFirestore.instance;
    for (var student in students) {
      // Nayi flat collection 'attendance_records'
      DocumentReference ref = FirebaseFirestore.instance
          .collection('attendance_records')
          .doc();

      batch.set(ref, {
        "studentId": student['id'],
        "studentName": student['name'],
        "rollNo": student['rollNo'],
        "class": widget.teacherClass,
        "status": student['status'],
        "date": date,
        "createdAt": FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();

    sendAbsentNotifications(date);
  }

  void sendAbsentNotifications(String date) async {
    for (var student in students) {
      if (student['status'] == 'Absent') {
        DocumentReference notifRef = await FirebaseFirestore.instance
            .collection('notifications')
            .add({
              "userId": student['id'],
              "message":
                  "Attendance Alert: You have been marked ABSENT in class '${widget.teacherClass}' on $date. Please ensure your attendance is maintained regularly. If you believe this attendance was marked by mistake, kindly contact your class teacher immediately.",
              "type": "attendance",
              "date": Timestamp.now(),
              "createdAt": FieldValue.serverTimestamp(),
              "isRead": false,
            });

        await NotificationService.sendPushToUser(
          userId: student['id'], // student ka Firebase UID
          title: 'Attendance Marked',
          body:
              "You have been marked ABSENT in ${widget.teacherClass} on $date",
          notificationType: 'attendance',
          relatedId: notifRef.id,
        );
      }
    }
  }

  // Attendance Summary calculation
  int get countPresent =>
      students.where((s) => s['status'] == 'Present').length;
  int get countAbsent => students.where((s) => s['status'] == 'Absent').length;

  @override
  Widget build(BuildContext context) {
    final double hPad = widget.horizontalPadding;

    return isLoading
        ? const Center(child: CircularProgressIndicator(color: navy))
        : Column(
            children: [
              _buildSummaryHeader(hPad),
              Padding(
                padding: EdgeInsets.fromLTRB(hPad, 6, hPad, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Student List",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: navy,
                      ),
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => isEditing = !isEditing),
                          style: TextButton.styleFrom(foregroundColor: navy),
                          icon: Icon(
                            isEditing
                                ? Icons.close_rounded
                                : Icons.edit_rounded,
                            size: 18,
                          ),
                          label: Text(isEditing ? "Cancel" : "Mark Attendance"),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: students.isEmpty
                    ? _buildEmptyState()
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 16),
                        itemCount: students.length,
                        itemBuilder: (context, index) {
                          var student = students[index];
                          return _buildStudentCard(student);
                        },
                      ),
              ),
              if (isEditing) _buildSaveFooter(hPad),
            ],
          );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: navy.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_outlined, size: 40, color: navy),
          ),
          const SizedBox(height: 16),
          Text(
            "No students found for class ${widget.teacherClass}",
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryHeader(double hPad) {
    return Container(
      margin: EdgeInsets.fromLTRB(hPad, 12, hPad, 4),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // 1. Date Section
          Column(
            children: [
              const Icon(Icons.calendar_today_rounded, color: navy, size: 22),
              const SizedBox(height: 4),
              Text(
                todayDate, // Yahan aapka date variable aa gaya
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: navy,
                ),
              ),
            ],
          ),

          // 2. Vertical Divider
          Container(
            height: 44,
            width: 1,
            margin: const EdgeInsets.symmetric(horizontal: 14),
            color: borderColor,
          ),

          // 3. Summary Section (Class, Present, Absent)
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem(
                  "Class ${widget.teacherClass}",
                  "${students.length}",
                  Icons.groups_rounded,
                  navy,
                ),
                _summaryItem(
                  "Present",
                  "$countPresent",
                  Icons.check_circle_rounded,
                  Colors.green.shade600,
                ),
                _summaryItem(
                  "Absent",
                  "$countAbsent",
                  Icons.cancel_rounded,
                  Colors.red.shade600,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryItem(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildStudentCard(Map<String, dynamic> student) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: navy.withOpacity(0.1),
            child: Text(
              "${student['rollNo']}",
              style: const TextStyle(
                color: navy,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "${student['name']}",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14.5,
                color: navy,
              ),
            ),
          ),
          isEditing
              ? _buildEditControls(student)
              : _buildStatusView(student['status']),
        ],
      ),
    );
  }

  Widget _buildStatusView(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: status == 'Present'
            ? Colors.green.shade50
            : status == 'Absent'
            ? Colors.red.shade50
            : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 12.5,
          color: status == 'Present'
              ? Colors.green.shade700
              : status == 'Absent'
              ? Colors.red.shade700
              : Colors.grey.shade700,
        ),
      ),
    );
  }

  Widget _buildEditControls(Map<String, dynamic> student) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: student['status'] == 'Present'
                ? Colors.green.shade600
                : Colors.grey.shade300,
            foregroundColor: student['status'] == 'Present'
                ? Colors.white
                : Colors.grey.shade700,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            setState(() {
              student['status'] = 'Present';
            });
          },
          child: const Text("Present", style: TextStyle(fontSize: 12.5)),
        ),
        const SizedBox(width: 6),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: student['status'] == 'Absent'
                ? Colors.red.shade600
                : Colors.grey.shade300,
            foregroundColor: student['status'] == 'Absent'
                ? Colors.white
                : Colors.grey.shade700,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            setState(() {
              student['status'] = 'Absent';
            });
          },
          child: const Text("Absent", style: TextStyle(fontSize: 12.5)),
        ),
      ],
    );
  }

  Widget _buildSaveFooter(double hPad) {
    return Container(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: navy,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: () {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                "Confirm Attendance",
                style: TextStyle(fontWeight: FontWeight.bold, color: navy),
              ),
              content: const Text(
                "Are you sure you want to save today's attendance?",
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    "Cancel",
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: navy,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () async {
                    Navigator.pop(context);
                    await saveAttendance();
                    setState(() => isEditing = false);
                  },
                  child: const Text("Yes Save"),
                ),
              ],
            ),
          );
        },
        icon: const Icon(Icons.check_rounded),
        label: const Text(
          "SAVE ATTENDANCE",
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
    );
  }
}

/// ============================================================
/// TAB 2 — ATTENDANCE HISTORY
/// (logic identical to the original AttendanceHistoryScreen)
/// ============================================================
class _AttendanceHistoryBody extends StatefulWidget {
  final double horizontalPadding;
  final String teacherClass;
  const _AttendanceHistoryBody({
    super.key,
    required this.horizontalPadding,
    required this.teacherClass,
  });

  @override
  State<_AttendanceHistoryBody> createState() => _AttendanceHistoryBodyState();
}

class _AttendanceHistoryBodyState extends State<_AttendanceHistoryBody> {
  bool isSelectionMode = false;

  Map<String, bool> selectedItems = {};
  String? selectedDate; // Filter variable
  bool showAttendanceCount = false;
  static const Color navy = Color(0xFF1E3A5F);
  static const Color borderColor = Color(0xFFE5E7EB);

  void _deleteSelected() async {
    final toDelete = selectedItems.entries
        .where((e) => e.value)
        .map((e) => e.key)
        .toList();
    if (toDelete.isEmpty) return;

    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Bulk Delete",
          style: TextStyle(fontWeight: FontWeight.bold, color: navy),
        ),
        content: Text(
          "Are you sure you want to delete ${toDelete.length} records?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
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

  void resetToHistory() {
    setState(() {
      showAttendanceCount = false;
      isSelectionMode = false;
      selectedItems.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final double hPad = widget.horizontalPadding;

    // Dynamic Query Logic
    Query query = FirebaseFirestore.instance
        .collection('attendance_records')
        .where('class', isEqualTo: widget.teacherClass)
        .orderBy('createdAt', descending: true);

    if (selectedDate != null) {
      query = query.where('date', isEqualTo: selectedDate);
    }
    return Column(
      children: [
        if (!showAttendanceCount) _buildFilterBar(hPad),

        Expanded(
          child: showAttendanceCount
              ? _buildAttendanceCount()
              : StreamBuilder<QuerySnapshot>(
                  stream: query.snapshots(),
                  builder: (context, snapshot) {
                    // 1. Loading state handle karein
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: navy),
                      );
                    }

                    // 2. Error state handle karein
                    if (snapshot.hasError) {
                      return Center(child: Text("Error: ${snapshot.error}"));
                    }

                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 84,
                              height: 84,
                              decoration: BoxDecoration(
                                color: navy.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.description_outlined,
                                size: 38,
                                color: navy,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              selectedDate != null
                                  ? "No records found for $selectedDate"
                                  : "No attendance records found",
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade600,
                              ),
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
                          margin: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: borderColor),
                          ),
                          child: Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(() {
                                    isSelectionMode = !isSelectionMode;

                                    if (!isSelectionMode) {
                                      selectedItems.clear();
                                    }
                                  });
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: navy,
                                  side: const BorderSide(color: navy),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                icon: Icon(
                                  isSelectionMode
                                      ? Icons.close_rounded
                                      : Icons.checklist_rounded,
                                  size: 18,
                                ),
                                label: Text(
                                  isSelectionMode ? "Cancel" : "Select",
                                ),
                              ),

                              const SizedBox(width: 10),

                              if (!isSelectionMode)
                                ElevatedButton.icon(
                                  onPressed: () {
                                    setState(() {
                                      showAttendanceCount =
                                          !showAttendanceCount;
                                    });
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: navy,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: Icon(
                                    showAttendanceCount
                                        ? Icons.history
                                        : Icons.analytics_outlined,
                                    size: 18,
                                  ),
                                  label: Text(
                                    showAttendanceCount
                                        ? "History"
                                        : "Attendance Count",
                                  ),
                                ),

                              if (isSelectionMode)
                                ElevatedButton.icon(
                                  onPressed: _deleteSelected,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red.shade600,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 18,
                                  ),
                                  label: const Text("Delete"),
                                ),
                            ],
                          ),
                        ),
                        // List View
                        // List View
                        Expanded(
                          child: showAttendanceCount
                              ? _buildAttendanceCount()
                              : ListView.builder(
                                  padding: EdgeInsets.fromLTRB(
                                    hPad,
                                    4,
                                    hPad,
                                    16,
                                  ),
                                  itemCount: records.length,
                                  itemBuilder: (context, index) {
                                    final doc = records[index];
                                    final data =
                                        doc.data() as Map<String, dynamic>;
                                    return _buildHistoryCard(doc.id, data);
                                  },
                                ),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFilterBar(double hPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 12, hPad, 4),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: navy,
                side: const BorderSide(color: navy, width: 1.2),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.calendar_month_rounded, size: 18),
              label: Text(
                selectedDate != null ? "Date: $selectedDate" : "Filter by Date",
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () async {
                DateTime? picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2030),
                );
                if (picked != null) {
                  setState(
                    () => selectedDate = picked.toString().split(' ')[0],
                  );
                }
              },
            ),
          ),
          if (selectedDate != null) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: "Clear filter",
              onPressed: () => setState(() => selectedDate = null),
              icon: const Icon(Icons.clear_rounded, color: Colors.red),
              style: IconButton.styleFrom(
                backgroundColor: Colors.red.withOpacity(0.08),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHistoryCard(String id, Map<String, dynamic> data) {
    final bool isPresent = data['status'] == 'Present';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          isSelectionMode
              ? Checkbox(
                  value: selectedItems[id] ?? false,
                  activeColor: navy,
                  onChanged: (val) => setState(() => selectedItems[id] = val!),
                )
              : CircleAvatar(
                  radius: 19,
                  backgroundColor: isPresent
                      ? Colors.green.shade600
                      : Colors.red.shade600,
                  child: Icon(
                    isPresent ? Icons.check_rounded : Icons.close_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  data['studentName'] ?? 'Unknown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "Date: ${data['date']} | Status: ${data['status']}",
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCount() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('attendance_records')
          .where('class', isEqualTo: widget.teacherClass)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text("No attendance records found"));
        }

        Map<String, Map<String, dynamic>> students = {};

        for (var doc in snapshot.data!.docs) {
          final data = doc.data() as Map<String, dynamic>;

          String id = data['studentId'];
          String name = data['studentName'];
          String roll = data['rollNo'].toString();
          String status = data['status'];

          students.putIfAbsent(id, () {
            return {'name': name, 'roll': roll, 'present': 0, 'absent': 0};
          });

          if (status == "Present") {
            students[id]!['present']++;
          } else {
            students[id]!['absent']++;
          }
        }

        final studentList = students.values.toList();

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(
            widget.horizontalPadding,
            8,
            widget.horizontalPadding,
            16,
          ),
          itemCount: studentList.length,
          itemBuilder: (context, index) {
            final student = studentList[index];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: borderColor),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: navy.withOpacity(.1),
                    child: Text(
                      student['roll'],
                      style: const TextStyle(
                        color: navy,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student['name'],
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              "Present: ${student['present']}",
                              style: const TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 20),
                            Text(
                              "Absent: ${student['absent']}",
                              style: const TextStyle(
                                color: Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
