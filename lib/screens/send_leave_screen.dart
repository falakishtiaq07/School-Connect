import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:school_connect/service/notification_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:school_connect/service/notification_service.dart';

class SendLeaveRequestPage extends StatefulWidget {
  const SendLeaveRequestPage({super.key});

  @override
  State<SendLeaveRequestPage> createState() => _SendLeaveRequestPageState();
}

class _SendLeaveRequestPageState extends State<SendLeaveRequestPage> {
  final TextEditingController _reasonController = TextEditingController();
  String? _studentName, _rollNo, _studentClass;
  DateTime? _fromDate, _toDate;
  String? _selectedType;
  bool _isLoading = true;

  final List<String> _types = ["Sick Leave", "Casual Leave", "Emergency"];

  // ---------------- Attachment (new) ----------------
  // TODO: replace with your actual Cloudinary cloud name + an UNSIGNED
  // upload preset (Cloudinary dashboard -> Settings -> Upload -> Add
  // upload preset -> Signing Mode: Unsigned). "auto" resource type lets
  // Cloudinary accept both images and PDFs through the same endpoint.
  static const String _cloudinaryCloudName = "dkjsza6pw";
  static const String _cloudinaryUploadPreset = "leave_images";

  PlatformFile? _selectedAttachment;
  bool _isUploadingAttachment = false;

  @override
  void initState() {
    super.initState();
    _fetchStudentData();
  }

