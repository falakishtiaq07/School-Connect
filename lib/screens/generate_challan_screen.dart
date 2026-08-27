import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:school_connect/screens/challan_preview_screen.dart';
import 'pdf_service_screen.dart';

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
  double _transportFee = 0;
  bool _isStudentLoaded = false;
  String _studentDocId = '';
  // Fee Particulars

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
  }

  Future<void> _loadSchoolSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('school_info')
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _schoolName = doc['school_name'] ?? 'Your School Name';
          _schoolAddress = doc['address'] ?? 'School Address';
          _schoolPhone = doc['phone'] ?? '000-0000000';
          _kuickpayId = doc['kuickpay_id'] ?? '0000000000000';
        });
      }
    } catch (_) {
      // Use defaults if settings not found
      setState(() {
        _schoolName = 'Your School Name';
        _schoolAddress = 'School Address';
        _schoolPhone = '000-0000000';
        _kuickpayId = '0000000000000';
      });
    }
  }

  double get _totalAmount {
    return _schoolFee + _transportFee;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString()) ?? 0;
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

      if (index == -1) {
        return null;
      }

      // EXACT SAME LOGIC AS BULK SCREEN
      return 'CH-${DateTime.now().year}-${rollNo}-${index + 1}';
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
    return '${date.day.toString().padLeft(2, '0')}-'
        '${_monthAbbr(date.month)}-${date.year}';
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

  Future<void> _searchStudent() async {
    final rollNo = _rollNoController.text.trim();

    if (rollNo.isEmpty) {
      _showSnack('Please enter Admission No.');
      return;
    }

    setState(() {
      _isLoading = true;
      _isStudentLoaded = false;
      _challanNo = '';
      _schoolFee = 0;
      _transportFee = 0;
    });

    try {
      final query = await FirebaseFirestore.instance
          .collection('student_profile')
          .where('roll_no', isEqualTo: rollNo)
          .limit(1)
          .get();

      if (query.docs.isEmpty) {
        if (mounted) {
          _showSnack('Student not found with this admission number.');
        }
        return;
      }

      final doc = query.docs.first;
      final data = doc.data();

      final studentName =
          data['student_name']?.toString() ?? data['name']?.toString() ?? '';

      final fatherName = data['father_name']?.toString() ?? '';
      final grade = data['grade']?.toString() ?? '';
      final section = data['section']?.toString() ?? '';

      // ── SAME FEES STRUCTURE AS BULK SCREEN ──
      final feesRaw = data['fees'];

      final fees = feesRaw is Map
          ? Map<String, dynamic>.from(feesRaw)
          : <String, dynamic>{};

      final schoolFee = _toDouble(fees['school_fee']);
      final transportFee = _toDouble(fees['transport_fee']);

      // ── SAME CHALLAN NUMBER LOGIC AS BULK ──
      final challanNo = await _generateChallanNo(rollNo, grade);

      if (challanNo == null) {
        if (mounted) {
          _showSnack('Unable to generate challan number for this student.');
        }
        return;
      }

      if (!mounted) return;

      setState(() {
        _studentDocId = doc.id;

        _studentNameController.text = studentName;
        _fatherNameController.text = fatherName;
        _classSectionController.text = section.isEmpty
            ? grade
            : '$grade - $section';

        _schoolFee = schoolFee;
        _transportFee = transportFee;

        _challanNo = challanNo;

        _isStudentLoaded = true;
      });

      _showSnack('Student loaded. Challan No: $_challanNo');
    } catch (e) {
      if (mounted) {
        _showSnack('Error fetching student: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _generateChallan() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isStudentLoaded || _challanNo.isEmpty) {
      _showSnack('Please search and load a student first.');
      return;
    }

    setState(() => _isGenerating = true);

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

        // EXACTLY LIKE BULK
        feeParticulars: [
          FeeParticular(name: 'School Fee', amount: _schoolFee),
          FeeParticular(name: 'Transport Fee', amount: _transportFee),
        ].where((f) => f.amount > 0).toList(),
      );

      await ChallanPdfService.generateAndShare(challanData);
    } catch (e) {
      if (mounted) {
        _showSnack('Error generating challan: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _previewChallan() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isStudentLoaded || _challanNo.isEmpty) {
      _showSnack('Please search and load a student first.');
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

        // SAME AS BULK
        feeParticulars: [
          FeeParticular(name: 'School Fee', amount: _schoolFee),
          FeeParticular(name: 'Transport Fee', amount: _transportFee),
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

    super.dispose();
  }

  // ─── UI ────────────────────────────────────────────────────────────────────

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
        actions: [
          if (_isGenerating)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: ElevatedButton.icon(
                onPressed: _generateChallan,
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Generate PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF28A745),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
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

  // ─── Student Info Card ─────────────────────────────────────────────────────

  Widget _studentInfoCard() {
    return _buildCard(
      title: 'Student Information',
      icon: Icons.person_outline,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildField(
                  label: 'Admission No *',
                  controller: _rollNoController,
                  hint: 'e.g. 1461',
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _searchStudent,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Search'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          value: _selectedMonth,
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
          _feeDisplayRow('School Fee', _schoolFee),
          const Divider(height: 1),

          _feeDisplayRow('Transport Fee', _transportFee),

          const Divider(height: 1),

          const SizedBox(height: 8),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFBFD0F0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF1E3A5F), size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fee is automatically fetched from the student record, same as Bulk Challan.',
                    style: TextStyle(
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

      if (_transportFee > 0) _summaryRow('Transport Fee', _transportFee),
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
        // 1. Preview Button
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton.icon(
            onPressed:
                _previewChallan, // Ye wahi function hai jo humne banaya tha
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

        // 2. Generate & Share Button
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

  // ─── Helpers ───────────────────────────────────────────────────────────────

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
    void Function(String)? onChanged,
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
          onChanged: onChanged,
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
