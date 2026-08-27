import 'dart:convert';

import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:school_connect/service/notification_service.dart';

// -----------------------------------------------------------------------
// THEME CONSTANTS — matches the rest of Maraschool SE
// -----------------------------------------------------------------------
const Color kNavy = Color(0xFF1E3A5F);
const Color kAccentBlue = Color(0xFF2E86AB);
const Color kBgLight = Color(0xFFF4F7FB);

// -----------------------------------------------------------------------
// CLOUDINARY CONFIG
// -----------------------------------------------------------------------
// Uses the same unsigned-upload pattern as the challan PDF uploads
// (cloud name pulled from the existing `challans-pdf` preset setup).
// Replace `kCloudinaryCloudName` with the project's actual cloud name if
// it differs from the one used for challan PDFs.
const String kCloudinaryCloudName = 'dkjsza6pw';
const String kCloudinaryUploadPreset = 'fee-receipts';

/// Student-side screen for uploading a fee-payment receipt image.
/// Only student-facing functionality lives here — no admin verification UI.
class StudentPaymentReceiptScreen extends StatefulWidget {
  /// Optional: pass the challan doc id if this screen is opened from a
  /// specific challan. If null, the screen falls back to the student's
  /// most recent challan (by `roll_no`).
  final String? challanId;

  const StudentPaymentReceiptScreen({super.key, this.challanId});

  @override
  State<StudentPaymentReceiptScreen> createState() =>
      _StudentPaymentReceiptScreenState();
}