  Future<void> _fetchStudentData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _studentName = data['name'];
          _rollNo = data['rollNo'];
          _studentClass = data['class'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ---------------- Attachment helpers (new) ----------------

  bool _isImageExtension(String? extension) {
    if (extension == null) return false;
    final ext = extension.toLowerCase();
    return ext == 'jpg' || ext == 'jpeg' || ext == 'png';
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedAttachment = result.files.first);
    }
  }

  void _removeAttachment() {
    setState(() => _selectedAttachment = null);
  }

  /// Uploads the picked file to Cloudinary and returns the secure URL.
  /// Throws an Exception on failure (caught by the caller in _submitRequest).
  Future<String> _uploadAttachmentToCloudinary(PlatformFile file) async {
    final uri = Uri.parse(
      "https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/auto/upload",
    );

    final request = http.MultipartRequest("POST", uri)
      ..fields['upload_preset'] = _cloudinaryUploadPreset;

    if (file.bytes != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', file.bytes!, filename: file.name),
      );
    } else if (file.path != null) {
      request.files.add(await http.MultipartFile.fromPath('file', file.path!));
    } else {
      throw Exception("Unable to read the selected file");
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      return data['secure_url'] as String;
    } else {
      throw Exception("Cloudinary upload failed (${response.statusCode})");
    }
  }

  Future<void> _submitRequest() async {
    if (_fromDate == null ||
        _toDate == null ||
        _selectedType == null ||
        _reasonController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please fill all fields"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    setState(() => _isLoading = true);

    // ---- Upload attachment first (if any) ----
    String? attachmentUrl;
    String? attachmentType;

    if (_selectedAttachment != null) {
      setState(() => _isUploadingAttachment = true);
      try {
        attachmentUrl = await _uploadAttachmentToCloudinary(
          _selectedAttachment!,
        );
        attachmentType = _isImageExtension(_selectedAttachment!.extension)
            ? "image"
            : "pdf";
      } catch (e) {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _isUploadingAttachment = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Attachment upload failed: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      if (mounted) setState(() => _isUploadingAttachment = false);
    }

    try {
      // 1. Firestore mein leave request save karein
      DocumentReference leaveRef = await FirebaseFirestore.instance
          .collection('leave_requests')
          .add({
            "studentName": _studentName,
            "rollNo": _rollNo,
            "class": _studentClass,
            "leaveType": _selectedType,
            "fromDate": Timestamp.fromDate(_fromDate!),
            "toDate": Timestamp.fromDate(_toDate!),
            "reason": _reasonController.text.trim(),
            "status": "Pending",
            "createdAt": FieldValue.serverTimestamp(),
            'studentId': FirebaseAuth.instance.currentUser!.uid,
            "attachmentUrl": attachmentUrl ?? "",
            "attachmentType": attachmentType ?? "",
          });

      // 2. Sirf is student ki class ke assigned teacher ko dhoondein
      if (_studentClass != null && _studentClass!.isNotEmpty) {
        final teacherQuery = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'teacher')
            .where('class', isEqualTo: _studentClass)
            .get();

        if (teacherQuery.docs.isNotEmpty) {
          // Teacher ki Firebase UID mil gayi!
          String teacherUid = teacherQuery.docs.first.id;

          // 3. 🌟 FIXED: All-in-one dynamic function ka istemal 🌟
          try {
            await NotificationService.sendPushToUser(
              targetUserId: teacherUid, // Teacher ki exact User ID target hogi
              title: "New Leave Request",
              body:
                  "${_studentName ?? "Student"} has applied for leave. Reason: ${_reasonController.text.trim()}",
              notificationType: "leave_request",
              relatedId: leaveRef.id,
            );
          } catch (notificationError) {
            debugPrint('NOTIFICATION ERROR: $notificationError');
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Request Submitted & Notification Sent to Teacher!"),
            backgroundColor: Colors.green,
          ),
        );

        _reasonController.clear();
        setState(() {
          _fromDate = null;
          _toDate = null;
          _selectedType = null;
          _selectedAttachment = null;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showLeaveDetails(Map<String, dynamic> data) {
    final String attachmentUrl = (data['attachmentUrl'] ?? '').toString();
    final String attachmentType = (data['attachmentType'] ?? '').toString();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.grey[100],
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E3A5F),
            foregroundColor: Colors.white,
            title: const Text("Leave Details"),
            centerTitle: true,
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Center(
                        child: Text(
                          "Request Information",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E3A5F),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _detailRow("Student", data['studentName']),
                      _detailRow("Leave Type", data['leaveType']),
                      _detailRow(
                        "From Date",
                        DateFormat(
                          'dd MMM yyyy',
                        ).format((data['fromDate'] as Timestamp).toDate()),
                      ),
                      _detailRow(
                        "To Date",
                        DateFormat(
                          'dd MMM yyyy',
                        ).format((data['toDate'] as Timestamp).toDate()),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        "Reason",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          data['reason'],
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      if (attachmentUrl.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          "Attachment",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (attachmentType == "image")
                          GestureDetector(
                            onTap: () => _openFullScreenImage(attachmentUrl),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                attachmentUrl,
                                height: 200,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  height: 150,
                                  color: Colors.grey.shade200,
                                  child: const Center(
                                    child: Icon(Icons.broken_image, size: 45),
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () =>
                                  _openAttachmentUrl(attachmentUrl),
                              icon: const Icon(Icons.picture_as_pdf),
                              label: const Text("Open PDF"),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
  // ---------------- Attachment viewing (new) ----------------

  Widget _buildAttachmentDetail(String url, String type) {
    if (type == "image") {
      return GestureDetector(
        onTap: () => _openFullScreenImage(url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            height: 140,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => Container(
              height: 100,
              color: Colors.grey[200],
              alignment: Alignment.center,
              child: const Icon(
                Icons.broken_image_outlined,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _openAttachmentUrl(url),
      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
      label: const Text("Open PDF"),
    );
  }

  void _openFullScreenImage(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(child: InteractiveViewer(child: Image.network(url))),
        ),
      ),
    );
  }

  Future<void> _openAttachmentUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Could not open attachment"),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 70,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        title: const Text(
          "Send Leave Request",
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF1E3A5F)),
            )
          : DefaultTabController(
              length: 2,
              child: SafeArea(
                child: Center(
                  child: Column(
                    children: [
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
                            color: const Color(0xFF1E3A5F),
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
                              text: "New Request",
                            ),
                            Tab(
                              height: 55,
                              icon: Icon(Icons.history),
                              text: "Check Status",
                            ),
                          ],
                        ),
                      ),

                      Expanded(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1300),
                          child: TabBarView(
                            children: [
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final bool isMobile =
                                      constraints.maxWidth < 700;
                                  return SingleChildScrollView(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      children: [
                                        _buildProfileCard(),
                                        const SizedBox(height: 15),

                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  .04,
                                                ),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                          child: DropdownButtonFormField<String>(
                                            value: _selectedType,
                                            decoration: const InputDecoration(
                                              labelText: "Leave Type",
                                              prefixIcon: Icon(
                                                Icons.assignment_outlined,
                                                color: Color(0xFF1E3A5F),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(14),
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(14),
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(14),
                                                ),
                                                borderSide: BorderSide(
                                                  color: Color(0xFF1E3A5F),
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                            items: _types
                                                .map(
                                                  (e) => DropdownMenuItem(
                                                    value: e,
                                                    child: Text(e),
                                                  ),
                                                )
                                                .toList(),
                                            onChanged: (value) {
                                              setState(
                                                () => _selectedType = value,
                                              );
                                            },
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        LayoutBuilder(
                                          builder: (context, constraints) {
                                            final bool isMobile =
                                                constraints.maxWidth < 600;

                                            if (isMobile) {
                                              return Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  _buildDateTile(
                                                    "From Date",
                                                    _fromDate,
                                                    true,
                                                  ),

                                                  const SizedBox(height: 14),

                                                  _buildDateTile(
                                                    "To Date",
                                                    _toDate,
                                                    false,
                                                  ),
                                                ],
                                              );
                                            }

                                            return Row(
                                              children: [
                                                Expanded(
                                                  child: _buildDateTile(
                                                    "From Date",
                                                    _fromDate,
                                                    true,
                                                  ),
                                                ),

                                                const SizedBox(width: 16),

                                                Expanded(
                                                  child: _buildDateTile(
                                                    "To Date",
                                                    _toDate,
                                                    false,
                                                  ),
                                                ),
                                              ],
                                            );
                                          },
                                        ),
                                        const SizedBox(height: 10),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  .04,
                                                ),
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                          child: TextField(
                                            controller: _reasonController,
                                            maxLines: 4,
                                            decoration: const InputDecoration(
                                              labelText: "Reason",
                                              alignLabelWithHint: true,
                                              prefixIcon: Padding(
                                                padding: EdgeInsets.only(
                                                  bottom: 70,
                                                ),
                                                child: Icon(
                                                  Icons.edit_note,
                                                  color: Color(0xFF1E3A5F),
                                                ),
                                              ),
                                              border: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(14),
                                                ),
                                              ),
                                              enabledBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(14),
                                                ),
                                              ),
                                              focusedBorder: OutlineInputBorder(
                                                borderRadius: BorderRadius.all(
                                                  Radius.circular(14),
                                                ),
                                                borderSide: BorderSide(
                                                  color: Color(0xFF1E3A5F),
                                                  width: 2,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 15),
                                        _buildAttachmentSection(),
                                        const SizedBox(height: 15),
                                        SizedBox(
                                          width: double.infinity,
                                          height: 55,
                                          child: ElevatedButton.icon(
                                            onPressed: _isLoading
                                                ? null
                                                : _submitRequest,
                                            icon: const Icon(
                                              Icons.send_rounded,
                                            ),
                                            label: const Text(
                                              "Submit Leave",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            style: ElevatedButton.styleFrom(
                                              elevation: 0,
                                              backgroundColor: const Color(
                                                0xFF1E3A5F,
                                              ),
                                              foregroundColor: Colors.white,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),

                              // History Section
                              LayoutBuilder(
                                builder: (context, constraints) {
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          16,
                                          16,
                                          16,
                                          10,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                            vertical: 14,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  .05,
                                                ),
                                                blurRadius: 8,
                                                offset: const Offset(0, 3),
                                              ),
                                            ],
                                          ),
                                          child: const Row(
                                            children: [
                                              CircleAvatar(
                                                radius: 18,
                                                backgroundColor: Color(
                                                  0xFF1E3A5F,
                                                ),
                                                child: Icon(
                                                  Icons.history,
                                                  color: Colors.white,
                                                  size: 20,
                                                ),
                                              ),
                                              SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  "Your Leave Requests",
                                                  style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight: FontWeight.bold,
                                                    color: Color(0xFF1E3A5F),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),

                                      Expanded(
                                        child: StreamBuilder<QuerySnapshot>(
                                          stream: FirebaseFirestore.instance
                                              .collection('leave_requests')
                                              .where(
                                                'studentId',
                                                isEqualTo: FirebaseAuth
                                                    .instance
                                                    .currentUser!
                                                    .uid,
                                              )
                                              .orderBy(
                                                'createdAt',
                                                descending: true,
                                              )
                                              .snapshots(),
                                          builder: (context, snapshot) {
                                            if (!snapshot.hasData) {
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              );
                                            }

                                            var docs = snapshot.data!.docs;

                                            if (docs.isEmpty) {
                                              return const Center(
                                                child: Text("No history yet"),
                                              );
                                            }

                                            return ListView.builder(
                                              padding: const EdgeInsets.all(16),
                                              itemCount: docs.length,
                                              itemBuilder: (context, index) {
                                                var data =
                                                    docs[index].data()
                                                        as Map<String, dynamic>;

                                                final bool hasAttachment =
                                                    (data['attachmentUrl'] ??
                                                            '')
                                                        .toString()
                                                        .isNotEmpty;

                                                return Container(
                                                  margin: const EdgeInsets.only(
                                                    bottom: 14,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black
                                                            .withOpacity(.05),
                                                        blurRadius: 8,
                                                        offset: const Offset(
                                                          0,
                                                          3,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                  child: InkWell(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    onTap: () =>
                                                        _showLeaveDetails(data),
                                                    child: Padding(
                                                      padding:
                                                          const EdgeInsets.all(
                                                            16,
                                                          ),
                                                      child: Row(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Container(
                                                            height: 50,
                                                            width: 50,
                                                            decoration: BoxDecoration(
                                                              color:
                                                                  const Color(
                                                                    0xFF1E3A5F,
                                                                  ).withOpacity(
                                                                    .08,
                                                                  ),
                                                              borderRadius:
                                                                  BorderRadius.circular(
                                                                    12,
                                                                  ),
                                                            ),
                                                            child: const Icon(
                                                              Icons
                                                                  .description_outlined,
                                                              color: Color(
                                                                0xFF1E3A5F,
                                                              ),
                                                            ),
                                                          ),

                                                          const SizedBox(
                                                            width: 14,
                                                          ),

                                                          Expanded(
                                                            child: Column(
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .start,
                                                              children: [
                                                                Text(
                                                                  data['reason'],
                                                                  maxLines: 1,
                                                                  overflow:
                                                                      TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                    fontSize:
                                                                        16,
                                                                    fontWeight:
                                                                        FontWeight
                                                                            .bold,
                                                                  ),
                                                                ),

                                                                const SizedBox(
                                                                  height: 8,
                                                                ),

                                                                Row(
                                                                  children: [
                                                                    Icon(
                                                                      Icons
                                                                          .calendar_today_outlined,
                                                                      size: 15,
                                                                      color: Colors
                                                                          .grey
                                                                          .shade600,
                                                                    ),
                                                                    const SizedBox(
                                                                      width: 6,
                                                                    ),
                                                                    Expanded(
                                                                      child: Text(
                                                                        DateFormat(
                                                                          'dd MMM yyyy',
                                                                        ).format(
                                                                          (data['fromDate']
                                                                                  as Timestamp)
                                                                              .toDate(),
                                                                        ),
                                                                        style: TextStyle(
                                                                          color: Colors
                                                                              .grey
                                                                              .shade700,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ),

                                                                if (hasAttachment) ...[
                                                                  const SizedBox(
                                                                    height: 8,
                                                                  ),
                                                                  Row(
                                                                    children: const [
                                                                      Icon(
                                                                        Icons
                                                                            .attach_file,
                                                                        size:
                                                                            16,
                                                                        color: Color(
                                                                          0xFF1E3A5F,
                                                                        ),
                                                                      ),
                                                                      SizedBox(
                                                                        width:
                                                                            4,
                                                                      ),
                                                                      Text(
                                                                        "Attachment",
                                                                        style: TextStyle(
                                                                          color: Color(
                                                                            0xFF1E3A5F,
                                                                          ),
                                                                          fontWeight:
                                                                              FontWeight.w500,
                                                                        ),
                                                                      ),
                                                                    ],
                                                                  ),
                                                                ],
                                                              ],
                                                            ),
                                                          ),

                                                          const SizedBox(
                                                            width: 10,
                                                          ),

                                                          _buildStatusBadge(
                                                            data['status'],
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            );
                                          },
                                        ),
                                      ),
                                    ],
                                  );
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
            ),
    );
  }

  Widget _buildProfileCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: const Color(0xFF1E3A5F).withOpacity(.1),
            child: const Icon(Icons.person, size: 30, color: Color(0xFF1E3A5F)),
          ),

          const SizedBox(width: 16),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _studentName ?? "Loading...",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 4),

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Roll No: ${_rollNo ?? "N/A"}",
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),

                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E3A5F),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _studentClass ?? "N/A",
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
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
  }

  Widget _buildStatusBadge(String status) {
    Color color = status == 'Accepted'
        ? Colors.green
        : (status == 'Rejected' ? Colors.red : Colors.orange);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
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

  Widget _buildDateTile(String label, DateTime? date, bool isFrom) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        DateTime? picked = await showDatePicker(
          context: context,
          initialDate: date ?? DateTime.now(),
          firstDate: DateTime.now(),
          lastDate: DateTime(2027),
        );

        if (picked != null) {
          setState(() {
            if (isFrom) {
              _fromDate = picked;
            } else {
              _toDate = picked;
            }
          });
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1E3A5F), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E3A5F).withOpacity(.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.calendar_today_outlined,
                color: Color(0xFF1E3A5F),
                size: 18,
              ),
            ),

            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    date == null
                        ? "Select Date"
                        : DateFormat('dd MMM yyyy').format(date),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: date == null ? Colors.grey : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            const Icon(Icons.arrow_drop_down, color: Color(0xFF1E3A5F)),
          ],
        ),
      ),
    );
  }
  // ---------------- Attachment UI (new) ----------------

  Widget _buildAttachmentSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E3A5F).withOpacity(.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.attach_file, color: Color(0xFF1E3A5F)),
              ),

              const SizedBox(width: 12),

              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Attachment",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Upload image or PDF (Optional)",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          if (_selectedAttachment == null)
            SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: _isLoading ? null : _pickAttachment,
                icon: const Icon(Icons.upload_file),
                label: const Text(
                  "Choose File",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1E3A5F),
                  side: const BorderSide(color: Color(0xFF1E3A5F)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            )
          else
            _buildSelectedAttachmentPreview(),

          if (_isUploadingAttachment) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(color: Color(0xFF1E3A5F)),
          ],
        ],
      ),
    );
  }

  Widget _buildSelectedAttachmentPreview() {
    final PlatformFile file = _selectedAttachment!;
    final bool isImage = _isImageExtension(file.extension);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: isImage && file.bytes != null
                ? Image.memory(
                    file.bytes!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 48,
                    height: 48,
                    color: Colors.white,
                    child: Icon(Icons.picture_as_pdf, color: Colors.red[700]),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              file.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: _isLoading ? null : _removeAttachment,
          ),
        ],
      ),
    );
  }
}

Widget _detailRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(child: Text(value)),
      ],
    ),
  );
}
