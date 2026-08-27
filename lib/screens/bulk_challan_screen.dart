import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/widgets.dart' as pw;
import 'package:school_connect/screens/pdf_service_screen.dart';
import 'package:school_connect/service/notification_service.dart';

class BulkGenerateChallanScreen extends StatefulWidget {
  const BulkGenerateChallanScreen({super.key});

  @override
  State<BulkGenerateChallanScreen> createState() =>
      _BulkGenerateChallanScreenState();
}

class _BulkGenerateChallanScreenState extends State<BulkGenerateChallanScreen> {
  static const _navy = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF2E86AB);
  static const _green = Color(0xFF28A745);
  static const _bgColor = Color(0xFFF5F7FA);

  // ── Step 1 ────────────────────────────────────────────────────────────────
  String? _selectedGrade;
  bool _isLoadingStudents = false;

  final List<String> _grades = [
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    '10',
  ];

  // ── Step 2: Dates + Month only (no fee rows) ──────────────────────────────
  String _selectedMonth = _currentMonthYear();
  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 15));
  DateTime _validTill = DateTime.now().add(const Duration(days: 30));

  // ── Step 3 ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _students = [];
  Set<int> _selectedIndexes = {};
  bool _selectAll = true;

  // ── Generation ────────────────────────────────────────────────────────────
  bool _isGenerating = false;
  int _genProgress = 0;
  int _genTotal = 0;
  bool _genDone = false;
  int _genSuccess = 0;
  int _genSaved = 0;
  List<String> _genSkipped = [];
  // Per-student status for save dialog
  List<_ChallanSaveResult> _saveResults = [];

  static String _currentMonthYear() {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final now = DateTime.now();
    return '${months[now.month - 1]}-${now.year}';
  }

  final List<String> _monthOptions = () {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    final year = DateTime.now().year;
    return months.map((m) => '$m-$year').toList();
  }();

  // ── Load students ─────────────────────────────────────────────────────────
  Future<void> _loadStudents() async {
    if (_selectedGrade == null) {
      _showSnack('Please select a Grade first.', isError: true);
      return;
    }
    setState(() {
      _isLoadingStudents = true;
      _students = [];
      _selectedIndexes = {};
      _genDone = false;
      _saveResults = [];
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('student_profile')
          .where('grade', isEqualTo: _selectedGrade)
          .orderBy('roll_no')
          .get();

      final list = snap.docs.map((d) => {'_docId': d.id, ...d.data()}).toList();

      if (mounted) {
        setState(() {
          _students = list;
          _selectedIndexes = Set.from(List.generate(list.length, (i) => i));
          _selectAll = true;
          _isLoadingStudents = false;
        });
      }
      if (list.isEmpty) {
        _showSnack('No students found for $_selectedGrade.', isError: true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingStudents = false);
        _showSnack('Error loading students: $e', isError: true);
      }
    }
  }

  // ── Date picker ───────────────────────────────────────────────────────────
  Future<void> _pickDate(String type) async {
    final init = type == 'issue'
        ? _issueDate
        : type == 'due'
        ? _dueDate
        : _validTill;
    final picked = await showDatePicker(
      context: context,
      initialDate: init,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _navy,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        if (type == 'issue') _issueDate = picked;
        if (type == 'due') _dueDate = picked;
        if (type == 'valid') _validTill = picked;
      });
    }
  }

  String _fmtDate(DateTime d) {
    const abbr = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${d.day.toString().padLeft(2, '0')}-${abbr[d.month - 1]}-${d.year}';
  }

  // ── Cloudinary upload helper ─────────────────────────────────────────────
  Future<String?> _uploadToCloudinary(Uint8List pdfBytes, String rollNo) async {
    const cloudName = 'dkjsza6pw'; // ← apna Cloudinary cloud name
    const uploadPreset = 'challans-pdf'; // ← unsigned upload preset
    // const folder = 'challans';

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudName/raw/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = uploadPreset
      ..fields['public_id'] = 'challan_${rollNo}_$_selectedMonth'
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          pdfBytes,
          filename: 'challan_$rollNo.pdf',
        ),
      );

    final response = await request.send();
    if (response.statusCode == 200) {
      final body = await response.stream.bytesToString();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['secure_url'] as String?;
    }
    return null;
  }

  // ── Bulk PDF generation — separate PDF per student → Cloudinary → Firestore
  Future<void> _generateBulkChallans() async {
    final selected = _selectedIndexes.toList()..sort();
    if (selected.isEmpty) {
      _showSnack('No students selected.', isError: true);
      return;
    }

    // Load school settings
    String schoolName = 'Your School Name';
    String schoolAddress = 'School Address';
    String schoolPhone = '000-0000000';
    String kuickpayId = '0000000000000';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('school_info')
          .get();
      if (doc.exists) {
        schoolName = doc['school_name'] ?? schoolName;
        schoolAddress = doc['address'] ?? schoolAddress;
        schoolPhone = doc['phone'] ?? schoolPhone;
        kuickpayId = doc['kuickpay_id'] ?? kuickpayId;
      }
    } catch (_) {}

    setState(() {
      _isGenerating = true;
      _genProgress = 0;
      _genTotal = selected.length;
      _genSuccess = 0;
      _genSaved = 0;
      _genSkipped = [];
      _genDone = false;
      _saveResults = [];
    });

    final fs = FirebaseFirestore.instance;

    for (final idx in selected) {
      final student = _students[idx];
      final rollNo = student['roll_no']?.toString() ?? '';
      final name = student['student_name']?.toString() ?? '';
      final challanNo = 'CH-${DateTime.now().year}-${rollNo}-${idx + 1}';
      final fatherName = student['father_name']?.toString() ?? '';
      final grade = student['grade']?.toString() ?? '';

      // Fees nested map safely extract
      final feesRaw = student['fees'];
      final fees = feesRaw is Map
          ? Map<String, dynamic>.from(feesRaw)
          : <String, dynamic>{};

      // School Fee + Transport Fee only
      final studentFees = <FeeParticular>[
        FeeParticular(
          name: 'School Fee',
          amount: (fees['school_fee'] ?? 0).toDouble(),
        ),
        FeeParticular(
          name: 'Transport Fee',
          amount: (fees['transport_fee'] ?? 0).toDouble(),
        ),
      ].where((f) => f.amount > 0).toList();

      if (rollNo.isEmpty || name.isEmpty) {
        _genSkipped.add(
          '${name.isEmpty ? "Unknown" : name} (Roll# $rollNo) — incomplete data',
        );
        if (mounted) setState(() => _genProgress++);
        continue;
      }

      final challanData = ChallanData(
        schoolName: schoolName,
        schoolAddress: schoolAddress,
        schoolPhone: schoolPhone,
        kuickpayId: kuickpayId,
        challanNo: challanNo,
        rollNo: rollNo,
        studentName: name,
        fatherName: fatherName,
        classSection: grade,
        month: _selectedMonth,
        issueDate: _fmtDate(_issueDate),
        dueDate: _fmtDate(_dueDate),
        validTill: _fmtDate(_validTill),
        feeParticulars: studentFees,
      );

      // ── 1. Generate separate PDF for this student (3 copies) ──
      final singlePdf = pw.Document();
      ChallanPdfService.addChallanPage(singlePdf, challanData);
      final pdfBytes = await singlePdf.save();

      // ── 2. Upload to Cloudinary ──
      String? pdfUrl;
      try {
        pdfUrl = await _uploadToCloudinary(pdfBytes, rollNo);
      } catch (_) {
        pdfUrl = null;
      }

      // ── 3. Save to Firestore challans collection (roll_no verified) ──
      if (pdfUrl != null) {
        final challanRef = fs.collection('challans').doc();

        await challanRef.set({
          'challan_no': challanNo,
          'roll_no': rollNo,
          'student_name': name,
          'father_name': fatherName,
          'grade': grade,
          'month': _selectedMonth,
          'issue_date': _fmtDate(_issueDate),
          'due_date': _fmtDate(_dueDate),
          'valid_till': _fmtDate(_validTill),
          'pdf_url': pdfUrl,
          'school_fee': fees['school_fee'] ?? 0,
          'transport_fee': fees['transport_fee'] ?? 0,
          'total_fee': challanData.totalAmount,
          'created_at': FieldValue.serverTimestamp(),
          'status': 'unpaid',
        });
        await NotificationService.sendPushNotification(
          targetRole: 'student',
          title: 'New Fee Challan',
          body: 'Your fee challan for $_selectedMonth has been generated.',
          notificationType: 'challan',
          relatedId: challanRef.id,
        );
        _genSaved++;
        _saveResults.add(
          _ChallanSaveResult(
            rollNo: rollNo,
            name: name,
            pdfUrl: pdfUrl,
            success: true,
          ),
        );
      } else {
        _genSkipped.add('$name (Roll# $rollNo) — Cloudinary upload failed');
        _saveResults.add(
          _ChallanSaveResult(
            rollNo: rollNo,
            name: name,
            pdfUrl: '',
            success: false,
          ),
        );
      }

      _genSuccess++;
      if (mounted) setState(() => _genProgress++);
      await Future.delayed(const Duration(milliseconds: 20));
    }

    if (mounted) {
      setState(() {
        _isGenerating = false;
        _genDone = true;
      });
    }
  }

  Future<void> _showSaveResults() async {
    showDialog(
      context: context,
      builder: (_) => _SaveResultsDialog(
        results: _saveResults,
        month: _selectedMonth,
        onDismiss: () => Navigator.pop(context),
      ),
    );
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : _green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text(
          'Bulk Generate Challans',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        elevation: 0,
      ),
      body: _isGenerating
          ? _generatingOverlay()
          : SingleChildScrollView(
              padding: EdgeInsets.all(isWide ? 24 : 16),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              _step1Card(),
                              const SizedBox(height: 16),
                              _step2Card(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 5,
                          child: Column(
                            children: [
                              _step3Card(),
                              if (_genDone) ...[
                                const SizedBox(height: 16),
                                _resultCard(),
                              ],
                            ],
                          ),
                        ),
                      ],
                    )
                  : Column(
                      children: [
                        _step1Card(),
                        const SizedBox(height: 16),
                        _step2Card(),
                        const SizedBox(height: 16),
                        _step3Card(),
                        if (_genDone) ...[
                          const SizedBox(height: 16),
                          _resultCard(),
                        ],
                        const SizedBox(height: 28),
                      ],
                    ),
            ),
    );
  }

  // ── Step 1: Grade ─────────────────────────────────────────────────────────
  Widget _step1Card() {
    return _card(
      stepNo: '1',
      title: 'Select Grade',
      child: Column(
        children: [
          _dropField(
            label: 'Grade',
            value: _selectedGrade,
            items: _grades,
            onChanged: (v) => setState(() => _selectedGrade = v),
            hint: 'Select grade',
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isLoadingStudents ? null : _loadStudents,
              icon: _isLoadingStudents
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.person_search_outlined, size: 18),
              label: Text(_isLoadingStudents ? 'Loading...' : 'Load Students'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Step 2: Month + Dates only (no fee particulars) ───────────────────────
  Widget _step2Card() {
    return _card(
      stepNo: '2',
      title: 'Challan Settings',
      child: Column(
        children: [
          _dropField(
            label: 'Month',
            value: _selectedMonth,
            items: _monthOptions,
            onChanged: (v) {
              if (v != null) setState(() => _selectedMonth = v);
            },
            hint: 'Select month',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _dateTile('Issue Date', _fmtDate(_issueDate), 'issue'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _dateTile('Due Date', _fmtDate(_dueDate), 'due')),
            ],
          ),
          const SizedBox(height: 8),
          _dateTile('Valid Till', _fmtDate(_validTill), 'valid'),
          const SizedBox(height: 12),
          // Info box — fee auto from backend
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFD0F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: _navy, size: 16),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Fee will be auto-fetched from each student\'s record (School Fee + Transport Fee).',
                    style: TextStyle(
                      fontSize: 12,
                      color: _navy,
                      fontWeight: FontWeight.w500,
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

  // ── Step 3: Students List ─────────────────────────────────────────────────
  Widget _step3Card() {
    return _card(
      stepNo: '3',
      title: 'Select Students',
      child: Column(
        children: [
          if (_students.isEmpty && !_isLoadingStudents)
            _emptyStudents()
          else if (_students.isNotEmpty) ...[
            // Select all bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F4FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Checkbox(
                    value: _selectAll,
                    onChanged: (v) {
                      setState(() {
                        _selectAll = v ?? false;
                        _selectedIndexes = _selectAll
                            ? Set.from(
                                List.generate(_students.length, (i) => i),
                              )
                            : {};
                      });
                    },
                    activeColor: _navy,
                  ),
                  const Text(
                    'Select All',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  const Spacer(),
                  Text(
                    '${_selectedIndexes.length}/${_students.length} selected',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            // Student list
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _students.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, color: Color(0xFFEEEEEE)),
              itemBuilder: (_, i) {
                final s = _students[i];
                final isSelected = _selectedIndexes.contains(i);

                // Fee from backend
                final feesRaw = s['fees'];
                final fees = feesRaw is Map
                    ? Map<String, dynamic>.from(feesRaw)
                    : <String, dynamic>{};
                final schoolFee = (fees['school_fee'] ?? 0).toDouble();
                final transportFee = (fees['transport_fee'] ?? 0).toDouble();
                final totalFee = schoolFee + transportFee;

                return InkWell(
                  onTap: () {
                    setState(() {
                      isSelected
                          ? _selectedIndexes.remove(i)
                          : _selectedIndexes.add(i);
                      _selectAll = _selectedIndexes.length == _students.length;
                    });
                  },
                  child: Container(
                    color: isSelected ? const Color(0xFFF0F4FF) : Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Checkbox(
                          value: isSelected,
                          onChanged: (v) {
                            setState(() {
                              v == true
                                  ? _selectedIndexes.add(i)
                                  : _selectedIndexes.remove(i);
                              _selectAll =
                                  _selectedIndexes.length == _students.length;
                            });
                          },
                          activeColor: _navy,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // ── Student name (not father name) ──
                              Text(
                                s['student_name']?.toString() ?? '—',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                              const SizedBox(height: 2),
                              // ── Auto total fee ──
                              Text(
                                'Fee: Rs. ${totalFee.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Roll No chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _navy.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Roll# ${s['roll_no'] ?? '—'}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            // Generate button
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _selectedIndexes.isEmpty
                    ? null
                    : _generateBulkChallans,
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 20),
                label: Text(
                  'Generate ${_selectedIndexes.length} '
                  'Challan${_selectedIndexes.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _emptyStudents() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.group_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text(
            'No students loaded',
            style: TextStyle(
              color: Color(0xFF9CA3AF),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select a grade above and tap Load Students',
            style: TextStyle(color: Color(0xFFB0B7C3), fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ── Result card ───────────────────────────────────────────────────────────
  Widget _resultCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: _green.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline,
              color: _green,
              size: 32,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Challans Generated!',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _resultChip('Generated', '$_genSuccess', _green),
              const SizedBox(width: 12),
              _resultChip('Skipped', '${_genSkipped.length}', Colors.orange),
            ],
          ),
          if (_genSkipped.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Skipped students:',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 4),
                  ..._genSkipped.map(
                    (s) => Text(
                      '• $s',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Saved count info
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                const Icon(Icons.cloud_done_outlined, color: _navy, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '$_genSaved challan(s) saved to student accounts via Cloudinary.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: _navy,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _showSaveResults,
              icon: const Icon(Icons.list_alt_outlined, size: 18),
              label: const Text(
                'View Save Results',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                elevation: 2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultChip(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(
            val,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }

  // ── Generating overlay ────────────────────────────────────────────────────
  Widget _generatingOverlay() {
    final pct = _genTotal > 0 ? _genProgress / _genTotal : 0.0;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(36),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: _navy.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.picture_as_pdf_outlined,
                size: 36,
                color: _navy,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Generating Challans...',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_genProgress of $_genTotal students',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 24),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 14,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: const AlwaysStoppedAnimation<Color>(_navy),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(pct * 100).toStringAsFixed(0)}%',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Reusable helpers ──────────────────────────────────────────────────────
  Widget _card({
    required String stepNo,
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF0F4FF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    color: _navy,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      stepNo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _navy,
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }

  Widget _dropField<T>({
    required String label,
    required T? value,
    required List<T> items,
    required void Function(T?) onChanged,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<T>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(color: Color(0xFFADB5BD), fontSize: 13),
          ),
          decoration: _inputDeco(),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    item.toString(),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _dateTile(String label, String val, String type) {
    return GestureDetector(
      onTap: () => _pickDate(type),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today,
              size: 14,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    val,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 14, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDeco({String? hint}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFADB5BD), fontSize: 12),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: _accent, width: 1.5),
    ),
    filled: true,
    fillColor: Colors.white,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Model: result of saving one student's challan
// ═══════════════════════════════════════════════════════════════════════════

class _ChallanSaveResult {
  final String rollNo;
  final String name;
  final String pdfUrl;
  final bool success;
  const _ChallanSaveResult({
    required this.rollNo,
    required this.name,
    required this.pdfUrl,
    required this.success,
  });
}

// ═══════════════════════════════════════════════════════════════════════════
// Save Results Dialog — shows per-student save status with roll_no verification
// ═══════════════════════════════════════════════════════════════════════════

class _SaveResultsDialog extends StatelessWidget {
  final List<_ChallanSaveResult> results;
  final String month;
  final VoidCallback onDismiss;

  const _SaveResultsDialog({
    required this.results,
    required this.month,
    required this.onDismiss,
  });

  static const _navy = Color(0xFF1E3A5F);
  static const _green = Color(0xFF28A745);
  static const _red = Color(0xFFDC3545);

  @override
  Widget build(BuildContext context) {
    final saved = results.where((r) => r.success).length;
    final failed = results.where((r) => !r.success).length;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
              Icons.cloud_done_outlined,
              color: Colors.white70,
              size: 18,
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Challan Save Results',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              onPressed: onDismiss,
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 420,
        height: 400,
        child: Column(
          children: [
            const SizedBox(height: 14),
            // Summary row
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _chip('Saved', '$saved', _green),
                const SizedBox(width: 12),
                _chip('Failed', '$failed', _red),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(),
            // Per-student list
            Expanded(
              child: ListView.separated(
                itemCount: results.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: Color(0xFFEEEEEE)),
                itemBuilder: (_, i) {
                  final r = results[i];
                  return ListTile(
                    dense: true,
                    leading: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: r.success
                            ? _green.withOpacity(0.1)
                            : _red.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        r.success
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: r.success ? _green : _red,
                        size: 18,
                      ),
                    ),
                    title: Text(
                      r.name,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        // Roll No verified badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _navy.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Roll# ${r.rollNo}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: _navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(
                          Icons.verified_outlined,
                          color: _green,
                          size: 12,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          r.success ? 'Saved to account' : 'Upload failed',
                          style: TextStyle(
                            fontSize: 10,
                            color: r.success ? _green : _red,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            // Info note
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: _navy, size: 14),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Each student can view their challan from the "View Challan" card on their dashboard. Challans are verified by Roll No.',
                      style: TextStyle(fontSize: 10, color: _navy),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: ElevatedButton(
                onPressed: onDismiss,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _navy,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        children: [
          Text(
            val,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}