class _StudentPaymentReceiptScreenState
    extends State<StudentPaymentReceiptScreen> {
  final _picker = ImagePicker();

  Map<String, dynamic>? _studentData;
  Map<String, dynamic>? _challanData;
  Map<String, dynamic>? _existingReceipt;
  String? _rollNo;

  Uint8List? _pickedImage;
  String? _pickedFileName;

  bool _loadingPage = true;
  bool _uploading = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadEverything();
  }

  // ---------------------------------------------------------------------
  // DATA LOADING
  // ---------------------------------------------------------------------

  Future<void> _loadEverything() async {
    if (!mounted) return;

    setState(() {
      _loadingPage = true;
      _loadError = null;
      _studentData = null;
      _challanData = null;
      _existingReceipt = null;
    });

    try {
      // ============================================================
      // 1. GET CURRENT LOGGED-IN FIREBASE USER
      // ============================================================

      final currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser == null) {
        if (!mounted) return;

        setState(() {
          _loadError = 'No logged-in student found. Please login again.';
          _loadingPage = false;
        });

        return;
      }

      final uid = currentUser.uid;

      // ============================================================
      // 2. GET STUDENT INFORMATION FROM users COLLECTION
      // ============================================================

      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();

      if (!userDoc.exists) {
        if (!mounted) return;

        setState(() {
          _loadError = 'Student account information was not found.';
          _loadingPage = false;
        });

        return;
      }

      final userData = userDoc.data();

      if (userData == null) {
        if (!mounted) return;

        setState(() {
          _loadError = 'Unable to load student account information.';
          _loadingPage = false;
        });

        return;
      }

      final rollNo = userData['rollNo']?.toString();

      if (rollNo == null || rollNo.trim().isEmpty) {
        if (!mounted) return;

        setState(() {
          _loadError = 'Roll number was not found for this student account.';
          _loadingPage = false;
        });

        return;
      }

      _rollNo = rollNo;

      // ============================================================
      // 3. FIND STUDENT PROFILE
      // ============================================================
      //
      // student_profile may use roll_no.
      // We DON'T make this query mandatory.
      // If it doesn't exist, we can still use users data.
      // ============================================================

      try {
        final studentSnap = await FirebaseFirestore.instance
            .collection('student_profile')
            .where('roll_no', isEqualTo: rollNo)
            .limit(1)
            .get();

        if (studentSnap.docs.isNotEmpty) {
          _studentData = studentSnap.docs.first.data();
        }
      } catch (e) {
        // Do not stop the whole screen if student_profile query fails.
        debugPrint('student_profile query error: $e');
      }

      // ============================================================
      // 4. FALLBACK STUDENT DATA FROM users COLLECTION
      // ============================================================

      _studentData ??= <String, dynamic>{};

      _studentData!['student_name'] ??= userData['name'];
      _studentData!['roll_no'] ??= userData['rollNo'];
      _studentData!['grade'] ??= userData['class'];
      _studentData!['email'] ??= userData['email'];
      _studentData!['uid'] ??= uid;

      // ============================================================
      // 5. LOAD CHALLAN
      // ============================================================

      if (widget.challanId != null && widget.challanId!.trim().isNotEmpty) {
        // ----------------------------------------------------------
        // Specific challan was passed to this screen
        // ----------------------------------------------------------

        try {
          final challanDoc = await FirebaseFirestore.instance
              .collection('challans')
              .doc(widget.challanId)
              .get();

          if (challanDoc.exists) {
            _challanData = challanDoc.data();
          }
        } catch (e) {
          debugPrint('Specific challan loading error: $e');
        }
      } else {
        try {
          final challanSnap = await FirebaseFirestore.instance
              .collection('challans')
              .where('roll_no', isEqualTo: rollNo)
              .limit(10)
              .get();

          if (challanSnap.docs.isNotEmpty) {
            // Find latest challan locally.
            QueryDocumentSnapshot<Map<String, dynamic>> latestDoc =
                challanSnap.docs.first;

            DateTime? latestDate;

            for (final doc in challanSnap.docs) {
              final data = doc.data();

              final createdAt = data['created_at'];

              DateTime? currentDate;

              if (createdAt is Timestamp) {
                currentDate = createdAt.toDate();
              } else if (createdAt is DateTime) {
                currentDate = createdAt;
              }

              if (currentDate != null) {
                if (latestDate == null || currentDate.isAfter(latestDate)) {
                  latestDate = currentDate;
                  latestDoc = doc;
                }
              }
            }

            _challanData = latestDoc.data();

            // Save document ID if it is not already present.
            _challanData!['documentId'] = latestDoc.id;
          }
        } catch (e) {
          debugPrint('Challan loading error: $e');
        }
      }

      // ============================================================
      // 6. GET CHALLAN ID
      // ============================================================

      String? challanIdForQuery;

      if (widget.challanId != null && widget.challanId!.trim().isNotEmpty) {
        challanIdForQuery = widget.challanId;
      } else if (_challanData != null) {
        challanIdForQuery =
            _challanData!['challanId']?.toString() ??
            _challanData!['documentId']?.toString() ??
            _challanData!['id']?.toString();
      }

      // ============================================================
      // 7. LOAD EXISTING RECEIPT
      // ============================================================

      _existingReceipt = null;

      try {
        final currentUser = FirebaseAuth.instance.currentUser;

        if (currentUser != null) {
          final receiptSnap = await FirebaseFirestore.instance
              .collection('fee_receipts')
              .where('studentId', isEqualTo: currentUser.uid)
              .limit(20)
              .get();

          if (receiptSnap.docs.isNotEmpty) {
            QueryDocumentSnapshot<Map<String, dynamic>> latestReceipt =
                receiptSnap.docs.first;

            DateTime? latestUploadTime;

            for (final doc in receiptSnap.docs) {
              final data = doc.data();
              final uploadedAt = data['uploadedAt'];

              DateTime? currentUploadTime;

              if (uploadedAt is Timestamp) {
                currentUploadTime = uploadedAt.toDate();
              } else if (uploadedAt is DateTime) {
                currentUploadTime = uploadedAt;
              }

              if (currentUploadTime != null) {
                if (latestUploadTime == null ||
                    currentUploadTime.isAfter(latestUploadTime)) {
                  latestUploadTime = currentUploadTime;
                  latestReceipt = doc;
                }
              }
            }

            _existingReceipt = latestReceipt.data();

            debugPrint('Receipt found: ${_existingReceipt?['status']}');
            debugPrint('Receipt URL: ${_existingReceipt?['receiptImageUrl']}');
          } else {
            debugPrint('No receipt found for current student.');
          }
        }
      } catch (e) {
        debugPrint('Fee receipt loading error: $e');

        // Receipt loading error should not break the screen.
        _existingReceipt = null;
      }

      // ============================================================
      // 8. FINISHED SUCCESSFULLY
      // ============================================================

      if (!mounted) return;

      setState(() {
        _loadingPage = false;
        _loadError = null;
      });
    } catch (e, stackTrace) {
      debugPrint('LOAD EVERYTHING ERROR: $e');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _loadingPage = false;
        _loadError = 'Unable to load student details. Please try again.';
      });
    }
  }

  /// Resolves the current student's `roll_no`.
  ///
  /// NOTE: wire this up to whatever mechanism the rest of the app already
  /// uses to map a logged-in FirebaseAuth user to a `roll_no` (e.g. a
  /// custom claim, a `uid` field on `student_profile`, or a stored
  /// session value). This default assumes a `uid` field exists on the
  /// `student_profile` document — adjust to match the real schema.
  Future<String?> _resolveCurrentRollNo() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return null;

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) return null;

      final data = userDoc.data();

      if (data == null) return null;

      return data['rollNo']?.toString();
    } catch (e) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // IMAGE PICK / SUBMIT
  // ---------------------------------------------------------------------

  Future<void> _pickImage() async {
    try {
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (file == null) return;

      final bytes = await file.readAsBytes();

      setState(() {
        _pickedImage = bytes;
        _pickedFileName = file.name;
      });
    } catch (e) {
      debugPrint('IMAGE PICK ERROR: $e');
      _showSnack('Could not select the receipt image.');
    }
  }

  void _removePickedImage() {
    setState(() {
      _pickedImage = null;
      _pickedFileName = null;
    });
  }

  Future<void> _submitReceipt() async {
    if (_pickedImage == null) {
      _showSnack('Please select your payment receipt.');
      return;
    }
    if (_rollNo == null) {
      _showSnack('Unable to identify the logged-in student.');
      return;
    }

    setState(() => _uploading = true);

    try {
      final secureUrl = await _uploadToCloudinary(_pickedImage!);
      if (secureUrl == null) {
        _showSnack('Receipt upload failed. Please check your connection.');
        setState(() => _uploading = false);
        return;
      }

      final challanIdForSave =
          widget.challanId ?? _challanData?['challanId'] ?? _challanData?['id'];

      final data = {
        'studentId': FirebaseAuth.instance.currentUser?.uid,
        'roll_no': _rollNo,
        'challanId': challanIdForSave,
        'receiptImageUrl': secureUrl,
        'status': 'Pending',
        'uploadedAt': FieldValue.serverTimestamp(),
      };

      DocumentReference receiptRef = await FirebaseFirestore.instance
          .collection('fee_receipts')
          .add(data);
      await NotificationService.sendPushNotification(
        targetRole: 'admin',
        title: 'Payment Receipt Uploaded',
        body: 'A student (Roll No: $_rollNo) has uploaded a fee receipt.',
        notificationType: 'receipt',
        relatedId: receiptRef.id,
      );
      _showSnack('Receipt submitted successfully.');
      setState(() {
        _pickedImage = null;
        _pickedFileName = null;
        _uploading = false;
      });
      await _loadEverything();
    } catch (e) {
      setState(() => _uploading = false);
      _showSnack('Something went wrong while submitting your receipt.');
    }
  }

  Future<String?> _uploadToCloudinary(Uint8List imageBytes) async {
    try {
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$kCloudinaryCloudName/image/upload',
      );

      final request = http.MultipartRequest('POST', uri);

      request.fields['upload_preset'] = kCloudinaryUploadPreset;

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          imageBytes,
          filename: _pickedFileName ?? 'receipt.jpg',
        ),
      );

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      debugPrint('Cloudinary status: ${response.statusCode}');
      debugPrint('Cloudinary response: ${response.body}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        return json['secure_url']?.toString();
      }

      return null;
    } catch (e) {
      debugPrint('CLOUDINARY UPLOAD ERROR: $e');
      return null;
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: kNavy,
      ),
    );
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgLight,
      appBar: _buildAppBar(),
      body: _loadingPage
          ? const Center(child: CircularProgressIndicator(color: kAccentBlue))
          : _loadError != null
          ? _buildErrorState()
          : RefreshIndicator(
              onRefresh: _loadEverything,
              color: kAccentBlue,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStudentCard(),
                  const SizedBox(height: 16),
                  _buildChallanCard(),
                  const SizedBox(height: 16),
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  if (_existingReceipt != null) ...[
                    _buildExistingReceiptCard(),
                    const SizedBox(height: 16),
                  ],
                  if (_canUploadNow()) ...[
                    _buildUploadCard(),
                    const SizedBox(height: 16),
                    if (_pickedImage != null) ...[
                      _buildPreviewCard(),
                      const SizedBox(height: 16),
                    ],
                    _buildSubmitButton(),
                  ],
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text(
        'Paid Challan Receipt',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
      ),
      backgroundColor: kNavy,
      iconTheme: const IconThemeData(color: Colors.white),
      elevation: 4,
      centerTitle: true,
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(
              _loadError ?? 'Something went wrong.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadEverything,
              style: ElevatedButton.styleFrom(backgroundColor: kAccentBlue),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ----- Student info card -----
  Widget _buildStudentCard() {
    final name = _studentData?['student_name'] ?? '—';
    final rollNo = _studentData?['roll_no'] ?? _rollNo ?? '—';
    final grade = _studentData?['grade'] ?? '—';

    return _card(
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: kAccentBlue.withOpacity(0.15),
            child: const Icon(Icons.person, color: kAccentBlue, size: 30),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Student',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Roll No: $rollNo',
                  style: const TextStyle(fontSize: 13, color: Colors.black87),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: kNavy,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              'Class $grade',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Challan info card -----
  Widget _buildChallanCard() {
    if (_challanData == null) {
      return _card(
        child: Row(
          children: const [
            Icon(Icons.receipt_long, color: kAccentBlue),
            SizedBox(width: 10),
            Expanded(child: Text('No challan information found.')),
          ],
        ),
      );
    }

    final challanNumber =
        _challanData?['challanNumber'] ??
        _challanData?['challan_number'] ??
        '—';
    final feeAmount =
        _challanData?['totalFee'] ?? _challanData?['total_fee'] ?? '—';
    final dueDateRaw = _challanData?['dueDate'] ?? _challanData?['due_date'];
    final feeMonth = _challanData?['feeMonth'] ?? _challanData?['fee_month'];
    final feeType = _challanData?['feeType'] ?? _challanData?['fee_type'];

    String dueDateDisplay = '—';
    if (dueDateRaw is Timestamp) {
      dueDateDisplay = DateFormat('d MMM yyyy').format(dueDateRaw.toDate());
    } else if (dueDateRaw is String) {
      dueDateDisplay = dueDateRaw;
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Challan Information',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          _infoRow(Icons.confirmation_number, 'Challan No', '$challanNumber'),
          _infoRow(Icons.payments, 'Fee Amount', '$feeAmount'),
          _infoRow(Icons.event, 'Due Date', dueDateDisplay),
          if (feeMonth != null)
            _infoRow(Icons.calendar_month, 'Fee Month', '$feeMonth'),
          if (feeType != null) _infoRow(Icons.category, 'Fee Type', '$feeType'),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: kAccentBlue),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: Colors.grey)),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ----- Status card -----
  Widget _buildStatusCard() {
    final status = (_existingReceipt?['status'] ?? 'No Receipt').toString();
    final config = _statusConfig(status);

    final adminRemarks = (_existingReceipt?['adminRemarks'] ?? '')
        .toString()
        .trim();

    return _card(
      color: config.bg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(config.icon, color: config.color, size: 30),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status
                Text(
                  config.label,
                  style: TextStyle(
                    color: config.color,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),

                const SizedBox(height: 2),

                // Status description
                Text(
                  config.subtitle,
                  style: const TextStyle(fontSize: 12.5, color: Colors.black87),
                ),

                // Admin Note
                if (adminRemarks.isNotEmpty) ...[
                  const SizedBox(height: 10),

                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: config.color.withOpacity(0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.comment_outlined,
                          size: 18,
                          color: config.color,
                        ),
                        const SizedBox(width: 8),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Admin Remarks',
                                style: TextStyle(
                                  color: config.color,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                adminRemarks,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.black87,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  _StatusConfig _statusConfig(String status) {
    switch (status) {
      case 'Paid':
        return _StatusConfig(
          color: Colors.green.shade700,
          bg: Colors.green.shade50,
          icon: Icons.check_circle,
          label: 'Paid',
          subtitle: 'Your payment has been verified successfully.',
        );
      case 'Rejected':
        return _StatusConfig(
          color: Colors.red.shade700,
          bg: Colors.red.shade50,
          icon: Icons.cancel,
          label: 'Rejected',
          subtitle:
              'Your payment receipt was rejected. Please upload a valid receipt.',
        );
      case 'Pending':
        return _StatusConfig(
          color: Colors.orange.shade800,
          bg: Colors.orange.shade50,
          icon: Icons.access_time_filled,
          label: 'Pending',
          subtitle: 'Your payment receipt is currently under verification.',
        );
      default:
        return _StatusConfig(
          color: Colors.blueGrey,
          bg: Colors.blueGrey.shade50,
          icon: Icons.info_outline,
          label: 'No Receipt Uploaded',
          subtitle: 'Upload your payment receipt below.',
        );
    }
  }

  bool _canUploadNow() {
    final status = _existingReceipt?['status'];
    if (status == 'Paid') return false; // upload disabled once verified
    return true; // no receipt, Pending, or Rejected all allow upload/re-upload
  }

  // ----- Existing receipt card -----
  Widget _buildExistingReceiptCard() {
    final url = _existingReceipt?['receiptImageUrl'] as String?;
    final uploadedAt = _existingReceipt?['uploadedAt'];
    String uploadedDisplay = '—';
    if (uploadedAt is Timestamp) {
      uploadedDisplay = DateFormat('d MMM yyyy').format(uploadedAt.toDate());
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Uploaded Receipt',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          if (url != null)
            GestureDetector(
              onTap: () => _openFullScreenImage(url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    color: Colors.grey.shade200,
                    child: const Icon(Icons.broken_image, color: Colors.grey),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Uploaded: $uploadedDisplay',
            style: const TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  void _openFullScreenImage(String url) {
    Navigator.of(context).push(
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

  void _openFullScreenLocalImage(Uint8List imageBytes) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          body: Center(
            child: InteractiveViewer(child: Image.memory(imageBytes)),
          ),
        ),
      ),
    );
  }

  // ----- Upload card -----
  Widget _buildUploadCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload Payment Receipt',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text(
            'Upload a clear picture of your paid receipt.',
            style: TextStyle(fontSize: 12.5, color: Colors.grey),
          ),
          const SizedBox(height: 2),
          const Text(
            'Supported: JPG • JPEG • PNG',
            style: TextStyle(fontSize: 11.5, color: Colors.grey),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: _pickImage,
            borderRadius: BorderRadius.circular(14),
            child: DottedBorderBox(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(
                    Icons.cloud_upload_outlined,
                    size: 38,
                    color: kAccentBlue,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Choose Receipt Image',
                    style: TextStyle(fontWeight: FontWeight.w600, color: kNavy),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Tap to select a receipt',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ----- Preview card -----
  Widget _buildPreviewCard() {
    return _card(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: const [
                Text(
                  'Receipt Preview',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => _openFullScreenLocalImage(_pickedImage!),
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: Image.memory(
                _pickedImage!,
                height: 200,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.image, size: 18, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _pickedFileName ?? 'receipt.jpg',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.redAccent),
                  onPressed: _uploading ? null : _removePickedImage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ----- Submit button -----
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: _uploading ? null : _submitReceipt,
        style: ElevatedButton.styleFrom(
          backgroundColor: kAccentBlue,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 3,
        ),
        child: _uploading
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.upload_rounded, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Submit Receipt',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // ----- Generic card wrapper -----
  Widget _card({required Widget child, Color? color, EdgeInsets? padding}) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StatusConfig {
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;
  final String subtitle;

  _StatusConfig({
    required this.color,
    required this.bg,
    required this.icon,
    required this.label,
    required this.subtitle,
  });
}

/// Simple dashed-border upload box (no extra package dependency needed
/// beyond CustomPainter). If the project already uses `dotted_border`
/// (per existing challan screens), swap this for that widget instead.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: kAccentBlue),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: kAccentBlue.withOpacity(0.04),
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      ),
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  final Color color;
  _DashedBorderPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      const Radius.circular(14),
    );

    const dashWidth = 6.0;
    const dashSpace = 4.0;
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();

    for (final metric in metrics) {
      double distance = 0;
      while (distance < metric.length) {
        final next = distance + dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + dashSpace;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) => false;
}
