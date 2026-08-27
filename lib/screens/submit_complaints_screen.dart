import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:school_connect/service/notification_service.dart';

class SubmitComplaintPage extends StatefulWidget {
  const SubmitComplaintPage({super.key});

  @override
  State<SubmitComplaintPage> createState() => _SubmitComplaintPageState();
}

class _SubmitComplaintPageState extends State<SubmitComplaintPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();
  String? _selectedCategory;
  String _selectedPriority = "Medium";
  bool _isLoading = true;
  String _name = "Loading...";
  String _rollNo = "N/A";
  String _class = "N/A";

  bool _titleError = false;
  bool _detailError = false;
  bool _categoryError = false;
  int _selectedTab = 0;
  final List<String> _categories = [
    "Infrastructure",
    "Staff Issue",
    "Attendance",
    "Others",
  ];

  // ---- Dashboard theme ----
  static const Color navy = Color(0xFF1E3A5F);
  static const Color navyDark = Color(0xFF16304E);
  static const Color accentBlue = Color(0xFF3B82F6);
  static const Color green = Color(0xFF10B981);
  static const Color red = Color(0xFFEF4444);
  static const Color lightBg = Color(0xFFF8FAFC);
  static const Color borderColor = Color(0xFFE5E7EB);

  Future<void> _submitComplaint() async {
    setState(() {
      _titleError = _titleController.text.isEmpty;
      _detailError = _detailController.text.isEmpty;
      _categoryError = _selectedCategory == null;
    });

    if (_categoryError || _titleError || _detailError) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection('complaints').add({
        "userId": user?.uid,
        "studentName": _name,
        "rollNo": _rollNo,
        "class": _class,
        "category": _selectedCategory,
        "title": _titleController.text,
        "details": _detailController.text,
        "priority": _selectedPriority,
        "status": "Pending",
        "sendTo": "Admin",
        "createdAt": FieldValue.serverTimestamp(),
      });
      await NotificationService.sendPushNotification(
        targetRole: 'admin',
        title: 'New Complaint',
        body: '$_name has submitted a new complaint.',
        notificationType: 'complaint',
      );
      if (mounted) {
        _titleController.clear();
        _detailController.clear();
        setState(() => _selectedCategory = null);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text("Complaint Submitted Successfully!"),
            backgroundColor: green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Error: $e"),
          backgroundColor: red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchStudentData();
  }

  Future<void> _fetchStudentData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        DocumentSnapshot userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (userDoc.exists) {
          var data = userDoc.data() as Map<String, dynamic>;
          setState(() {
            _name = data['name'] ?? "No Name";
            _rollNo = data['rollNo'] ?? "N/A";
            _class = data['class'] ?? "N/A";
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // ---------------- Responsive helper ----------------
  double _horizontalPadding(double width) {
    if (width >= 1200) return width * 0.15;
    if (width >= 900) return 48;
    if (width >= 600) return 28;
    return 16;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: lightBg,
      appBar: _buildAppBar(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: navy))
          : DefaultTabController(
              length: 2,
              child: SafeArea(
                child: Column(
                  children: [
                    // Tabs
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.05),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: TabBar(
                        dividerColor: Colors.transparent,
                        indicator: BoxDecoration(
                          color: navy,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey.shade700,
                        labelStyle: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                        unselectedLabelStyle: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                        tabs: const [
                          Tab(
                            height: 55,
                            icon: Icon(Icons.edit_document),
                            text: "New Complaint",
                          ),
                          Tab(
                            height: 55,
                            icon: Icon(Icons.list_alt),
                            text: "My Complaints",
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: TabBarView(
                        children: [
                          // New Complaint Tab
                          SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              _horizontalPadding(
                                MediaQuery.of(context).size.width,
                              ),
                              10,
                              _horizontalPadding(
                                MediaQuery.of(context).size.width,
                              ),
                              28,
                            ),
                            child: Column(
                              children: [
                                _buildInfoCard(),
                                const SizedBox(height: 18),

                                _sectionCard(
                                  child: Column(
                                    children: [
                                      _sectionHeader(
                                        "New Complaint",
                                        Icons.report_gmailerrorred_rounded,
                                      ),
                                      const SizedBox(height: 14),

                                      // Category Dropdown
                                      DropdownButtonFormField<String>(
                                        initialValue: _selectedCategory,
                                        decoration: _inputDecoration(
                                          "Complaint Category *",
                                          icon: Icons.apps_rounded,
                                          errorText: _categoryError
                                              ? "Select a category"
                                              : null,
                                        ),
                                        items: _categories
                                            .map(
                                              (c) => DropdownMenuItem(
                                                value: c,
                                                child: Text(c),
                                              ),
                                            )
                                            .toList(),
                                        onChanged: (val) => setState(() {
                                          _selectedCategory = val;
                                          _categoryError = false;
                                        }),
                                      ),
                                      const SizedBox(height: 16),

                                      // Title
                                      TextField(
                                        controller: _titleController,
                                        onChanged: (val) =>
                                            setState(() => _titleError = false),
                                        decoration: _inputDecoration(
                                          "Complaint Title *",
                                          icon: Icons.edit_rounded,
                                          errorText: _titleError
                                              ? "Title is required"
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(height: 16),

                                      // Details
                                      TextField(
                                        controller: _detailController,
                                        onChanged: (val) => setState(
                                          () => _detailError = false,
                                        ),
                                        maxLines: 4,
                                        decoration: _inputDecoration(
                                          "Complaint Details *",
                                          icon: Icons.notes_rounded,
                                          errorText: _detailError
                                              ? "Details are required"
                                              : null,
                                          alignLabelWithHint: true,
                                        ),
                                      ),
                                      const SizedBox(height: 22),

                                      const Text(
                                        "Priority Level",
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          color: navy,
                                        ),
                                      ),
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: ["High", "Medium", "Low"]
                                            .map(
                                              (level) => _priorityChip(level),
                                            )
                                            .toList(),
                                      ),
                                      const SizedBox(height: 26),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 52,
                                        child: ElevatedButton.icon(
                                          onPressed: _submitComplaint,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: navy,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                          ),
                                          icon: const Icon(
                                            Icons.send_rounded,
                                            size: 19,
                                          ),
                                          label: const Text(
                                            "Submit Complaint",
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // My Complaints Tab
                          SingleChildScrollView(
                            padding: EdgeInsets.fromLTRB(
                              _horizontalPadding(
                                MediaQuery.of(context).size.width,
                              ),
                              18,
                              _horizontalPadding(
                                MediaQuery.of(context).size.width,
                              ),
                              28,
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: navy.withOpacity(0.08),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.list_alt_rounded,
                                        color: navy,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    const Text(
                                      "My Submitted Complaints",
                                      style: TextStyle(
                                        fontSize: 16.5,
                                        fontWeight: FontWeight.bold,
                                        color: navy,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),

                                _buildMyComplaintsList(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: navy,
      elevation: 0,
      centerTitle: true,
      iconTheme: const IconThemeData(color: Colors.white),
      title: const Text(
        "Complaints",
        style: TextStyle(
          color: Colors.white,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
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
      // bottom: PreferredSize(
      //   preferredSize: const Size.fromHeight(1),
      //   child: Container(height: 1, color: Colors.white.withOpacity(0.08)),
      // ),
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    IconData? icon,
    String? errorText,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      labelText: label,
      alignLabelWithHint: alignLabelWithHint,
      errorText: errorText,
      prefixIcon: icon != null
          ? Icon(icon, color: navy.withOpacity(0.7))
          : null,
      filled: true,
      fillColor: lightBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: navy, width: 1.4),
      ),
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      width: double.infinity,
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
      child: child,
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: navy.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: navy, size: 19),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: navy,
          ),
        ),
      ],
    );
  }

  Widget _priorityChip(String level) {
    final bool selected = _selectedPriority == level;
    final Color color = level == "High"
        ? red
        : level == "Medium"
        ? accentBlue
        : green;
    return GestureDetector(
      onTap: () => setState(() => _selectedPriority = level),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: selected ? color : borderColor, width: 1.2),
        ),
        child: Text(
          level,
          style: TextStyle(
            color: selected ? Colors.white : Colors.grey.shade700,
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }

  Widget _buildMyComplaintsList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('complaints')
          .where(
            'userId',
            isEqualTo: FirebaseAuth.instance.currentUser?.uid,
          ) // Sirf us user ki complaints
          .orderBy('createdAt', descending: true) // Nayi complaint sab se upar
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: navy),
            ),
          );
        }

        var complaints = snapshot.data!.docs;

        if (complaints.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: complaints.length,
          itemBuilder: (context, index) {
            var data = complaints[index].data() as Map<String, dynamic>;

            // Status ka color manage karne ke liye
            Color statusColor = accentBlue; // Pending
            if (data['status'] == 'Accepted') {
              statusColor = green;
            } else if (data['status'] == 'Rejected')
              statusColor = red;

            return _buildComplaintCard(data, statusColor);
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: navy.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.inbox_rounded, size: 36, color: navy),
          ),
          const SizedBox(height: 14),
          Text(
            "No complaints submitted yet.",
            style: TextStyle(fontSize: 13.5, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildComplaintCard(Map<String, dynamic> data, Color statusColor) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showComplaintDetails(data),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: navy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.report_gmailerrorred_rounded,
                    color: navy,
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
                        data['title'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                          color: navy,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        "Category: ${data['category']}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    data['status'],
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showComplaintDetails(Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          "Complaint Details",
          style: TextStyle(fontWeight: FontWeight.bold, color: navy),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _detailRow("Category:", data['category']),
              _detailRow("Title:", data['title']),
              _detailRow("Details:", data['details']),
              _detailRow("Submitted By:", _name),
              _detailRow("Submitted To:", data['sendTo'] ?? "Admin"),
              _detailRow("Status:", data['status']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Close", style: TextStyle(color: navy)),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: navy,
                fontSize: 13.5,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13.5, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      width: double.infinity,
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
          CircleAvatar(
            radius: 28,
            backgroundColor: navy.withOpacity(0.1),
            child: const Icon(Icons.person_rounded, size: 28, color: navy),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: navy,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  "Roll No: $_rollNo  |  Class: $_class",
                  style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
