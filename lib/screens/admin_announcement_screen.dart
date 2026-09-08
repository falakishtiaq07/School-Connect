import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:school_connect/service/notification_service.dart';

class AdminAnnouncementsScreen extends StatefulWidget {
  const AdminAnnouncementsScreen({super.key});

  @override
  State<AdminAnnouncementsScreen> createState() =>
      _AdminAnnouncementsScreenState();
}

class _AdminAnnouncementsScreenState extends State<AdminAnnouncementsScreen> {
  // ── Colors (prompt palette) ────────────────────────────────────────────────
  static const _navy = Color(0xFF1E3A5F);
  static const _primary = Color(0xFF3B82F6);
  static const _success = Color(0xFF10B981);
  static const _danger = Color(0xFFEF4444);
  static const _border = Color(0xFFE5E7EB);
  static const _textPri = Color(0xFF1F2937);
  static const _textSec = Color(0xFF6B7280);
  static const _bg = Color(0xFFF8FAFC);
  static const _white = Colors.white;
  int selectedTab = 0;
  // ══════════════════════════════════════════════════════════════════════════
  // LOGIC — UNTOUCHED
  // ══════════════════════════════════════════════════════════════════════════

  final titleController = TextEditingController();
  final descController = TextEditingController();

  bool sendToTeachers = false;
  bool sendToStudents = false;
  bool isLoading = false;

