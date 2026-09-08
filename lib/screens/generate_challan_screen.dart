import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:school_connect/screens/challan_preview_screen.dart';
import 'package:school_connect/service/notification_service.dart';
import 'pdf_service_screen.dart';
import 'dart:typed_data';

class GenerateChallanScreen extends StatefulWidget {
  const GenerateChallanScreen({super.key});

  @override
  State<GenerateChallanScreen> createState() => _GenerateChallanScreenState();
}

class _GenerateChallanScreenState extends State<GenerateChallanScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isGenerating = false;

  // Student Info Controllers
  final _rollNoController = TextEditingController();
  final _studentNameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _classSectionController = TextEditingController();

  // Manual fee-entry controllers (used only when no backend profile is found)
  final _schoolFeeController = TextEditingController();
  final _acChargesController = TextEditingController();
  final _stationaryFeeController = TextEditingController();

  // Class & Student Selection State
  String? _selectedClass;
  // Holds the Firestore *document id* of the selected student (from the
  // `users` collection), which is the same as the student's Firebase Auth
  // uid (docs are keyed by uid on import). This single field is used both
  // as the Dropdown's unique value AND as the target for the Firestore
  // challan record + push notification — there used to be a second,
  // never-assigned `_selectedStudentUid` field that caused "select a
  // student first" to show even after a student was fully loaded.
  String? _selectedStudentId;
  List<String> _availableClasses = [];
  List<Map<String, dynamic>> _classStudents = [];
  bool _isLoadingClasses = true;
  bool _isLoadingStudents = false;

  // School Info (pre-filled from Firestore settings)
  String _schoolName = '';
  String _schoolAddress = '';
  String _schoolPhone = '';
  String _kuickpayId = '';
  String _challanNo = '';

  // Dates
  DateTime _issueDate = DateTime.now();
  DateTime _dueDate = DateTime.now().add(const Duration(days: 15));
  DateTime _validTill = DateTime.now().add(const Duration(days: 30));
  String _selectedMonth = _currentMonthYear();
  double _schoolFee = 0;
  double _acCharges = 0;
  double _stationaryFee = 0;
  bool _isStudentLoaded = false;
  String _studentDocId = '';

  // True when no `student_profile` record was found for the selected
  // student — fee fields become editable so the admin can enter them by hand.
  bool _manualFeeEntry = false;

  static String _currentMonthYear() {
    final months = [
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
    final months = [
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

  @override
  void initState() {
    super.initState();
    _loadSchoolSettings();
    _fetchClassesFromUsers();
  }

  // ─── Dropdown safety guards ────────────────────────────────────────────────
  String? get _dropdownSafeClass =>
      _availableClasses.contains(_selectedClass) ? _selectedClass : null;

  String? get _dropdownSafeStudentId {
    final ids = _classStudents.map((s) => s['id']).toSet();
    return ids.contains(_selectedStudentId) ? _selectedStudentId : null;
  }

  // ─── Fetch Classes from Users Collection ──────────────────────────────────
  Future<void> _fetchClassesFromUsers() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      final Set<String> classSet = {};

      for (final doc in snap.docs) {
        final data = doc.data();
        final role = (data['role'] ?? '').toString().trim().toLowerCase();

        if (role == 'student') {
          final cls = (data['class'] ?? '').toString().trim();
          if (cls.isNotEmpty) {
            classSet.add(cls);
          }
        }
      }

      if (mounted) {
        setState(() {
          _availableClasses = classSet.toList()..sort();
          _isLoadingClasses = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching classes: $e');
      if (mounted) {
        setState(() => _isLoadingClasses = false);
        _showSnack('Could not load classes. Please try again.');
      }
    }
  }

  // ─── Fetch Students By Selected Class ─────────────────────────────────────
  Future<void> _fetchStudentsForClass(String className) async {
    setState(() {
      _isLoadingStudents = true;
      _classStudents = [];
      _selectedStudentId = null;
      _isStudentLoaded = false;
      _challanNo = '';
      _rollNoController.clear();
      _studentNameController.clear();
      _fatherNameController.clear();
      _classSectionController.clear();
      _resetFees();
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('class', isEqualTo: className)
          .get();

      final List<Map<String, dynamic>> students = [];
      for (final doc in snap.docs) {
        final data = doc.data();
        final role = (data['role'] ?? '').toString().trim().toLowerCase();
        if (role == 'student') {
          students.add({
            'id': doc.id,
            'name': (data['name'] ?? data['student_name'] ?? 'Unknown')
                .toString(),
            'roll_no': (data['roll_no'] ?? data['rollNo'] ?? '').toString(),
          });
        }
      }

      if (students.isEmpty) {
        final profileSnap = await FirebaseFirestore.instance
            .collection('student_profile')
            .where('grade', isEqualTo: className)
            .get();

        for (final doc in profileSnap.docs) {
          final data = doc.data();
          students.add({
            'id': doc.id,
            'name': (data['student_name'] ?? data['name'] ?? 'Unknown')
                .toString(),
            'roll_no': (data['roll_no'] ?? '').toString(),
          });
        }
      }

      if (mounted) {
        setState(() {
          _classStudents = students;
          _isLoadingStudents = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching students: $e');
      if (mounted) {
        setState(() => _isLoadingStudents = false);
        _showSnack('Could not load students for this class. Please try again.');
      }
    }
  }

  // ─── Load Specific Student Details ────────────────────────────────────────
  Future<void> _onStudentSelected(String? studentId) async {
    if (studentId == null || studentId.isEmpty) return;

    final basicInfo = _classStudents.firstWhere(
      (s) => s['id'] == studentId,
      orElse: () => <String, dynamic>{},
    );

    if (basicInfo.isEmpty) {
      _showSnack('Selected student is no longer in this class list.');
      return;
    }

    final rollNo = (basicInfo['roll_no'] ?? '').toString();
    final basicName = (basicInfo['name'] ?? '').toString();

    setState(() {
      _selectedStudentId = studentId;
      _studentDocId = studentId;
      _rollNoController.text = rollNo;
      _studentNameController.text = basicName;
      _fatherNameController.clear();
      _classSectionController.text = _selectedClass ?? '';
      _isLoading = true;
      _isStudentLoaded = false;
      _challanNo = '';
      _resetFees();
    });

    try {
      if (rollNo.isEmpty) {
        _enterManualMode();
        return;
      }

      final query = await FirebaseFirestore.instance
          .collection('student_profile')
          .where('roll_no', isEqualTo: rollNo)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        _enterManualMode();
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();

      final studentName = (data['student_name'] ?? data['name'] ?? basicName)
          .toString();
      final fatherName = (data['father_name'] ?? '').toString();
      final grade = (data['grade'] ?? _selectedClass ?? '').toString();
      final section = (data['section'] ?? '').toString();

      final feesRaw = data['fees'];
      final fees = feesRaw is Map
          ? Map<String, dynamic>.from(feesRaw)
          : <String, dynamic>{};

      final schoolFee = _toDouble(fees['school_fee']);
      final acCharges = _toDouble(fees['ac_charges']);
      final stationaryFee = _toDouble(fees['stationary_fee']);

      final challanNo =
          await _generateChallanNo(rollNo, grade) ?? _fallbackChallanNo(rollNo);

      if (!mounted) return;

      setState(() {
        _studentDocId = doc.id;
        _studentNameController.text = studentName;
        _fatherNameController.text = fatherName;
        _classSectionController.text = section.isEmpty
            ? grade
            : '$grade - $section';
        _schoolFee = schoolFee;
        _acCharges = acCharges;
        _stationaryFee = stationaryFee;
        _manualFeeEntry = false;
        _challanNo = challanNo;
        _isStudentLoaded = true;
      });

      _showSnack('Student loaded. Challan No: $_challanNo');
    } catch (e) {
      debugPrint('Error fetching student profile: $e');
      if (mounted) {
        _enterManualMode(
          message:
              'Could not reach student profile records. Please enter details manually or check records.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetFees() {
    _schoolFee = 0;
    _acCharges = 0;
    _stationaryFee = 0;
    _manualFeeEntry = false;
    _schoolFeeController.clear();
    _acChargesController.clear();
    _stationaryFeeController.clear();
  }

  void _enterManualMode({String? message}) {
    final rollNo = _rollNoController.text.trim();
    setState(() {
      _challanNo = _fallbackChallanNo(rollNo.isEmpty ? 'NA' : rollNo);
      _isStudentLoaded = true;
      _manualFeeEntry = true;
      _schoolFee = 0;
      _acCharges = 0;
      _stationaryFee = 0;
      _schoolFeeController.text = '0';
      _acChargesController.text = '0';
      _stationaryFeeController.text = '0';
    });
    _showSnack(
      message ??
          'Student detailed profile not found in backend. Please enter fees manually below.',
    );
  }

  String _fallbackChallanNo(String rollNo) {
    final suffix = DateTime.now().millisecondsSinceEpoch % 10000;
    return 'CH-${DateTime.now().year}-$rollNo-M$suffix';
  }

  Future<void> _loadSchoolSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('school_info')
          .get();
      if (doc.exists && mounted) {
        final data = doc.data() ?? {};
        setState(() {
          _schoolName = (data['school_name'] ?? 'Your School Name').toString();
          _schoolAddress = (data['address'] ?? 'School Address').toString();
          _schoolPhone = (data['phone'] ?? '000-0000000').toString();
          _kuickpayId = (data['kuickpay_id'] ?? '0000000000000').toString();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _schoolName = 'Your School Name';
          _schoolAddress = 'School Address';
          _schoolPhone = '000-0000000';
          _kuickpayId = '0000000000000';
        });
      }
    }
  }

  double get _totalAmount => _schoolFee + _acCharges + _stationaryFee;
  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _generateChallanNo(String rollNo, String grade) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('student_profile')
          .where('grade', isEqualTo: grade)
          .orderBy('roll_no')
          .get();

      int index = -1;
      for (int i = 0; i < snap.docs.length; i++) {
        final studentRoll = snap.docs[i].data()['roll_no']?.toString() ?? '';
        if (studentRoll == rollNo) {
          index = i;
          break;
        }
      }

      if (index == -1) return null;
      return 'CH-${DateTime.now().year}-$rollNo-${index + 1}';
    } catch (e) {
      debugPrint('Challan number generation error: $e');
      return null;
    }
  }

  Future<void> _pickDate(String type) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: type == 'issue'
          ? _issueDate
          : type == 'due'
          ? _dueDate
          : _validTill,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1E3A5F),
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

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}-${_monthAbbr(date.month)}-${date.year}';
  }

  String _monthAbbr(int m) {
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
    return abbr[m - 1];
  }

  Future<void> _generateChallan() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isStudentLoaded || _challanNo.isEmpty || _selectedStudentId == null) {
      _showSnack('Please select a class and student first.');
      return;
    }

    setState(() => _isGenerating = true);

    try {
      final totalAmount = _schoolFee + _acCharges + _stationaryFee;

      final challanData = ChallanData(
        challanNo: _challanNo,
        schoolName: _schoolName,
        schoolAddress: _schoolAddress,
        schoolPhone: _schoolPhone,
        kuickpayId: _kuickpayId,
        rollNo: _rollNoController.text.trim(),
        studentName: _studentNameController.text.trim(),
        fatherName: _fatherNameController.text.trim(),
        classSection: _classSectionController.text.trim(),
        month: _selectedMonth,
        issueDate: _formatDate(_issueDate),
        dueDate: _formatDate(_dueDate),
        validTill: _formatDate(_validTill),
        feeParticulars: [
          FeeParticular(name: 'School Fee', amount: _schoolFee),
          FeeParticular(name: 'AC Charges', amount: _acCharges),
          FeeParticular(name: 'Stationary Fee', amount: _stationaryFee),
        ].where((f) => f.amount > 0).toList(),
      );

      // 1. PDF generate kar ke Cloudinary par bhej dein
      String? pdfUrl = await ChallanPdfService.generateAndUploadToCloudinary(
        challanData,
        'dkjsza6pw', // Apna Cloudinary cloud name yahan dein
        'challans-pdf', // Apna upload preset yahan dein
      );

      if (pdfUrl == null || pdfUrl.isEmpty) {
        _showSnack('Failed to upload PDF challan.');
        return;
      }

      // 2. Firestore mein save karein (challanRef ko yahan bahar declare kiya hai)
      DocumentReference challanRef = await FirebaseFirestore.instance
          .collection('challans')
          .add({
            "challanNo": _challanNo,
            "studentId": _selectedStudentId,
            "studentName": _studentNameController.text.trim(),
            "rollNo": _rollNoController.text.trim(),
            "classSection": _classSectionController.text.trim(),
            "month": _selectedMonth,
            "totalAmount": totalAmount,
            "dueDate": _formatDate(_dueDate),
            "pdfUrl": pdfUrl,
            "status": "Unpaid",
            "createdAt": FieldValue.serverTimestamp(),
          });

      // 3. Send Push Notification to the Student (Ab yahan `challanRef` easily mil jaye ga)
      try {
        await NotificationService.sendPushToUser(
          targetUserId: _selectedStudentId,
          title: 'Fee Challan Generated 📄',
          body:
              'Your fee challan for $_selectedMonth has been generated. Total: Rs. ${totalAmount.toStringAsFixed(0)}. Due Date: ${_formatDate(_dueDate)}',
          notificationType: 'fee_challan',
          relatedId: challanRef.id,
        );
      } catch (notificationError) {
        debugPrint('NOTIFICATION ERROR: $notificationError');
      }

      _showSnack('Challan uploaded & sent successfully!');
    } catch (e) {
      if (mounted) _showSnack('Error: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _previewChallan() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isStudentLoaded || _challanNo.isEmpty) {
      _showSnack('Please select a class and student first.');
      return;
    }

    try {
      final challanData = ChallanData(
        challanNo: _challanNo,
        schoolName: _schoolName,
        schoolAddress: _schoolAddress,
        schoolPhone: _schoolPhone,
        kuickpayId: _kuickpayId,
        rollNo: _rollNoController.text.trim(),
        studentName: _studentNameController.text.trim(),
        fatherName: _fatherNameController.text.trim(),
        classSection: _classSectionController.text.trim(),
        month: _selectedMonth,
        issueDate: _formatDate(_issueDate),
        dueDate: _formatDate(_dueDate),
        validTill: _formatDate(_validTill),
        feeParticulars: [
          FeeParticular(name: 'School Fee', amount: _schoolFee),
          FeeParticular(name: 'AC Charges', amount: _acCharges),
          FeeParticular(name: 'Stationary Fee', amount: _stationaryFee),
        ].where((f) => f.amount > 0).toList(),
      );

      final pdfBytes = await ChallanPdfService.generatePdf(challanData);
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChallanPreviewScreen(pdfBytes: pdfBytes),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  void dispose() {
    _rollNoController.dispose();
    _studentNameController.dispose();
    _fatherNameController.dispose();
    _classSectionController.dispose();
    _schoolFeeController.dispose();
    _acChargesController.dispose();
    _stationaryFeeController.dispose();
    super.dispose();
  }

  static const _primaryColor = Color(0xFF1E3A5F);
  static const _accentColor = Color(0xFF2E86AB);
  static const _bgColor = Color(0xFFF5F7FA);
  static const _cardColor = Colors.white;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        title: const Text(
          'Generate Fee Challan',
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        elevation: 0,
        // "Generate PDF" button removed from here — the "Generate & Share
        // Challan PDF" button under Preview Challan (below) is the single
        // place that triggers generation now.
      ),
      body: Form(
        key: _formKey,
        child: isWide ? _wideLayout() : _mobileLayout(),
      ),
    );
  }

  Widget _wideLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              children: [
                _studentInfoCard(),
                const SizedBox(height: 16),
                _feeParticularsCard(),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            flex: 3,
            child: Column(
              children: [
                _datesCard(),
                const SizedBox(height: 16),
                _summaryCard(),
                const SizedBox(height: 16),
                _generateButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileLayout() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _studentInfoCard(),
          const SizedBox(height: 16),
          _datesCard(),
          const SizedBox(height: 16),
          _feeParticularsCard(),
          const SizedBox(height: 16),
          _summaryCard(),
          const SizedBox(height: 20),
          _generateButton(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Student Info Card ──────────────────────────────────────────────────

  Widget _studentInfoCard() {
    return _buildCard(
      title: 'Student Information',
      icon: Icons.person_outline,
      child: Column(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Class *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 6),
              _isLoadingClasses
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<String>(
                      value: _dropdownSafeClass,
                      decoration: _inputDecoration(
                        _availableClasses.isEmpty
                            ? 'No classes found yet'
                            : 'Choose a class',
                      ),
                      items: _availableClasses
                          .map(
                            (cls) =>
                                DropdownMenuItem(value: cls, child: Text(cls)),
                          )
                          .toList(),
                      onChanged: _availableClasses.isEmpty
                          ? null
                          : (val) {
                              if (val != null) {
                                setState(() => _selectedClass = val);
                                _fetchStudentsForClass(val);
                              }
                            },
                      validator: (v) => v == null ? 'Required' : null,
                    ),
            ],
          ),
          const SizedBox(height: 12),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select Student *',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
              const SizedBox(height: 6),
              _isLoadingStudents
                  ? const LinearProgressIndicator()
                  : DropdownButtonFormField<String>(
                      value: _dropdownSafeStudentId,
                      decoration: _inputDecoration(
                        _selectedClass == null
                            ? 'First select a class'
                            : _classStudents.isEmpty
                            ? 'No students found in this class'
                            : 'Choose a student',
                      ),
                      items: _classStudents
                          .map(
                            (student) => DropdownMenuItem<String>(
                              value: student['id'] as String,
                              child: Text(
                                (student['roll_no'] as String).isNotEmpty
                                    ? '${student['name']} (Roll: ${student['roll_no']})'
                                    : '${student['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: _classStudents.isEmpty
                          ? null
                          : _onStudentSelected,
                      validator: (v) => v == null ? 'Required' : null,
                    ),
            ],
          ),
          const SizedBox(height: 12),

          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Center(child: CircularProgressIndicator()),
            ),

          _buildField(
            label: "Student's Name *",
            controller: _studentNameController,
            hint: 'Full name',
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _buildField(
            label: "Father's Name *",
            controller: _fatherNameController,
            hint: "Father's full name",
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _buildField(
            label: 'Class/Section *',
            controller: _classSectionController,
            hint: 'e.g. Grade 2 (T)',
            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          _buildDropdown(),
        ],
      ),
    );
  }

  Widget _buildDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Month *',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: _monthOptions.contains(_selectedMonth) ? _selectedMonth : null,
          decoration: _inputDecoration('Select month'),
          items: _monthOptions
              .map((m) => DropdownMenuItem(value: m, child: Text(m)))
              .toList(),
          onChanged: (val) {
            if (val != null) setState(() => _selectedMonth = val);
          },
          validator: (v) => v == null ? 'Required' : null,
        ),
      ],
    );
  }

  // ─── Dates Card ────────────────────────────────────────────────────────────
  Widget _datesCard() {
    return _buildCard(
      title: 'Challan Dates',
      icon: Icons.calendar_today_outlined,
      child: Column(
        children: [
          _dateTile('Issue Date', _formatDate(_issueDate), 'issue'),
          const SizedBox(height: 10),
          _dateTile('Due Date', _formatDate(_dueDate), 'due'),
          const SizedBox(height: 10),
          _dateTile('Valid Till', _formatDate(_validTill), 'valid'),
        ],
      ),
    );
  }

  Widget _dateTile(String label, String value, String type) {
    return InkWell(
      onTap: () => _pickDate(type),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD1D5DB)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today,
              size: 16,
              color: Color(0xFF6B7280),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF9CA3AF)),
          ],
        ),
      ),
    );
  }

  // ─── Fee Particulars Card ──────────────────────────────────────────────────
  Widget _feeParticularsCard() {
    return _buildCard(
      title: 'Fee Particulars',
      icon: Icons.receipt_long_outlined,
      child: Column(
        children: [
          if (_manualFeeEntry) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF5C86A)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.edit_note, color: Color(0xFF92600A), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No backend fee record found for this student — enter fees manually below.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF92600A),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            _editableFeeField('School Fee', _schoolFeeController, (v) {
              setState(() => _schoolFee = double.tryParse(v) ?? 0);
            }),
            const SizedBox(height: 12),
            _editableFeeField('AC Charges', _acChargesController, (v) {
              setState(() => _acCharges = double.tryParse(v) ?? 0);
            }),
            const SizedBox(height: 12),
            _editableFeeField('Stationary Fee', _stationaryFeeController, (v) {
              setState(() => _stationaryFee = double.tryParse(v) ?? 0);
            }),
          ] else ...[
            _feeDisplayRow('School Fee', _schoolFee),
            const Divider(height: 1),
            _feeDisplayRow('AC Charges', _acCharges),
            const Divider(height: 1),
            _feeDisplayRow('Stationary Fee', _stationaryFee),
            const Divider(height: 1),
          ],
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFD0F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline,
                  color: Color(0xFF1E3A5F),
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _manualFeeEntry
                        ? 'These fees were entered manually and will be used for this challan.'
                        : 'Fee is automatically fetched from the student record based on selection.',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF1E3A5F),
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

  Widget _editableFeeField(
    String label,
    TextEditingController controller,
    void Function(String) onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: onChanged,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
          decoration: _inputDecoration('0').copyWith(prefixText: 'Rs. '),
        ),
      ],
    );
  }

  Widget _feeDisplayRow(String name, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              name,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
          ),
          Text(
            'Rs. ${amount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1E3A5F),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Summary Card ──────────────────────────────────────────────────────────
  Widget _summaryCard() {
    return Container(
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.summarize_outlined, color: Colors.white70, size: 18),
              SizedBox(width: 8),
              Text(
                'Total Amount',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Rs. ${_totalAmount.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
          ),
          const Divider(color: Colors.white24, height: 20),
          ...(_buildSummaryRows()),
        ],
      ),
    );
  }

  List<Widget> _buildSummaryRows() {
    return [
      if (_schoolFee > 0) _summaryRow('School Fee', _schoolFee),
      if (_acCharges > 0) _summaryRow('AC Charges', _acCharges),
      if (_stationaryFee > 0) _summaryRow('Stationary Fee', _stationaryFee),
    ];
  }

  Widget _summaryRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            'Rs. ${amount.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Generate Button ───────────────────────────────────────────────────────
  Widget _generateButton() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed: _previewChallan,
            icon: const Icon(Icons.visibility, size: 20),
            label: const Text(
              'Preview Challan',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF1E3A5F),
              side: const BorderSide(color: Color(0xFF1E3A5F), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _isGenerating ? null : _generateChallan,
            icon: _isGenerating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf, size: 20),
            label: Text(
              _isGenerating ? 'Generating...' : 'Generate & Share Challan PDF',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF28A745),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              elevation: 2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: _cardColor,
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF0F4FF),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: _primaryColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _primaryColor,
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

  Widget _buildField({
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label.isNotEmpty) ...[
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF374151),
            ),
          ),
          const SizedBox(height: 6),
        ],
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          validator: validator,
          style: const TextStyle(fontSize: 14, color: Color(0xFF1F2937)),
          decoration: _inputDecoration(hint ?? ''),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFADB5BD), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
        borderSide: const BorderSide(color: _accentColor, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.white,
    );
  }
}
