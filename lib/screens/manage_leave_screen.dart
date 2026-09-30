import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:school_connect/service/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';

class ManageLeavePage extends StatefulWidget {
  const ManageLeavePage({super.key});

  @override
  State<ManageLeavePage> createState() => _ManageLeavePageState();
}

class _ManageLeavePageState extends State<ManageLeavePage> {
  String _selectedFilter = "All";
  String? _teacherClass;

  bool _isSelectionMode = false;
  final List<String> _selectedDocs = [];

  static const Color navy = Color(0xFF1E3A5F);
  static const Color navyDark = Color(0xFF16304E);
  static const Color cardBorder = Color(0xFFE7ECF3);

  @override
  void initState() {
    super.initState();
    _fetchTeacherClass();
  }

  Future<void> _fetchTeacherClass() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    if (doc.exists) {
      setState(() => _teacherClass = doc.data()?['class']);
    }
  }

  Future<void> _confirmDelete() async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          "Delete Requests",
          style: TextStyle(fontWeight: FontWeight.bold, color: navy),
        ),
        content: Text(
          "Are you sure you want to delete ${_selectedDocs.length} requests?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      for (String id in _selectedDocs) {
        await FirebaseFirestore.instance
            .collection('leave_requests')
            .doc(id)
            .delete();
      }
      setState(() {
        _isSelectionMode = false;
        _selectedDocs.clear();
      });
    }
  }

  Future<void> _showConfirmDialog(String docId, String status) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          "Confirm $status",
          style: const TextStyle(fontWeight: FontWeight.bold, color: navy),
        ),
        content: Text("Are you sure you want to $status this request?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: status == "Accepted" ? Colors.green : Colors.red,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              _updateStatus(docId, status);
              Navigator.pop(context);
            },
            child: const Text("Confirm", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  double _horizontalPadding(double width) {
    if (width >= 1200) return 24;
    if (width >= 900) return 20;
    if (width >= 600) return 16;
    return 12;
  }

  @override
  Widget build(BuildContext context) {
    if (_teacherClass == null) {
      return Scaffold(
        backgroundColor: Colors.grey.shade100,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: navy, strokeWidth: 3),
              const SizedBox(height: 16),
              Text(
                "Loading requests...",
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 70,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        title: const Text(
          "Manage Leave Request",
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      floatingActionButton: (_isSelectionMode && _selectedDocs.isNotEmpty)
          ? FloatingActionButton.extended(
              backgroundColor: Colors.red.shade600,
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              onPressed: _confirmDelete,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.white,
              ),
              label: Text(
                "Delete Selected (${_selectedDocs.length})",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double hPad = _horizontalPadding(constraints.maxWidth);
            return Column(
              children: [
                _buildSummarySection(hPad),
                if (!_isSelectionMode) _buildFilterTabs(hPad),
                const SizedBox(height: 6),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('leave_requests')
                        .where('class', isEqualTo: _teacherClass)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: navy),
                        );
                      }

                      var docs = snapshot.data!.docs;
                      docs.sort((a, b) {
                        var dataA = a.data() as Map<String, dynamic>;
                        var dataB = b.data() as Map<String, dynamic>;

                        Timestamp? timeA =
                            dataA['createdAt'] ?? dataA['fromDate'];
                        Timestamp? timeB =
                            dataB['createdAt'] ?? dataB['fromDate'];

                        if (timeA == null || timeB == null) return 0;
                        return timeB.compareTo(timeA);
                      });
                      if (_selectedFilter != "All") {
                        docs = docs
                            .where((d) => d['status'] == _selectedFilter)
                            .toList();
                      }

                      if (docs.isEmpty) {
                        return _buildEmptyState();
                      }

                      return ListView.builder(
                        padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 90),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          var data = docs[index].data() as Map<String, dynamic>;
                          return _buildRequestCard(docs[index].id, data);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: navy,
      elevation: 0,
      centerTitle: false,
      iconTheme: const IconThemeData(color: Colors.white),
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(
              Icons.fact_check_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Flexible(
            child: Text(
              "Leave Requests",
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
              ),
            ),
          ),
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

  Widget _buildSummarySection(double hPad) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('leave_requests')
          .where('class', isEqualTo: _teacherClass)
          .snapshots(),
      builder: (context, snapshot) {
        int p = 0, a = 0, r = 0;
        if (snapshot.hasData) {
          for (var d in snapshot.data!.docs) {
            if (d['status'] == 'Pending') {
              p++;
            } else if (d['status'] == 'Accepted')
              a++;
            else if (d['status'] == 'Rejected')
              r++;
          }
        }
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 0),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    children: [
                      _summaryCard(
                        "Pending",
                        p,
                        Colors.orange,
                        Icons.hourglass_top_rounded,
                      ),
                      const SizedBox(width: 12),
                      _summaryCard(
                        "Accepted",
                        a,
                        Colors.green,
                        Icons.check_circle_rounded,
                      ),
                      const SizedBox(width: 12),
                      _summaryCard(
                        "Rejected",
                        r,
                        Colors.red,
                        Icons.cancel_rounded,
                      ),
                    ],
                  );
                },
              ),
            ),
            // Select Button
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 4),
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: navy,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: () => setState(() {
                    _isSelectionMode = !_isSelectionMode;
                    if (!_isSelectionMode) _selectedDocs.clear();
                  }),
                  icon: Icon(
                    _isSelectionMode
                        ? Icons.close_rounded
                        : Icons.checklist_rounded,
                    size: 18,
                  ),
                  label: Text(
                    _isSelectionMode ? "Cancel" : "Select",
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(String title, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7ECF3), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "$count",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: color,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 10.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterTabs(double hPad) {
    final filters = ["All", "Pending", "Accepted", "Rejected"];

    return Padding(
      padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          bool isMobile = constraints.maxWidth < 600;

          if (isMobile) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cardBorder, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.filter_list_rounded,
                        size: 18,
                        color: navy,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "Filter: ",
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _selectedFilter,
                        style: const TextStyle(
                          color: navy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  PopupMenuButton<String>(
                    initialValue: _selectedFilter,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (String newValue) {
                      setState(() {
                        _selectedFilter = newValue;
                      });
                    },
                    itemBuilder: (BuildContext context) {
                      return filters.map((String filter) {
                        bool isSelected = _selectedFilter == filter;
                        return PopupMenuItem<String>(
                          value: filter,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                filter,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? navy
                                      : Colors.grey.shade800,
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check, size: 16, color: navy),
                            ],
                          ),
                        );
                      }).toList();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: navy.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            "Change",
                            style: TextStyle(
                              color: navy,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: navy,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: filters.map((f) {
                final bool selected = _selectedFilter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedFilter = f),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? navy : Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: selected ? navy : cardBorder,
                          width: 1.2,
                        ),
                      ),
                      child: Text(
                        f,
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.grey.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _statCard(String title, String count, Color color) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border(top: BorderSide(color: color, width: 3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 16.0),
        child: Column(
          children: [
            Text(
              title,
              style: TextStyle(
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              count,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: navy.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inbox_rounded, size: 42, color: navy),
            ),
            const SizedBox(height: 18),
            const Text(
              "No requests found",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: navy,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Leave requests matching this filter will show up here.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestCard(String id, Map<String, dynamic> data) {
    bool isSelected = _selectedDocs.contains(id);
    final bool isPending = data['status'] == "Pending";
    final bool hasAttachment = (data['attachmentUrl'] ?? '')
        .toString()
        .isNotEmpty;

    final bool isNew = data['teacherRead'] != true;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? const Color(0xFF2E86AB).withOpacity(0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? const Color(0xFF2E86AB) : cardBorder,
          width: isSelected ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () async {
            if (_isSelectionMode) {
              setState(() {
                isSelected ? _selectedDocs.remove(id) : _selectedDocs.add(id);
              });
            } else {
              if (data['teacherRead'] != true) {
                await FirebaseFirestore.instance
                    .collection('leave_requests')
                    .doc(id)
                    .update({'teacherRead': true});
              }

              if (!mounted) return;

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => LeaveDetailPage(data: data, docId: id),
                ),
              );
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isSelectionMode)
                  Padding(
                    padding: const EdgeInsets.only(right: 8, top: 4),
                    child: Checkbox(
                      value: isSelected,
                      activeColor: const Color(0xFF2E86AB),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                      onChanged: (v) => setState(
                        () => v!
                            ? _selectedDocs.add(id)
                            : _selectedDocs.remove(id),
                      ),
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 12, top: 2),
                    child: CircleAvatar(
                      radius: 22,
                      backgroundColor: navy.withOpacity(0.1),
                      child: Text(
                        (data['studentName'] as String).isNotEmpty
                            ? data['studentName'][0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          color: navy,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        "${data['studentName']} ",
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15,
                                          color: navy,
                                        ),
                                      ),
                                    ),

                                    if (isNew)
                                      Container(
                                        width: 9,
                                        height: 9,
                                        margin: const EdgeInsets.only(right: 5),
                                        decoration: const BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                        ),
                                      ),

                                    Text(
                                      "(Roll: ${data['rollNo']})",
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (hasAttachment)
                            Padding(
                              padding: const EdgeInsets.only(left: 6, top: 2),
                              child: Icon(
                                Icons.attach_file_rounded,
                                size: 16,
                                color: Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      if ((data['leaveType'] ?? '').toString().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E86AB).withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              data['leaveType'],
                              style: const TextStyle(
                                color: Color(0xFF2E86AB),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      Text(
                        "Reason: ${data['reason']}",
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.date_range_rounded,
                            size: 13,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              "${DateFormat('dd-MM-yyyy').format((data['fromDate'] as Timestamp).toDate())} to ${DateFormat('dd-MM-yyyy').format((data['toDate'] as Timestamp).toDate())}",
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (!_isSelectionMode && isPending)
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
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
                              onPressed: () =>
                                  _showConfirmDialog(id, "Accepted"),
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: const Text("Accept"),
                            ),
                            ElevatedButton.icon(
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
                              onPressed: () =>
                                  _showConfirmDialog(id, "Rejected"),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: const Text("Reject"),
                            ),
                          ],
                        )
                      else if (!_isSelectionMode)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildStatusBadge(data['status']),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'Accepted'
        ? Colors.green
        : (status == 'Rejected' ? Colors.red : Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Future<void> _updateStatus(String id, String status) async {
    try {
      DocumentSnapshot docSnapshot = await FirebaseFirestore.instance
          .collection('leave_requests')
          .doc(id)
          .get();

      if (!docSnapshot.exists) return;
      final data = docSnapshot.data() as Map<String, dynamic>;

      String targetUserId =
          data['studentUid'] ?? data['userId'] ?? data['uid'] ?? '';

      await FirebaseFirestore.instance
          .collection('leave_requests')
          .doc(id)
          .update({'status': status});

      try {
        String title = 'Leave Request Update';
        String body = 'Your leave request status has been updated to $status.';

        if (status.toLowerCase() == 'approved') {
          title = 'Leave Approved ✅';
          body = 'Good news! Your leave request has been approved.';
        } else if (status.toLowerCase() == 'rejected') {
          title = 'Leave Rejected ❌';
          body = 'Your leave request has been rejected.';
        }

        if (targetUserId.isNotEmpty) {
          await NotificationService.sendPushToUser(
            targetUserId: targetUserId,
            title: title,
            body: body,
            notificationType: 'leave_update',
            relatedId: id,
          );
        }
      } catch (notificationError) {
        debugPrint('NOTIFICATION ERROR: $notificationError');
      }
    } catch (e) {
      debugPrint('Error updating leave status: $e');
    }
  }
}

class LeaveDetailPage extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId;
  const LeaveDetailPage({super.key, required this.data, required this.docId});

  static const Color navy = Color(0xFF1E3A5F);
  static const Color navyDark = Color(0xFF16304E);
  static const Color accentBlue = Color(0xFF2E86AB);

  bool get _hasAttachment =>
      (data['attachmentUrl'] ?? '').toString().isNotEmpty;

  bool get _isImageAttachment {
    final String type = (data['attachmentType'] ?? '').toString().toLowerCase();
    return type.startsWith('image');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text(
          "Leave Details",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [navy, navyDark],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final double hPad = constraints.maxWidth >= 900
              ? constraints.maxWidth * 0.2
              : (constraints.maxWidth >= 600 ? 32 : 16);
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 20, hPad, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoTile(
                  Icons.person_rounded,
                  "Student Name",
                  "${data['studentName']}",
                ),
                _infoTile(Icons.class_rounded, "Class", data['class'] ?? 'N/A'),
                _infoTile(
                  Icons.badge_rounded,
                  "Roll Number",
                  "${data['rollNo']}",
                ),
                if ((data['leaveType'] ?? '').toString().isNotEmpty)
                  _infoTile(
                    Icons.work_outline_rounded,
                    "Leave Type",
                    "${data['leaveType']}",
                  ),
                _infoTile(
                  Icons.calendar_today_rounded,
                  "From Date",
                  DateFormat(
                    'dd-MM-yyyy',
                  ).format((data['fromDate'] as Timestamp).toDate()),
                ),
                _infoTile(
                  Icons.event_rounded,
                  "To Date",
                  DateFormat(
                    'dd-MM-yyyy',
                  ).format((data['toDate'] as Timestamp).toDate()),
                ),
                _infoTile(
                  Icons.label_rounded,
                  "Status",
                  "${data['status']}",
                  valueColor: data['status'] == 'Accepted'
                      ? Colors.green
                      : (data['status'] == 'Rejected'
                            ? Colors.red
                            : Colors.orange),
                ),
                _reasonTile(),
                if (_hasAttachment) ...[
                  const SizedBox(height: 16),
                  _attachmentSection(context),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _infoTile(
    IconData icon,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: navy.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: navy, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade500,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reasonTile() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notes_rounded, color: navy, size: 18),
              const SizedBox(width: 8),
              const Text(
                "Reason",
                style: TextStyle(fontWeight: FontWeight.bold, color: navy),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "${data['reason']}",
            style: const TextStyle(fontSize: 14.5, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _attachmentSection(BuildContext context) {
    final String url = (data['attachmentUrl'] ?? '').toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_file_rounded, color: navy, size: 18),
              const SizedBox(width: 8),
              const Text(
                "Attachment",
                style: TextStyle(fontWeight: FontWeight.bold, color: navy),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isImageAttachment) ...[
            GestureDetector(
              onTap: () => _openFullScreenImage(context, url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  height: 220,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 220,
                      color: Colors.grey.shade100,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: navy,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 220,
                    color: Colors.grey.shade100,
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Tap to view full image",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade500,
                fontStyle: FontStyle.italic,
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Colors.red.shade600,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      "PDF document attached",
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openAttachmentUrl(context, url),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text("View PDF"),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accentBlue,
                  side: const BorderSide(color: accentBlue),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openFullScreenImage(BuildContext context, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(child: Image.network(url)),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachmentUrl(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not open attachment"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}
