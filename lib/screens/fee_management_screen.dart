import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as excelLib;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

class BulkImportStudentsScreen extends StatefulWidget {
  const BulkImportStudentsScreen({super.key});

  @override
  State<BulkImportStudentsScreen> createState() =>
      _BulkImportStudentsScreenState();
}

class _BulkImportStudentsScreenState extends State<BulkImportStudentsScreen> {
  static const _navy = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF2E86AB);
  static const _green = Color(0xFF28A745);
  static const _orange = Color(0xFFFFA500);
  static const _red = Color(0xFFDC3545);

  final _rollNoCtrl = TextEditingController();
  final _studentNameCtrl = TextEditingController();
  final _fatherNameCtrl = TextEditingController();
  final _schoolFeeCtrl = TextEditingController(text: '0');
  final _acChargesCtrl = TextEditingController(text: '0');
  final _stationaryFeeCtrl = TextEditingController(text: '0');
  final _searchCtrl = TextEditingController();

  String? _selectedClass;
  String? _selectedStudentId;
  List<String> _classes = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _classStudents = [];

  bool _isLoadingClasses = false;
  bool _isLoadingStudents = false;
  bool _isSaving = false;
  bool _manualEntry = true;

  List<QueryDocumentSnapshot<Map<String, dynamic>>> _allDocs = [];
  DocumentSnapshot<Map<String, dynamic>>? _lastDoc;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  String _searchQuery = '';
  Timer? _debounce;

  // Bulk import state.
  List<Map<String, String>> _parsedRows = [];
  List<String> _errorRows = [];
  bool _isPicking = false;
  bool _isImporting = false;
  int _importProgress = 0;
  int _importTotal = 0;
  int _importedCount = 0;
  int _skippedCount = 0;
  String? _fileName;

  static const _requiredColumns = [
    'roll_no',
    'student_name',
    'father_name',
    'class',
    'school_fee',
    'ac_charges',
    'stationary_fee',
  ];

  @override
  void initState() {
    super.initState();
    _loadClasses();
    _loadFirstPage();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _rollNoCtrl.dispose();
    _studentNameCtrl.dispose();
    _fatherNameCtrl.dispose();
    _schoolFeeCtrl.dispose();
    _acChargesCtrl.dispose();
    _stationaryFeeCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // CLASS + STUDENT FETCH
  // ---------------------------------------------------------------------------

  Future<void> _loadClasses() async {
    if (mounted) setState(() => _isLoadingClasses = true);

    final names = <String>{};

    try {
      // Preferred source: classes collection.
      final classSnap = await FirebaseFirestore.instance
          .collection('classes')
          .get();

      for (final doc in classSnap.docs) {
        final data = doc.data();
        final value =
            (data['name'] ??
                    data['className'] ??
                    data['class_name'] ??
                    data['title'] ??
                    data['class'] ??
                    '')
                .toString()
                .trim();

        if (value.isNotEmpty) names.add(value);
      }
    } catch (_) {
      // If classes collection is unavailable, student users below are used.
    }

    try {
      // Fallback/additional source: distinct classes from Student accounts.
      final studentSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'Student')
          .get();

      for (final doc in studentSnap.docs) {
        final value = (doc.data()['class'] ?? '').toString().trim();
        if (value.isNotEmpty) names.add(value);
      }
    } catch (e) {
      if (names.isEmpty) {
        _showSnack('Failed to load classes: $e', isError: true);
      }
    }

    final sorted = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (!mounted) return;

    setState(() {
      _classes = sorted;
      _isLoadingClasses = false;
    });
  }

  Future<void> _loadStudentsForClass(String className) async {
    setState(() {
      _selectedStudentId = null;
      _classStudents = [];
      _isLoadingStudents = true;
    });

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'Student')
          .where('class', isEqualTo: className)
          .get();

      final students = snap.docs.toList()
        ..sort((a, b) {
          final an = (a.data()['name'] ?? '').toString().toLowerCase();
          final bn = (b.data()['name'] ?? '').toString().toLowerCase();
          return an.compareTo(bn);
        });

      if (!mounted) return;

      setState(() {
        _classStudents = students;
        _isLoadingStudents = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingStudents = false);
      _showSnack('Failed to load students: $e', isError: true);
    }
  }

  void _onClassChanged(String? value) {
    if (value == null) return;

    setState(() {
      _selectedClass = value;
      _manualEntry = true;
      _selectedStudentId = null;
      _classStudents = [];
      _clearStudentFields();
    });

    _loadStudentsForClass(value);
  }

  void _onStudentChanged(String? value) {
    if (value == null) return;

    if (value == '__manual__') {
      setState(() {
        _manualEntry = true;
        _selectedStudentId = null;
      });
      _clearStudentFields();
      return;
    }

    final student = _classStudents.where((d) => d.id == value).firstOrNull;
    if (student == null) return;

    final data = student.data();

    setState(() {
      _manualEntry = false;
      _selectedStudentId = student.id;
    });

    _studentNameCtrl.text = (data['name'] ?? '').toString();
    _rollNoCtrl.text = (data['rollNo'] ?? data['roll_no'] ?? '').toString();
    _fatherNameCtrl.text = (data['fatherName'] ?? data['father_name'] ?? '')
        .toString();
  }

  void _clearStudentFields() {
    _rollNoCtrl.clear();
    _studentNameCtrl.clear();
    _fatherNameCtrl.clear();
  }

  // ---------------------------------------------------------------------------
  // MANUAL SAVE
  // ---------------------------------------------------------------------------

  Future<void> _saveSingleStudent() async {
    final rollNo = _rollNoCtrl.text.trim();
    final studentName = _studentNameCtrl.text.trim();
    final fatherName = _fatherNameCtrl.text.trim();
    final className = _selectedClass;

    if (className == null || className.isEmpty) {
      _showSnack('Please select a class.', isError: true);
      return;
    }

    if (rollNo.isEmpty || studentName.isEmpty || fatherName.isEmpty) {
      _showSnack(
        'Roll No, Student Name and Father Name are required.',
        isError: true,
      );
      return;
    }

    final schoolFee = _number(_schoolFeeCtrl.text);
    final acCharges = _number(_acChargesCtrl.text);
    final stationaryFee = _number(_stationaryFeeCtrl.text);
    final totalFee = schoolFee + acCharges + stationaryFee;

    setState(() => _isSaving = true);

    try {
      final ref = FirebaseFirestore.instance.collection('student_profile');

      // Roll number is treated as the unique profile key.
      final duplicate = await ref
          .where('roll_no', isEqualTo: rollNo)
          .limit(1)
          .get();

      if (duplicate.docs.isNotEmpty) {
        if (mounted) {
          setState(() => _isSaving = false);
          _showSnack(
            'A student profile with Roll No $rollNo already exists.',
            isError: true,
          );
        }
        return;
      }

      await ref.add({
        'roll_no': rollNo,
        'student_name': studentName,
        'father_name': fatherName,
        'class': className,
        'grade': className,
        'student_id': _selectedStudentId,
        'created_at': FieldValue.serverTimestamp(),
        'fees': {
          'school_fee': schoolFee,
          'ac_charges': acCharges,
          'stationary_fee': stationaryFee,
          'total_fee': totalFee,
        },
      });

      if (!mounted) return;

      _showSnack('Student profile saved successfully.');
      _clearForm();
      _resetPagination();
      await _loadFirstPage();
    } catch (e) {
      if (mounted) {
        _showSnack('Failed to save student: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  double _number(String value) {
    return double.tryParse(value.trim().replaceAll(',', '')) ?? 0;
  }

  void _clearForm() {
    setState(() {
      _selectedStudentId = null;
      _manualEntry = true;
    });

    _rollNoCtrl.clear();
    _studentNameCtrl.clear();
    _fatherNameCtrl.clear();
    _schoolFeeCtrl.text = '0';
    _acChargesCtrl.text = '0';
    _stationaryFeeCtrl.text = '0';
  }

  // ---------------------------------------------------------------------------
  // BULK IMPORT
  // ---------------------------------------------------------------------------

  Future<void> _pickFile() async {
    setState(() {
      _isPicking = true;
      _parsedRows = [];
      _errorRows = [];
      _fileName = null;
    });

    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) setState(() => _isPicking = false);
        return;
      }

      final file = result.files.first;

      if (file.bytes == null) {
        throw Exception('Unable to read the selected Excel file.');
      }

      if (mounted) setState(() => _fileName = file.name);

      final bytes = Uint8List.fromList(file.bytes!);
      await Future.delayed(Duration.zero);
      _parseExcel(bytes);
    } catch (e) {
      if (mounted) {
        setState(() => _isPicking = false);
        _showSnack('Error picking file: $e', isError: true);
      }
    }
  }

  void _parseExcel(Uint8List bytes) {
    try {
      final excel = excelLib.Excel.decodeBytes(bytes);

      if (excel.tables.isEmpty) {
        throw Exception('Excel file does not contain a sheet.');
      }

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName];

      if (sheet == null || sheet.rows.isEmpty) {
        _showSnack('Excel sheet is empty.', isError: true);
        if (mounted) setState(() => _isPicking = false);
        return;
      }

      final headers = sheet.rows.first
          .map((c) => c?.value?.toString().trim().toLowerCase() ?? '')
          .toList();

      for (final col in _requiredColumns) {
        if (!headers.contains(col)) {
          _showSnack('Missing column: "$col"', isError: true);
          if (mounted) setState(() => _isPicking = false);
          return;
        }
      }

      final rows = <Map<String, String>>[];
      final errors = <String>[];

      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];

        if (row.every(
          (c) => c == null || (c.value?.toString().trim() ?? '').isEmpty,
        )) {
          continue;
        }

        final map = <String, String>{};

        for (int j = 0; j < headers.length && j < row.length; j++) {
          if (headers[j].isNotEmpty) {
            map[headers[j]] = row[j]?.value?.toString().trim() ?? '';
          }
        }

        if ((map['roll_no'] ?? '').isEmpty ||
            (map['student_name'] ?? '').isEmpty ||
            (map['class'] ?? '').isEmpty) {
          errors.add('Row ${i + 1}: roll_no, student_name or class is empty');
          continue;
        }

        rows.add(map);
      }

      if (mounted) {
        setState(() {
          _parsedRows = rows;
          _errorRows = errors;
          _isPicking = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isPicking = false);
        _showSnack('Parse error: $e', isError: true);
      }
    }
  }

  Future<void> _importToFirestore() async {
    if (_parsedRows.isEmpty || _isImporting) return;

    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importTotal = _parsedRows.length;
      _importedCount = 0;
      _skippedCount = 0;
    });

    final fs = FirebaseFirestore.instance;
    final ref = fs.collection('student_profile');

    try {
      final existingSnap = await ref.get();

      final existingRollNos = existingSnap.docs
          .map((d) => (d.data()['roll_no'] ?? '').toString().trim())
          .where((v) => v.isNotEmpty)
          .toSet();

      const batchSize = 499;
      int imported = 0;
      int skipped = 0;

      for (int i = 0; i < _parsedRows.length; i += batchSize) {
        final end = (i + batchSize < _parsedRows.length)
            ? i + batchSize
            : _parsedRows.length;

        final chunk = _parsedRows.sublist(i, end);
        final batch = fs.batch();

        for (int ci = 0; ci < chunk.length; ci++) {
          final row = chunk[ci];
          final rollNo = (row['roll_no'] ?? '').trim();

          if (rollNo.isEmpty || existingRollNos.contains(rollNo)) {
            skipped++;
          } else {
            final schoolFee = _number(row['school_fee'] ?? '0');
            final acCharges = _number(row['ac_charges'] ?? '0');
            final stationaryFee = _number(row['stationary_fee'] ?? '0');
            final totalFee = schoolFee + acCharges + stationaryFee;

            final className = (row['class'] ?? '').trim();

            batch.set(ref.doc(), {
              'roll_no': rollNo,
              'student_name': (row['student_name'] ?? '').trim(),
              'father_name': (row['father_name'] ?? '').trim(),
              'class': className,
              'grade': className,
              'student_id': null,
              'created_at': FieldValue.serverTimestamp(),
              'fees': {
                'school_fee': schoolFee,
                'ac_charges': acCharges,
                'stationary_fee': stationaryFee,
                'total_fee': totalFee,
              },
            });

            existingRollNos.add(rollNo);
            imported++;
          }

          if (mounted) {
            setState(() => _importProgress = i + ci + 1);
          }
        }

        await batch.commit();
      }

      await _loadFirstPage();

      if (mounted) {
        setState(() {
          _isImporting = false;
          _importedCount = imported;
          _skippedCount = skipped;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isImporting = false);
        _showSnack('Import failed: $e', isError: true);
      }
    }
  }

  void _resetImport() {
    setState(() {
      _parsedRows = [];
      _errorRows = [];
      _fileName = null;
      _importProgress = 0;
      _importTotal = 0;
      _importedCount = 0;
      _skippedCount = 0;
    });
  }

  Future<void> _openBulkImportDialog() async {
    _resetImport();

    await showDialog(
      context: context,
      barrierDismissible: !_isImporting,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            // Keep the parent state as the source of truth. This also lets
            // progress update while the dialog is open.
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              titlePadding: EdgeInsets.zero,
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              title: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                decoration: const BoxDecoration(
                  color: _navy,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.upload_file_outlined,
                      color: Colors.white70,
                      size: 19,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Bulk Import Students',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _isImporting
                          ? null
                          : () {
                              _resetImport();
                              Navigator.pop(ctx);
                            },
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              content: SizedBox(
                width: 760,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _bulkDialogContent(ctx),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _bulkDialogContent(BuildContext dialogContext) {
    if (_isImporting) {
      final pct = _importTotal == 0 ? 0.0 : _importProgress / _importTotal;

      return Column(
        children: [
          const SizedBox(height: 12),
          const Icon(Icons.cloud_upload_outlined, size: 48, color: _accent),
          const SizedBox(height: 16),
          const Text(
            'Importing students...',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            '$_importProgress of $_importTotal records',
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 10,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(_accent),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${(pct * 100).toStringAsFixed(0)}%',
            style: const TextStyle(color: _accent, fontWeight: FontWeight.w700),
          ),
        ],
      );
    }

    if (_parsedRows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Upload one .xlsx file containing these columns:',
            style: TextStyle(fontSize: 13, color: Color(0xFF374151)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: _requiredColumns
                .map((e) => _smallChip(e.replaceAll('_', ' '), _accent))
                .toList(),
          ),
          const SizedBox(height: 16),
          const Text(
            'DOB, Security Fee and Transport Fee are not used.',
            style: TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _isPicking ? null : _pickFile,
              icon: _isPicking
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_file, size: 19),
              label: Text(_isPicking ? 'Reading file...' : 'Choose Excel File'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Preview — ${_parsedRows.length} rows',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(onPressed: _resetImport, child: const Text('Clear')),
          ],
        ),
        if (_fileName != null) ...[
          Text(
            _fileName!,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
        ],
        if (_errorRows.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Text(
              '${_errorRows.length} row(s) will be skipped.\n'
              '${_errorRows.take(5).join('\n')}',
              style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Container(
          constraints: const BoxConstraints(maxHeight: 330),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SingleChildScrollView(
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(_navy),
                headingTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                columnSpacing: 18,
                columns: const [
                  DataColumn(label: Text('#')),
                  DataColumn(label: Text('Roll No')),
                  DataColumn(label: Text('Student')),
                  DataColumn(label: Text('Father')),
                  DataColumn(label: Text('Class')),
                  DataColumn(label: Text('School Fee')),
                  DataColumn(label: Text('AC')),
                  DataColumn(label: Text('Stationary')),
                ],
                rows: _parsedRows.asMap().entries.map((entry) {
                  final row = entry.value;

                  return DataRow(
                    cells: [
                      DataCell(Text('${entry.key + 1}')),
                      DataCell(Text(row['roll_no'] ?? '')),
                      DataCell(Text(row['student_name'] ?? '')),
                      DataCell(Text(row['father_name'] ?? '')),
                      DataCell(Text(row['class'] ?? '')),
                      DataCell(Text(row['school_fee'] ?? '0')),
                      DataCell(Text(row['ac_charges'] ?? '0')),
                      DataCell(Text(row['stationary_fee'] ?? '0')),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            onPressed: _importToFirestore,
            icon: const Icon(Icons.cloud_upload_outlined, size: 19),
            label: Text(
              'Import ${_parsedRows.length} Students',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // STUDENT PROFILE LIST
  // ---------------------------------------------------------------------------

  void _onSearchChanged() {
    _debounce?.cancel();

    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _searchQuery = _searchCtrl.text.trim().toLowerCase();
        });
      }
    });
  }

  void _resetPagination() {
    _allDocs = [];
    _lastDoc = null;
    _hasMore = true;
    _isLoadingMore = false;
  }

  Future<void> _loadFirstPage() async {
    if (_isLoadingMore) return;

    _resetPagination();

    if (mounted) setState(() => _isLoadingMore = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('student_profile')
          .orderBy('roll_no')
          .limit(20)
          .get();

      if (!mounted) return;

      setState(() {
        _allDocs = snap.docs;
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : null;
        _hasMore = snap.docs.length == 20;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoadingMore = false);
      _showSnack('Failed to load student profiles: $e', isError: true);
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoadingMore || _lastDoc == null) return;

    setState(() => _isLoadingMore = true);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('student_profile')
          .orderBy('roll_no')
          .startAfterDocument(_lastDoc!)
          .limit(20)
          .get();

      if (!mounted) return;

      setState(() {
        _allDocs = [..._allDocs, ...snap.docs];
        _lastDoc = snap.docs.isNotEmpty ? snap.docs.last : _lastDoc;
        _hasMore = snap.docs.length == 20;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingMore = false);
        _showSnack('Failed to load more students: $e', isError: true);
      }
    }
  }

  List<QueryDocumentSnapshot<Map<String, dynamic>>> get _filteredDocs {
    if (_searchQuery.isEmpty) return _allDocs;

    return _allDocs.where((doc) {
      final d = doc.data();

      final name = (d['student_name'] ?? '').toString().toLowerCase();
      final roll = (d['roll_no'] ?? '').toString().toLowerCase();
      final father = (d['father_name'] ?? '').toString().toLowerCase();
      final className = (d['class'] ?? d['grade'] ?? '')
          .toString()
          .toLowerCase();

      return name.contains(_searchQuery) ||
          roll.contains(_searchQuery) ||
          father.contains(_searchQuery) ||
          className.contains(_searchQuery);
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // EDIT / DELETE
  // ---------------------------------------------------------------------------

  Future<void> _openEditDialog(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final studentClass = (data['class'] ?? data['grade'] ?? '')
        .toString()
        .trim();

    // Safe dialog classes list banana jo master list ko affect na kare
    final dialogClasses = <String>{
      ..._classes.map((e) => e.trim()).where((e) => e.isNotEmpty),
    };

    if (studentClass.isNotEmpty) {
      dialogClasses.add(studentClass);
    }

    final sortedDialogClasses = dialogClasses.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return _EditStudentDialog(
          data: data,
          classes: sortedDialogClasses,
          onSave: (values) async {
            final roll = values['roll_no'] as String;
            final name = values['student_name'] as String;
            final father = values['father_name'] as String;
            final selectedClass = values['class'] as String;

            final newSchool = values['school_fee'] as double;
            final newAc = values['ac_charges'] as double;
            final newStationary = values['stationary_fee'] as double;

            if (selectedClass.trim().isEmpty ||
                roll.trim().isEmpty ||
                name.trim().isEmpty ||
                father.trim().isEmpty) {
              _showSnack(
                'Class, Roll No, Student Name and Father Name are required.',
                isError: true,
              );
              return false;
            }

            try {
              final duplicate = await FirebaseFirestore.instance
                  .collection('student_profile')
                  .where('roll_no', isEqualTo: roll)
                  .get();

              final duplicateOther = duplicate.docs
                  .where((d) => d.id != doc.id)
                  .isNotEmpty;

              if (duplicateOther) {
                _showSnack(
                  'Another profile already uses Roll No $roll.',
                  isError: true,
                );
                return false;
              }

              await doc.reference.update({
                'roll_no': roll,
                'student_name': name,
                'father_name': father,
                'class': selectedClass,
                'grade': selectedClass,
                'fees': {
                  'school_fee': newSchool,
                  'ac_charges': newAc,
                  'stationary_fee': newStationary,
                  'total_fee': newSchool + newAc + newStationary,
                },
                'updated_at': FieldValue.serverTimestamp(),
              });

              return true;
            } catch (e) {
              _showSnack('Update failed: $e', isError: true);
              return false;
            }
          },
          // Yahan onDelete callback add kiya gaya hai taake record delete ho sakay
          onDelete: () async {
            try {
              await doc.reference.delete();
              return true;
            } catch (e) {
              _showSnack('Delete failed: $e', isError: true);
              return false;
            }
          },
        );
      },
    );

    if (result == true && mounted) {
      _showSnack('Operation completed successfully.');
      await _loadFirstPage();
    }
  }

  // -------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width > 850;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Student Profiles',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: _isImporting ? null : _openBulkImportDialog,
              icon: const Icon(Icons.upload_file_outlined, size: 16),
              label: const Text(
                'Import',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withOpacity(0.55)),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadClasses();
          await _loadFirstPage();

          if (_selectedClass != null) {
            await _loadStudentsForClass(_selectedClass!);
          }
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(isWide ? 28 : 16),
          child: Column(
            children: [
              _buildManualEntryCard(isWide),
              const SizedBox(height: 24),
              _buildStudentListSection(isWide),
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildManualEntryCard(bool isWide) {
    return Container(
      width: double.infinity,
      decoration: _cardDecor(),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.person_add_alt_1_outlined,
                  color: Colors.white70,
                  size: 19,
                ),
                const SizedBox(width: 9),
                const Expanded(
                  child: Text(
                    'Add Student Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.all(isWide ? 22 : 16),
            child: Column(
              children: [
                isWide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _classDropdown()),
                          const SizedBox(width: 12),
                          Expanded(child: _studentDropdown()),
                        ],
                      )
                    : Column(
                        children: [
                          _classDropdown(),
                          const SizedBox(height: 12),
                          _studentDropdown(),
                        ],
                      ),
                const SizedBox(height: 12),
                if (isWide)
                  Row(
                    children: [
                      Expanded(child: _textField('Roll No', _rollNoCtrl)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _textField('Student Name', _studentNameCtrl),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _textField('Father Name', _fatherNameCtrl),
                      ),
                    ],
                  )
                else
                  Column(
                    children: [
                      _textField('Roll No', _rollNoCtrl),
                      _textField('Student Name', _studentNameCtrl),
                      _textField('Father Name', _fatherNameCtrl),
                    ],
                  ),
                const SizedBox(height: 4),
                const Divider(height: 24),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Fee Details',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                isWide
                    ? Row(
                        children: [
                          Expanded(
                            child: _textField(
                              'School Fee',
                              _schoolFeeCtrl,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _textField(
                              'AC Charges',
                              _acChargesCtrl,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _textField(
                              'Stationary Fee',
                              _stationaryFeeCtrl,
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _textField(
                            'School Fee',
                            _schoolFeeCtrl,
                            keyboardType: TextInputType.number,
                          ),
                          _textField(
                            'AC Charges',
                            _acChargesCtrl,
                            keyboardType: TextInputType.number,
                          ),
                          _textField(
                            'Stationary Fee',
                            _stationaryFeeCtrl,
                            keyboardType: TextInputType.number,
                          ),
                        ],
                      ),
                const SizedBox(height: 4),
                _totalFeeBox(),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: _isSaving ? null : _clearForm,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: const BorderSide(color: _navy),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveSingleStudent,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(_isSaving ? 'Saving...' : 'Save Student'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
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

  Widget _classDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedClass,
      isExpanded: true,
      decoration: _inputDecoration('Class'),
      hint: Text(_isLoadingClasses ? 'Loading classes...' : 'Select Class'),
      items: _classes
          .map(
            (c) => DropdownMenuItem<String>(
              value: c,
              child: Text(c, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: _isLoadingClasses ? null : _onClassChanged,
    );
  }

  Widget _studentDropdown() {
    final items = <DropdownMenuItem<String>>[
      const DropdownMenuItem<String>(
        value: '__manual__',
        child: Text('Manual Entry'),
      ),
      ..._classStudents.map((doc) {
        final data = doc.data();
        final name = (data['name'] ?? 'Unnamed').toString();
        final roll = (data['rollNo'] ?? data['roll_no'] ?? '').toString();

        return DropdownMenuItem<String>(
          value: doc.id,
          child: Text(
            roll.isEmpty ? name : '$name — Roll #$roll',
            overflow: TextOverflow.ellipsis,
          ),
        );
      }),
    ];

    return DropdownButtonFormField<String>(
      value: _manualEntry ? '__manual__' : _selectedStudentId,
      isExpanded: true,
      decoration: _inputDecoration(
        _selectedClass == null
            ? 'Student'
            : 'Student (${_classStudents.length})',
      ),
      hint: Text(
        _selectedClass == null
            ? 'Select class first'
            : _isLoadingStudents
            ? 'Loading students...'
            : _classStudents.isEmpty
            ? 'No students found in this class'
            : 'Select Student',
      ),
      items: items,
      onChanged: _selectedClass == null || _isLoadingStudents
          ? null
          : _onStudentChanged,
    );
  }

  Widget _textField(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) {
          setState(() {});
        },
        style: const TextStyle(fontSize: 13),
        decoration: _inputDecoration(label),
      ),
    );
  }

  Widget _totalFeeBox() {
    final total =
        _number(_schoolFeeCtrl.text) +
        _number(_acChargesCtrl.text) +
        _number(_stationaryFeeCtrl.text);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _green.withOpacity(0.07),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: _green.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calculate_outlined, color: _green, size: 17),
          const SizedBox(width: 8),
          const Text(
            'Total Fee',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            'Rs. ${_money(total)}',
            style: const TextStyle(
              color: _green,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStudentListSection(bool isWide) {
    final docs = _filteredDocs;

    return Container(
      width: double.infinity,
      decoration: _cardDecor(),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.groups_outlined,
                  color: Colors.white70,
                  size: 20,
                ),
                const SizedBox(width: 9),
                const Text(
                  'Student Profiles',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'Total: ${_allDocs.length}${_hasMore ? '+' : ''}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isLoadingMore ? null : _loadFirstPage,
                  icon: const Icon(
                    Icons.refresh,
                    color: Colors.white,
                    size: 18,
                  ),
                  tooltip: 'Refresh',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(fontSize: 13),
              decoration:
                  _inputDecoration(
                    'Search by name, roll no, father name or class',
                  ).copyWith(
                    prefixIcon: const Icon(
                      Icons.search,
                      color: Color(0xFF9CA3AF),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          )
                        : null,
                  ),
            ),
          ),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          if (_isLoadingMore && _allDocs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator(color: _navy)),
            )
          else if (docs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Text(
                  'No student profiles found.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                ),
              ),
            )
          else if (isWide)
            _desktopTable(docs)
          else
            _mobileList(docs),
          if (_hasMore && _searchQuery.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: OutlinedButton.icon(
                onPressed: _isLoadingMore ? null : _loadMore,
                icon: const Icon(Icons.expand_more, size: 18),
                label: Text(
                  _isLoadingMore
                      ? 'Loading...'
                      : 'Load More (${_allDocs.length})',
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: const BorderSide(color: _navy),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          if (!_hasMore && _allDocs.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'All students loaded',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _desktopTable(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF0F4FF)),
              headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
              dataRowMinHeight: 54,
              dataRowMaxHeight: 54,

              // Screen ke available width ke according table expand hoga
              columnSpacing: 24,

              columns: const [
                DataColumn(label: Text('Roll #')),
                DataColumn(label: Text('Student Name')),
                DataColumn(label: Text('Father Name')),
                DataColumn(label: Text('Class')),
                DataColumn(label: Text('School Fee')),
                DataColumn(label: Text('AC Charges')),
                DataColumn(label: Text('Stationary')),
                DataColumn(label: Text('Total')),
                DataColumn(label: Text('Actions')),
              ],

              rows: docs.map((doc) {
                final d = doc.data();

                final fees = Map<String, dynamic>.from(
                  (d['fees'] as Map?) ?? {},
                );

                final school = _number((fees['school_fee'] ?? 0).toString());

                final ac = _number((fees['ac_charges'] ?? 0).toString());

                final stationary = _number(
                  (fees['stationary_fee'] ?? 0).toString(),
                );

                final total = school + ac + stationary;

                return DataRow(
                  cells: [
                    DataCell(_chip(d['roll_no']?.toString() ?? '—', _accent)),

                    DataCell(
                      Text(
                        d['student_name']?.toString() ?? '—',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),

                    DataCell(
                      Text(
                        d['father_name']?.toString() ?? '—',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),

                    DataCell(
                      Text(
                        (d['class'] ?? d['grade'] ?? '—').toString(),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),

                    DataCell(Text('Rs. ${_money(school)}')),

                    DataCell(Text('Rs. ${_money(ac)}')),

                    DataCell(Text('Rs. ${_money(stationary)}')),

                    DataCell(
                      Text(
                        'Rs. ${_money(total)}',
                        style: const TextStyle(
                          color: _green,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),

                    DataCell(
                      IconButton(
                        onPressed: () => _openEditDialog(doc),
                        icon: const Icon(
                          Icons.edit_outlined,
                          size: 17,
                          color: _navy,
                        ),
                        tooltip: 'Edit',
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }

  Widget _mobileList(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final d = docs[i].data();
        final fees = Map<String, dynamic>.from((d['fees'] as Map?) ?? {});

        final school = _number((fees['school_fee'] ?? 0).toString());
        final ac = _number((fees['ac_charges'] ?? 0).toString());
        final stationary = _number((fees['stationary_fee'] ?? 0).toString());
        final total = school + ac + stationary;

        final name = d['student_name']?.toString() ?? '—';

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 7,
          ),
          leading: CircleAvatar(
            backgroundColor: _navy.withOpacity(0.1),
            child: Text(
              name.isEmpty ? '?' : name[0].toUpperCase(),
              style: const TextStyle(color: _navy, fontWeight: FontWeight.w800),
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 3),
              Text(
                '${d['father_name'] ?? '—'} • '
                'Roll #${d['roll_no'] ?? '—'}',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
              Text(
                '${d['class'] ?? d['grade'] ?? '—'} • '
                'Fee: Rs. ${_money(total)}',
                style: const TextStyle(
                  fontSize: 11,
                  color: _green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          trailing: IconButton(
            onPressed: () => _openEditDialog(docs[i]),
            icon: const Icon(Icons.edit_outlined, size: 17, color: _navy),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // HELPERS
  // ---------------------------------------------------------------------------

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
    );
  }

  Widget _smallChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  String _money(double value) {
    if (value == value.roundToDouble()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(2);
  }

  BoxDecoration _cardDecor() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : _green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _EditStudentDialog extends StatefulWidget {
  final Map<String, dynamic> data;
  final List<String> classes;
  final Future<bool> Function(Map<String, dynamic> values) onSave;
  final Future<bool> Function()? onDelete;

  const _EditStudentDialog({
    required this.data,
    required this.classes,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_EditStudentDialog> createState() => _EditStudentDialogState();
}

class _EditStudentDialogState extends State<_EditStudentDialog> {
  late final TextEditingController cRoll;
  late final TextEditingController cName;
  late final TextEditingController cFather;
  late final TextEditingController cSchool;
  late final TextEditingController cAc;
  late final TextEditingController cStationary;

  late String selectedClass;
  bool saving = false;

  double _number(String value) {
    return double.tryParse(value.trim().replaceAll(',', '')) ?? 0;
  }

  String _money(double value) {
    return value
        .toStringAsFixed(0)
        .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',');
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      isDense: true,
    );
  }

  @override
  void initState() {
    super.initState();

    final data = widget.data;
    final fees = Map<String, dynamic>.from((data['fees'] as Map?) ?? {});

    cRoll = TextEditingController(text: (data['roll_no'] ?? '').toString());
    cName = TextEditingController(
      text: (data['student_name'] ?? '').toString(),
    );
    cFather = TextEditingController(
      text: (data['father_name'] ?? '').toString(),
    );
    cSchool = TextEditingController(text: (fees['school_fee'] ?? 0).toString());
    cAc = TextEditingController(text: (fees['ac_charges'] ?? 0).toString());
    cStationary = TextEditingController(
      text: (fees['stationary_fee'] ?? 0).toString(),
    );

    final savedClass = (data['class'] ?? data['grade'] ?? '').toString().trim();
    selectedClass = savedClass;
  }

  @override
  void dispose() {
    cRoll.dispose();
    cName.dispose();
    cFather.dispose();
    cSchool.dispose();
    cAc.dispose();
    cStationary.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final roll = cRoll.text.trim();
    final name = cName.text.trim();
    final father = cFather.text.trim();

    if (selectedClass.trim().isEmpty ||
        roll.isEmpty ||
        name.isEmpty ||
        father.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Class, Roll No, Student Name and Father Name are required.',
          ),
        ),
      );
      return;
    }

    setState(() {
      saving = true;
    });

    final success = await widget.onSave({
      'roll_no': roll,
      'student_name': name,
      'father_name': father,
      'class': selectedClass,
      'school_fee': _number(cSchool.text),
      'ac_charges': _number(cAc.text),
      'stationary_fee': _number(cStationary.text),
    });

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop(true);
    } else {
      setState(() {
        saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final school = _number(cSchool.text);
    final ac = _number(cAc.text);
    final stationary = _number(cStationary.text);
    final total = school + ac + stationary;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      titlePadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      title: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: Color(0xFF1E293B),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(14),
            topRight: Radius.circular(14),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.edit_outlined, color: Colors.white70, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Edit — ${widget.data['student_name'] ?? ''}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              onPressed: saving
                  ? null
                  : () {
                      Navigator.of(context).pop(false);
                    },
              icon: const Icon(Icons.close, color: Colors.white70, size: 18),
            ),
          ],
        ),
      ),
      content: SizedBox(
        width: 450,
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Column(
              children: [
                DropdownButtonFormField<String>(
                  // Safe check taake invalid value par crash na ho
                  value:
                      selectedClass.isNotEmpty &&
                          widget.classes.contains(selectedClass)
                      ? selectedClass
                      : null,
                  isExpanded: true,
                  decoration: _inputDecoration('Class'),
                  items: widget.classes
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: saving
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            selectedClass = v;
                          });
                        },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _field('Roll No', cRoll)),
                    const SizedBox(width: 10),
                    Expanded(child: _field('Student Name', cName)),
                  ],
                ),
                _field('Father Name', cFather),
                const Divider(height: 20),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Fee Details',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _field(
                        'School Fee',
                        cSchool,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        'AC Charges',
                        cAc,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                _field(
                  'Stationary Fee',
                  cStationary,
                  keyboardType: TextInputType.number,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Total Fee: Rs. ${_money(total)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Delete Button (Left Side)
            TextButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Delete Student'),
                          content: Text(
                            'Are you sure you want to delete "${widget.data['student_name'] ?? ''}"? '
                            'This action cannot be undone.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(c, true),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );

                      if (confirm != true) return;

                      setState(() => saving = true);

                      if (widget.onDelete != null) {
                        final success = await widget.onDelete!();
                        if (!mounted) return;
                        if (success) {
                          Navigator.of(context).pop(true);
                        } else {
                          setState(() => saving = false);
                        }
                      } else {
                        setState(() => saving = false);
                      }
                    },
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.red,
                size: 18,
              ),
              label: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),

            // Update / Save Button (Right Side)
            ElevatedButton(
              onPressed: saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Update',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: (_) {
          setState(() {});
        },
        style: const TextStyle(fontSize: 13),
        decoration: _inputDecoration(label),
      ),
    );
  }
}
