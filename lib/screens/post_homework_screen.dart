import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:school_connect/service/notification_service.dart';

/// ============================================================
/// OUTER SHELL — gradient header + custom tabs + IndexedStack
/// ============================================================
class HomeworkManagementScreen extends StatefulWidget {
  const HomeworkManagementScreen({super.key});

  @override
  State<HomeworkManagementScreen> createState() =>
      _HomeworkManagementScreenState();
}

class _HomeworkManagementScreenState extends State<HomeworkManagementScreen> {
  int _selectedTab = 0; // 0 = Post Diary, 1 = Posted Diary

  // ---- Dashboard theme ----
  static const Color navy = Color(0xFF1E3A5F);
  static const Color navyDark = Color(0xFF16304E);
  static const Color bg = Color(0xFFF8FAFC);
  static const Color borderColor = Color(0xFFE5E7EB);

  double _horizontalPadding(double width) {
    if (width >= 1200) return 24;
    if (width >= 900) return 20;
    if (width >= 600) return 16;
    return 12;
  }

  void _switchToListTab() => setState(() => _selectedTab = 1);

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
                      _PostHomeworkBody(
                        onViewPosted: _switchToListTab,
                        horizontalPadding: hPad,
                      ),
                      _PostedHomeworkListBody(horizontalPadding: hPad),
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
            "Homework Diary",
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
              label: "Post Diary",
              emoji: "📚",
              selected: _selectedTab == 0,
              onTap: () => setState(() => _selectedTab = 0),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _tabButton(
              label: "Posted Diary",
              emoji: "📄",
              selected: _selectedTab == 1,
              onTap: () => setState(() => _selectedTab = 1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required String emoji,
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
              Text(emoji, style: const TextStyle(fontSize: 15)),
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
/// TAB 1 — POST CLASS DIARY
/// ============================================================
class _PostHomeworkBody extends StatefulWidget {
  final VoidCallback onViewPosted;
  final double horizontalPadding;

  const _PostHomeworkBody({
    required this.onViewPosted,
    required this.horizontalPadding,
  });

  @override
  State<_PostHomeworkBody> createState() => _PostHomeworkBodyState();
}

class _PostHomeworkBodyState extends State<_PostHomeworkBody> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _titleController = TextEditingController();

  final TextEditingController _descController = TextEditingController();

  final cloudinary = CloudinaryPublic('dkjsza6pw', 'ml_default', cache: false);

  String? teacherClass;
  bool isLoading = false;

  List<PlatformFile> pickedFiles = [];

  static const Color navy = Color(0xFF1E3A5F);
  static const Color borderColor = Color(0xFFE5E7EB);

  @override
  void initState() {
    super.initState();
    _fetchTeacherData();
  }

  /// ==========================================================
  /// FETCH TEACHER CLASS AUTOMATICALLY
  /// ==========================================================
  Future<void> _fetchTeacherData() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          if (!mounted) return;

          setState(() {
            teacherClass = doc.data()?['class'] ?? "N/A";
            isLoading = false;
          });
        } else {
          if (!mounted) return;

          setState(() {
            teacherClass = "N/A";
            isLoading = false;
          });
        }
      } else {
        if (!mounted) return;

        setState(() {
          teacherClass = "N/A";
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        teacherClass = "N/A";
        isLoading = false;
      });
    }
  }

  /// ==========================================================
  /// PICK FILES
  /// ==========================================================
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: true,
      );

      if (result != null) {
        List<PlatformFile> validFiles = [];

        for (var file in result.files) {
          if (file.size <= 10 * 1024 * 1024) {
            validFiles.add(file);
          }
        }

        if (validFiles.isNotEmpty) {
          setState(() {
            pickedFiles.addAll(validFiles);
          });
        }

        if (result.files.length != validFiles.length && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                "Some files were skipped because they exceed 10 MB.",
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("File selection error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// ==========================================================
  /// SUBMIT CLASS DIARY
  /// ==========================================================
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (teacherClass == null ||
        teacherClass!.isEmpty ||
        teacherClass == "N/A") {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Teacher class could not be loaded."),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isLoading = true);

    try {
      List<String> uploadedFileUrls = [];

      /// --------------------------------------------------------
      /// CLOUDINARY UPLOAD
      /// --------------------------------------------------------
      final cloudinary = CloudinaryPublic(
        'dkjsza6pw',
        'homework_images',
        cache: false,
      );

      for (var file in pickedFiles) {
        CloudinaryResponse response;

        if (kIsWeb) {
          if (file.bytes == null) continue;

          String base64Str = base64Encode(file.bytes!);

          response = await cloudinary.uploadFile(
            CloudinaryFile.fromFile(
              "data:application/octet-stream;base64,$base64Str",
              identifier: file.name,
              resourceType: CloudinaryResourceType.Auto,
            ),
          );
        } else {
          if (file.path == null) continue;

          response = await cloudinary.uploadFile(
            CloudinaryFile.fromFile(
              file.path!,
              resourceType: CloudinaryResourceType.Auto,
            ),
          );
        }

        uploadedFileUrls.add(response.secureUrl);
      }

      DocumentReference diaryRef = await FirebaseFirestore.instance
          .collection('homework')
          .add({
            'title': _titleController.text.trim(),
            'description': _descController.text.trim(),
            'class': teacherClass,
            'attachments': uploadedFileUrls,
            'timestamp': FieldValue.serverTimestamp(),
            'teacherId': FirebaseAuth.instance.currentUser?.uid,
          });

      /// --------------------------------------------------------
      /// NOTIFICATION
      /// --------------------------------------------------------
      /// --------------------------------------------------------
      /// NOTIFICATION
      /// --------------------------------------------------------
      try {
        final studentsSnap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'Student')
            .where('class', isEqualTo: teacherClass)
            .get();

        final studentUids = studentsSnap.docs
            .map((d) => (d.data()['uid'] ?? d.id).toString())
            .toList();

        await NotificationService.sendPushToUsers(
          userIds: studentUids,
          title: 'New Class Diary',
          body: _titleController.text.trim(),
          notificationType: 'homework',
          relatedId: diaryRef.id,
        );
      } catch (notificationError) {
        debugPrint('NOTIFICATION ERROR: $notificationError');
      }

      /// --------------------------------------------------------
      /// FORM RESET
      /// --------------------------------------------------------
      if (!mounted) return;

      setState(() {
        _titleController.clear();
        _descController.clear();
        pickedFiles.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Class Diary Posted Successfully!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Upload Error: $e"),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double hPad = widget.horizontalPadding;

    return isLoading && teacherClass == null
        ? const Center(child: CircularProgressIndicator(color: navy))
        : SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// ==================================================
                  /// CLASS INFORMATION
                  /// ==================================================
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          "Class Information",
                          Icons.school_rounded,
                        ),
                        _buildReadOnlyField(
                          "Assigned Class",
                          teacherClass ?? "Loading...",
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// ==================================================
                  /// DIARY DETAILS
                  /// ==================================================
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader(
                          "Diary Details",
                          Icons.assignment_rounded,
                        ),

                        TextFormField(
                          maxLength: 100,
                          controller: _titleController,
                          decoration: _inputDecoration("Diary Title *"),
                          validator: (val) =>
                              (val?.trim().isEmpty ?? true) ? "Required" : null,
                        ),

                        const SizedBox(height: 8),

                        TextFormField(
                          controller: _descController,
                          maxLines: 5,
                          decoration: _inputDecoration(
                            "Description / Instructions",
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  /// ==================================================
                  /// ATTACHMENT
                  /// ==================================================
                  _sectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader("Attachment", Icons.attach_file_rounded),

                        DottedBorder(
                          options: RoundedRectDottedBorderOptions(
                            color: navy.withOpacity(0.35),
                            strokeWidth: 2,
                            dashPattern: const [6, 3],
                            radius: const Radius.circular(12),
                          ),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: navy.withOpacity(0.04),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              children: [
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 10,
                                  children: [
                                    Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 38,
                                      color: navy,
                                    ),

                                    SizedBox(
                                      width: 160,
                                      child: Text(
                                        "Upload Image",
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),

                                    OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: navy,
                                        side: const BorderSide(color: navy),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                      ),
                                      onPressed: isLoading ? null : _pickFile,
                                      icon: const Icon(
                                        Icons.upload_rounded,
                                        size: 18,
                                      ),
                                      label: const Text("Choose File"),
                                    ),
                                  ],
                                ),

                                if (pickedFiles.isNotEmpty)
                                  const SizedBox(height: 12),

                                ...pickedFiles.map(
                                  (f) => Container(
                                    margin: const EdgeInsets.only(top: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(color: borderColor),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.insert_drive_file_rounded,
                                          color: navy,
                                          size: 20,
                                        ),

                                        const SizedBox(width: 10),

                                        Expanded(
                                          child: Text(
                                            f.name,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),

                                        IconButton(
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            color: Colors.red,
                                            size: 20,
                                          ),
                                          onPressed: isLoading
                                              ? null
                                              : () {
                                                  setState(() {
                                                    pickedFiles.remove(f);
                                                  });
                                                },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  /// ==================================================
                  /// BUTTONS
                  /// ==================================================
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: navy,
                            side: const BorderSide(color: navy),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: isLoading
                              ? null
                              : () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                      ),

                      const SizedBox(width: 15),

                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: navy,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          onPressed: isLoading ? null : _submitForm,
                          child: isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2.2,
                                  ),
                                )
                              : const Text("Post Diary"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
  }

  /// ============================================================
  /// INPUT DECORATION
  /// ============================================================
  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: borderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: navy, width: 1.4),
      ),
    );
  }

  /// ============================================================
  /// SECTION CARD
  /// ============================================================
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

  /// ============================================================
  /// SECTION HEADER
  /// ============================================================
  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
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
      ),
    );
  }

  /// ============================================================
  /// READ ONLY CLASS FIELD
  /// ============================================================
  Widget _buildReadOnlyField(String label, String value) {
    return InputDecorator(
      decoration: _inputDecoration(
        label,
      ).copyWith(fillColor: Colors.grey.shade100),
      child: Text(
        value,
        style: const TextStyle(
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }
}

/// ============================================================
/// TAB 2 — POSTED CLASS DIARY LIST
/// ============================================================
class _PostedHomeworkListBody extends StatelessWidget {
  final double horizontalPadding;

  const _PostedHomeworkListBody({required this.horizontalPadding});

  static const Color navy = Color(0xFF1E3A5F);
  static const Color borderColor = Color(0xFFE5E7EB);

  @override
  Widget build(BuildContext context) {
    final double hPad = horizontalPadding;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('homework')
          .where(
            'teacherId',
            isEqualTo: FirebaseAuth.instance.currentUser?.uid.trim(),
          )
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: navy));
        }

        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                "Unable to load diary.\n${snapshot.error}",
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        return ListView.builder(
          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 24),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            final doc = snapshot.data!.docs[index];

            final data = doc.data() as Map<String, dynamic>;

            return _buildDiaryCard(context, doc.id, data);
          },
        );
      },
    );
  }

  /// ============================================================
  /// EMPTY STATE
  /// ============================================================
  Widget _buildEmptyState() {
    return Center(
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
            child: const Icon(Icons.menu_book_rounded, size: 42, color: navy),
          ),
          const SizedBox(height: 18),
          const Text(
            "No Diary Posted Yet",
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: navy,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "Class diary you post will show up here.",
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  /// ============================================================
  /// DIARY CARD
  /// ============================================================
  Widget _buildDiaryCard(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            _showHomeworkDetails(context, data);
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: navy.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.menu_book_rounded,
                    color: navy,
                    size: 20,
                  ),
                ),

                const SizedBox(width: 14),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['title'] ?? "No Title",
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                          color: navy,
                        ),
                      ),

                      const SizedBox(height: 6),

                      _chip(Icons.class_rounded, "${data['class'] ?? 'N/A'}"),

                      const SizedBox(height: 8),

                      if (data['timestamp'] != null)
                        Row(
                          children: [
                            Icon(
                              Icons.event_rounded,
                              size: 13,
                              color: Colors.grey.shade500,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              "Posted: ${_formatTimestamp(data['timestamp'])}",
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.red,
                  ),
                  onPressed: () => _confirmDelete(context, docId),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ============================================================
  /// DATE FORMAT
  /// ============================================================
  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp is Timestamp) {
        return _formatDate(timestamp.toDate());
      }

      return "N/A";
    } catch (_) {
      return "N/A";
    }
  }

  String _formatDate(DateTime date) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec",
    ];

    return "${date.day.toString().padLeft(2, '0')} "
        "${months[date.month - 1]} "
        "${date.year}";
  }

  /// ============================================================
  /// CHIP
  /// ============================================================
  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2E86AB).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF2E86AB)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF2E86AB),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// ============================================================
  /// DETAIL SCREEN
  /// ============================================================
  void _showHomeworkDetails(BuildContext context, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TeacherHomeworkDetailScreen(data: data),
      ),
    );
  }

  /// ============================================================
  /// DELETE
  /// ============================================================
  void _confirmDelete(BuildContext context, String docId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          "Delete Diary",
          style: TextStyle(fontWeight: FontWeight.bold, color: navy),
        ),
        content: const Text("Are you sure you want to delete this diary?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () async {
              try {
                await FirebaseFirestore.instance
                    .collection('homework')
                    .doc(docId)
                    .delete();

                if (context.mounted) {
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Diary deleted successfully."),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  Navigator.pop(context);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text("Delete Error: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

/// ============================================================
/// FULL SCREEN IMAGE
/// ============================================================
class FullScreenImagePage extends StatelessWidget {
  final String imageUrl;

  const FullScreenImagePage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: .8,
          maxScale: 5,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) {
                return child;
              }

              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// ============================================================
/// TEACHER DIARY DETAIL SCREEN
/// ============================================================
class TeacherHomeworkDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const TeacherHomeworkDetailScreen({super.key, required this.data});

  static const Color navy = Color(0xFF1E3A5F);

  @override
  Widget build(BuildContext context) {
    final List attachments = data['attachments'] ?? [];

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: navy,
        foregroundColor: Colors.white,
        title: const Text(
          "Diary Details",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// ==================================================
            /// TITLE
            /// ==================================================
            Text(
              data['title'] ?? "",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 15),

            /// ==================================================
            /// CLASS
            /// ==================================================
            _chip(Icons.class_rounded, "Class : ${data['class'] ?? 'N/A'}"),

            const SizedBox(height: 20),

            /// ==================================================
            /// POSTED DATE
            /// ==================================================
            if (data['timestamp'] != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xffF5F7FB),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  "Posted Date : ${_formatTimestamp(data['timestamp'])}",
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),

            if (data['timestamp'] != null) const SizedBox(height: 20),

            /// ==================================================
            /// DESCRIPTION
            /// ==================================================
            const Text(
              "Description",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: navy,
                fontSize: 16,
              ),
            ),

            const SizedBox(height: 10),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xffF5F7FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                data['description'] ?? "No Description",
                style: const TextStyle(height: 1.6),
              ),
            ),

            /// ==================================================
            /// ATTACHMENTS
            /// ==================================================
            if (attachments.isNotEmpty) ...[
              const SizedBox(height: 22),

              const Text(
                "Attachments",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: navy,
                ),
              ),

              const SizedBox(height: 12),

              ...attachments.map((url) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              FullScreenImagePage(imageUrl: url.toString()),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        url.toString(),
                        width: 180,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ],
          ],
        ),
      ),
    );
  }

  /// ============================================================
  /// CHIP
  /// ============================================================
  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF2E86AB).withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF2E86AB)),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF2E86AB),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// ============================================================
  /// TIMESTAMP FORMAT
  /// ============================================================
  String _formatTimestamp(dynamic timestamp) {
    try {
      if (timestamp is Timestamp) {
        final date = timestamp.toDate();

        const months = [
          "Jan",
          "Feb",
          "Mar",
          "Apr",
          "May",
          "Jun",
          "Jul",
          "Aug",
          "Sep",
          "Oct",
          "Nov",
          "Dec",
        ];

        return "${date.day.toString().padLeft(2, '0')} "
            "${months[date.month - 1]} "
            "${date.year}";
      }

      return "N/A";
    } catch (_) {
      return "N/A";
    }
  }
}