  File? attachmentFile;
  final ImagePicker picker = ImagePicker();
  final cloudinary = CloudinaryPublic(
    'dkjsza6pw',
    'announcement_images',
    cache: false,
  );
  Future<void> pickAttachment() async {
    final XFile? picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => attachmentFile = File(picked.path));
    }
  }

  Future<String?> uploadFile(File file) async {
    try {
      CloudinaryResponse response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(file.path),
      );

      debugPrint("IMAGE URL: ${response.secureUrl}");
      return response.secureUrl;
    } catch (e) {
      debugPrint("UPLOAD ERROR: $e");
      return null;
    }
  }

  Future<void> postAnnouncement() async {
    if (titleController.text.trim().isEmpty ||
        descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title & Description required'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (!sendToTeachers && !sendToStudents) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select at least one audience'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => isLoading = true);
    try {
      String? fileUrl;
      if (attachmentFile != null) {
        fileUrl = await uploadFile(attachmentFile!);
      }

      await FirebaseFirestore.instance.collection('announcements').add({
        'title': titleController.text.trim(),
        'description': descController.text.trim(),
        'teachers': sendToTeachers,
        'students': sendToStudents,
        'attachment': fileUrl,
        'createdAt': FieldValue.serverTimestamp(),
      });

      /// --------------------------------------------------------
      /// NOTIFICATION — sirf jo audience actually select ki gayi ho,
      /// aur tag filters ki jagah exact uid list se (reliable).
      /// --------------------------------------------------------
      try {
        final List<String> recipientUids = [];

        if (sendToTeachers) {
          final teacherSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'Teacher')
              .get();
          recipientUids.addAll(
            teacherSnap.docs.map((d) => (d.data()['uid'] ?? d.id).toString()),
          );
        }

        if (sendToStudents) {
          final studentSnap = await FirebaseFirestore.instance
              .collection('users')
              .where('role', isEqualTo: 'Student')
              .get();
          recipientUids.addAll(
            studentSnap.docs.map((d) => (d.data()['uid'] ?? d.id).toString()),
          );
        }

        await NotificationService.sendPushToUsers(
          userIds: recipientUids,
          title: 'New Announcement',
          body: titleController.text,
          notificationType: 'announcement',
        );
      } catch (notificationError) {
        // Announcement Firestore mein save ho chuka hai — notification
        // fail hone par bhi poora flow crash/error nahi dikhana chahiye.
        debugPrint('NOTIFICATION ERROR: $notificationError');
      }

      titleController.clear();
      descController.clear();
      setState(() {
        attachmentFile = null;
        sendToTeachers = false;
        sendToStudents = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Announcement Posted Successfully!'),
            backgroundColor: Color(0xFF28A745),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
    if (mounted) setState(() => isLoading = false);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;

        return Scaffold(
          backgroundColor: _bg,
          appBar: AppBar(
            backgroundColor: _navy,
            foregroundColor: _white,
            elevation: 0,
            title: const Text(
              'Announcements',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
            ),
          ),
          body: Column(
            children: [
              // Tabs
              Container(
                margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE5E7EB)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            selectedTab = 0;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: selectedTab == 0
                                ? _navy
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              "New Announcement",
                              style: TextStyle(
                                color: selectedTab == 0 ? Colors.white : _navy,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            selectedTab = 1;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: selectedTab == 1
                                ? _navy
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Center(
                            child: Text(
                              "Posted Announcements",
                              style: TextStyle(
                                color: selectedTab == 1 ? Colors.white : _navy,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(isWide ? 28 : 16),
                  child: selectedTab == 0
                      ? _FormCard(
                          titleController: titleController,
                          descController: descController,
                          sendToTeachers: sendToTeachers,
                          sendToStudents: sendToStudents,
                          isLoading: isLoading,
                          attachmentFile: attachmentFile,
                          onTeacherToggle: (v) =>
                              setState(() => sendToTeachers = v),
                          onStudentToggle: (v) =>
                              setState(() => sendToStudents = v),
                          onPickAttachment: pickAttachment,
                          onRemoveAttachment: () {
                            setState(() {
                              attachmentFile = null;
                            });
                          },
                          onPost: postAnnouncement,
                        )
                      : _PostedList(isWide: isWide),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabs() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  selectedTab = 0;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selectedTab == 0 ? _navy : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    "New Announcement",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selectedTab == 0 ? Colors.white : _navy,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                setState(() {
                  selectedTab = 1;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: selectedTab == 1 ? _navy : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    "Posted Announcements",
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: selectedTab == 1 ? Colors.white : _navy,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// FORM CARD
// ══════════════════════════════════════════════════════════════════════════════

class _FormCard extends StatelessWidget {
  final TextEditingController titleController;
  final TextEditingController descController;
  final bool sendToTeachers, sendToStudents, isLoading;
  final File? attachmentFile;
  final void Function(bool) onTeacherToggle, onStudentToggle;
  final VoidCallback onPickAttachment;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onPost;
  static const _navy = Color(0xFF1E3A5F);
  static const _primary = Color(0xFF3B82F6);
  static const _success = Color(0xFF10B981);
  static const _border = Color(0xFFE5E7EB);
  static const _textPri = Color(0xFF1F2937);
  static const _textSec = Color(0xFF6B7280);
  static const _white = Colors.white;

  const _FormCard({
    required this.titleController,
    required this.descController,
    required this.sendToTeachers,
    required this.sendToStudents,
    required this.isLoading,
    required this.attachmentFile,
    required this.onTeacherToggle,
    required this.onStudentToggle,
    required this.onPickAttachment,
    required this.onRemoveAttachment,
    required this.onPost,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.campaign_outlined,
                    color: _white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Create New Announcement',
                      style: TextStyle(
                        color: _white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Post announcements for selected users.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.65),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Form body ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                _fieldLabel('Title', required: true),
                const SizedBox(height: 6),
                TextField(
                  controller: titleController,
                  style: const TextStyle(fontSize: 14),
                  decoration: _inputDeco(
                    'Enter announcement title',
                    Icons.title_outlined,
                  ),
                ),
                const SizedBox(height: 16),

                // Description
                _fieldLabel('Description', required: true),
                const SizedBox(height: 6),
                TextField(
                  controller: descController,
                  maxLines: 5,
                  style: const TextStyle(fontSize: 14),
                  decoration: _inputDeco(
                    'Write your announcement here...',
                    Icons.notes_outlined,
                  ),
                ),
                const SizedBox(height: 20),

                // ── Audience ──────────────────────────────────────────────
                _fieldLabel('Audience', required: true),
                const SizedBox(height: 4),
                const Text(
                  'Select who should receive this announcement.',
                  style: TextStyle(fontSize: 12, color: _textSec),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _AudienceTile(
                        icon: Icons.person_outlined,
                        label: 'Teachers',
                        selected: sendToTeachers,
                        color: _success,
                        onChanged: onTeacherToggle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AudienceTile(
                        icon: Icons.school_outlined,
                        label: 'Students',
                        selected: sendToStudents,
                        color: _primary,
                        onChanged: onStudentToggle,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // ── Attachment ────────────────────────────────────────────
                _fieldLabel('Attachment', required: false),
                const SizedBox(height: 6),
                InkWell(
                  onTap: onPickAttachment,

                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: attachmentFile != null
                          ? _success.withOpacity(0.06)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: attachmentFile != null
                            ? _success.withOpacity(0.4)
                            : _border,
                        width: attachmentFile != null ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          attachmentFile != null
                              ? Icons.check_circle_outline
                              : Icons.attach_file_outlined,
                          color: attachmentFile != null ? _success : _textSec,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            attachmentFile != null
                                ? '✔  Image Selected'
                                : '📎  Attachment (Optional)',
                            style: TextStyle(
                              fontSize: 13,
                              color: attachmentFile != null
                                  ? _success
                                  : _textSec,
                              fontWeight: attachmentFile != null
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        attachmentFile != null
                            ? IconButton(
                                onPressed: onRemoveAttachment,
                                icon: const Icon(
                                  Icons.close,
                                  color: Colors.red,
                                  size: 20,
                                ),
                                tooltip: "Remove Image",
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _navy.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Choose Image',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _navy,
                                  ),
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 22),

                // ── Post button ───────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: isLoading ? null : onPost,
                    icon: isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _white,
                            ),
                          )
                        : const Icon(Icons.send_outlined, size: 18),
                    label: Text(
                      isLoading ? 'Posting...' : 'Post Announcement',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: _white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────
  static Widget _fieldLabel(String text, {bool required = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: _textPri,
          ),
        ),
        if (required)
          const Text(
            ' *',
            style: TextStyle(
              color: Color(0xFFEF4444),
              fontWeight: FontWeight.w700,
            ),
          ),
      ],
    );
  }

  static InputDecoration _inputDeco(String hint, IconData icon) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFADB5BD), fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF9CA3AF), size: 18),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
        ),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
      );
}

// ── Audience tile ─────────────────────────────────────────────────────────────

class _AudienceTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final void Function(bool) onChanged;

  const _AudienceTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      child: InkWell(
        onTap: () => onChanged(!selected),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? color.withOpacity(0.08) : const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : const Color(0xFFE5E7EB),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected ? color : const Color(0xFF9CA3AF),
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? color : const Color(0xFF6B7280),
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// POSTED LIST
// ══════════════════════════════════════════════════════════════════════════════

class _PostedList extends StatelessWidget {
  final bool isWide;

  static const _navy = Color(0xFF1E3A5F);
  static const _primary = Color(0xFF3B82F6);
  static const _success = Color(0xFF10B981);
  static const _danger = Color(0xFFEF4444);
  static const _border = Color(0xFFE5E7EB);
  static const _textPri = Color(0xFF1F2937);
  static const _textSec = Color(0xFF6B7280);
  static const _white = Colors.white;

  const _PostedList({required this.isWide});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Section header ─────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.list_alt_outlined,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Posted Announcements',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Recently published announcements.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Stream ─────────────────────────────────────────────────────
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('announcements')
                .orderBy('createdAt', descending: true)
                .snapshots(),
            builder: (context, snapshot) {
              // Loading
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator(color: _navy)),
                );
              }
              // Error
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.wifi_off_outlined,
                          size: 40,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Could not load announcements.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _textSec, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                );
              }
              // Empty
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          size: 48,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'No announcements yet',
                          style: TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Your posted announcements will appear here.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB0B7C3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              final docs = snapshot.data!.docs;
              return ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFF0F0F0)),
                itemBuilder: (ctx, i) {
                  final data = docs[i].data() as Map<String, dynamic>;
                  final docId = docs[i].id;
                  final Timestamp? t = data['createdAt'] as Timestamp?;
                  final dateStr = t != null ? _formatDate(t.toDate()) : 'N/A';

                  return _AnnouncementRow(
                    data: data,
                    docId: docId,
                    dateStr: dateStr,
                    isWide: isWide,
                    context: ctx,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year;
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y  $h:$min';
  }
}

// ── Single announcement row ───────────────────────────────────────────────────

class _AnnouncementRow extends StatelessWidget {
  final Map<String, dynamic> data;
  final String docId, dateStr;
  final bool isWide;
  final BuildContext context;

  static const _navy = Color(0xFF1E3A5F);
  static const _primary = Color(0xFF3B82F6);
  static const _success = Color(0xFF10B981);
  static const _danger = Color(0xFFEF4444);
  static const _textPri = Color(0xFF1F2937);
  static const _textSec = Color(0xFF6B7280);

  const _AnnouncementRow({
    required this.data,
    required this.docId,
    required this.dateStr,
    required this.isWide,
    required this.context,
  });

  // View dialog — logic
  void _showView(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (c) {
        final String? imageUrl = data['attachment'];

        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: EdgeInsets.zero,

          title: Container(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.campaign_outlined,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    data['title'] ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(c),
                  icon: const Icon(Icons.close, color: Colors.white),
                ),
              ],
            ),
          ),

          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  /// Description Heading
                  const Text(
                    "Description",
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 8),

                  Text(
                    data['description'] ?? '',
                    style: const TextStyle(fontSize: 14, height: 1.6),
                  ),

                  if (imageUrl != null && imageUrl.toString().isNotEmpty) ...[
                    const SizedBox(height: 20),

                    const Divider(),

                    const SizedBox(height: 10),

                    const Text(
                      "Attachment",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 10),

                    Center(
                      child: InkWell(
                        onTap: () {
                          showDialog(
                            context: ctx,
                            builder: (_) => Dialog(
                              backgroundColor: Colors.transparent,
                              child: InteractiveViewer(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.network(
                            imageUrl,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(c),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
              ),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  // Delete dialog — logic unchanged
  void _showDelete(BuildContext ctx) {
    showDialog(
      context: ctx,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Delete Announcement',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
        ),
        content: const Text(
          'Are you sure you want to delete this announcement?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              FirebaseFirestore.instance
                  .collection('announcements')
                  .doc(docId)
                  .delete();
              Navigator.pop(c);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext ctx) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: _navy.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.campaign_outlined, color: _navy, size: 18),
          ),
          const SizedBox(width: 14),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  data['title'] ?? '',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _textPri,
                  ),
                ),
                const SizedBox(height: 4),
                // Date
                Row(
                  children: [
                    const Icon(
                      Icons.access_time_outlined,
                      size: 12,
                      color: Color(0xFF9CA3AF),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      dateStr,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF9CA3AF),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Audience badges
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (data['teachers'] == true) _badge('Teachers', _success),
                    if (data['students'] == true) _badge('Students', _primary),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // Actions
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _actionBtn(
                icon: Icons.visibility_outlined,
                color: _primary,
                tip: 'View',
                onTap: () => _showView(ctx),
              ),
              const SizedBox(height: 6),
              _actionBtn(
                icon: Icons.delete_outline,
                color: _danger,
                tip: 'Delete',
                onTap: () => _showDelete(ctx),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Pill badge
  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // Rounded icon action button
  Widget _actionBtn({
    required IconData icon,
    required Color color,
    required String tip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }
}
