import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:school_connect/screens/add_users_screen.dart';
import 'package:school_connect/service/email_verification_service.dart';

// ═══════════════════════════════════════════════════════════════════════════
// MANAGE USERS SCREEN
// ═══════════════════════════════════════════════════════════════════════════

class ManageUsersScreen extends StatefulWidget {
  const ManageUsersScreen({super.key});
  @override
  State<ManageUsersScreen> createState() => _ManageUsersScreenState();
}

class _ManageUsersScreenState extends State<ManageUsersScreen>
    with SingleTickerProviderStateMixin {
  // ── Theme ──────────────────────────────────────────────────────────────────
  static const _navy = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF2E86AB);
  static const _green = Color(0xFF28A745);
  static const _red = Color(0xFFDC3545);
  static const _amber = Color(0xFFF59E0B);
  static const _bg = Color(0xFFF0F4F8);
  static const _white = Colors.white;

  late final TabController _tab = TabController(length: 3, vsync: this);

  // ── Import state ───────────────────────────────────────────────────────────
  bool _isImporting = false;
  int _importProgress = 0;
  int _importTotal = 0;
  int _importedCount = 0;
  List<String> _skipped = [];

  // ── Promote state ──────────────────────────────────────────────────────────
  String? _promoteClass;
  List<DocumentSnapshot> _promoteStudents = [];
  Set<String> _promoteSelected = {};
  bool _loadingPromote = false;

  static const List<String> _classes = [
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
  static final _emailRx = RegExp(r'^[\w.+\-]+@[a-zA-Z\d\-]+\.[a-zA-Z]{2,}$');

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // IMPORT LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _pickFile() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'csv'],
      withData: true,
    );
    if (res == null || res.files.first.bytes == null) return;
    await _importExcel(res.files.first.bytes!);
  }

  void _showAddUserDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add User"),
          content: const Text("Coming Soon"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Close"),
            ),
          ],
        );
      },
    );
  }

  Future<UserCredential> _createUserAndSendVerification({
    required String email,
    required String password,
  }) async {
    final String tempAppName =
        'bulkCreateUser_${DateTime.now().millisecondsSinceEpoch}';

    final FirebaseApp tempApp = await Firebase.initializeApp(
      name: tempAppName,
      options: Firebase.app().options,
    );

    try {
      final FirebaseAuth tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      final UserCredential credential = await tempAuth
          .createUserWithEmailAndPassword(email: email, password: password);

      // Verification email send karo
      await credential.user!.sendEmailVerification();

      // Temporary session logout
      await tempAuth.signOut();

      return credential;
    } finally {
      await tempApp.delete();
    }
  }

  Future<void> _importExcel(Uint8List bytes) async {
    final excel = xl.Excel.decodeBytes(bytes);
    final sheet = excel.tables[excel.tables.keys.first];
    if (sheet == null || sheet.rows.length < 2) {
      _snack('File is empty or missing header row.', isError: true);
      return;
    }

    final headers = sheet.rows.first
        .map((c) => c?.value?.toString().trim().toLowerCase() ?? '')
        .toList();

    // int idx(String h) => headers.indexOf(h);
    int idx(String h) => headers.indexOf(h.toLowerCase());
    final ni = idx('name');
    final ei = idx('email');
    final ri = idx('role');
    final ci = idx('class');
    final rni = idx('rollNo');

    if (ni < 0 || ei < 0 || ri < 0) {
      _snack('Required columns: name, email, role', isError: true);
      return;
    }

    final rows = sheet.rows
        .skip(1)
        .where(
          (r) => !r.every(
            (c) => c == null || (c.value?.toString().trim() ?? '').isEmpty,
          ),
        )
        .toList();

    setState(() {
      _isImporting = true;
      _importProgress = 0;
      _importTotal = rows.length;
      _importedCount = 0;
      _skipped = [];
    });

    String cell(List row, int i) =>
        i >= 0 && i < row.length ? row[i]?.value?.toString().trim() ?? '' : '';

    final fs = FirebaseFirestore.instance;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final name = cell(row, ni);
      final email = cell(row, ei);
      final roleInput = cell(row, ri).trim().toLowerCase();

      String role = '';

      if (roleInput == 'student') {
        role = 'Student';
      } else if (roleInput == 'teacher') {
        role = 'Teacher';
      }
      final cls = cell(row, ci);
      final rollNo = cell(row, rni);
      final label = name.isNotEmpty ? name : 'Row ${i + 2}';

      // ── Validation ─────────────────────────────────────────────────────
      if (email.isEmpty || !_emailRx.hasMatch(email)) {
        _skipped.add('$label — invalid email "$email"');
        if (mounted) setState(() => _importProgress++);
        continue;
      }
      bool isRealEmail = await EmailVerificationService.isEmailValid(email);
      if (!isRealEmail) {
        _skipped.add('$label ($email) — email does not exist');
        if (mounted) setState(() => _importProgress++);
        continue;
      }
      if (role != 'Teacher' && role != 'Student') {
        _skipped.add('$label ($email) — invalid role "$role"');
        if (mounted) setState(() => _importProgress++);
        continue;
      }
      if (role == 'Student' && rollNo.isEmpty) {
        _skipped.add('$label ($email) — student missing roll_no');
        if (mounted) setState(() => _importProgress++);
        continue;
      }
      // Duplicate check
      final dup = await fs
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (dup.docs.isNotEmpty) {
        _skipped.add('$label ($email) — duplicate email');
        if (mounted) setState(() => _importProgress++);
        continue;
      }

      // ── Password: Name@123 ──────────────────────────────────────────────
      final firstName = name.split(' ').first;
      final password = '${firstName}@123';

      // ── Create Firebase Auth user ───────────────────────────────────────
      try {
        final cred = await _createUserAndSendVerification(
          email: email,
          password: password,
        );

        // ── Write Firestore doc ─────────────────────────────────────────
        final Map<String, dynamic> doc = {
          'uid': cred.user!.uid,
          'name': name,
          'email': email,
          'role': role,
          'class': cls,
          'password': password, // stored for admin reference
          'created_at': FieldValue.serverTimestamp(),
        };
        if (role == 'Student') doc['rollNo'] = rollNo;

        await fs.collection('users').doc(cred.user!.uid).set(doc);
        _importedCount++;
      } catch (e) {
        _skipped.add('$label ($email) — auth error: $e');
      }

      if (mounted) setState(() => _importProgress++);
    }

    if (mounted) {
      setState(() => _isImporting = false);
      _showImportResult();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // PROMOTE LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadClassStudents(String cls) async {
    setState(() {
      _loadingPromote = true;
      _promoteStudents = [];
      _promoteSelected = {};
    });
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Student')
        .where('class', isEqualTo: cls)
        .orderBy('name')
        .get();
    if (mounted) {
      setState(() {
        _promoteStudents = snap.docs;
        _promoteSelected = snap.docs
            .map((d) => d.id)
            .toSet(); // select all by default
        _loadingPromote = false;
      });
    }
  }

  Future<void> _promoteSelected_() async {
    if (_promoteClass == null || _promoteSelected.isEmpty) return;
    final from = int.parse(_promoteClass!);
    final toClass = '${from + 1}';

    final ok = await _confirm(
      title: 'Promote ${_promoteSelected.length} Student(s)?',
      body:
          'Selected students from Class $_promoteClass → Class $toClass.\n\nOther students will remain in Class $_promoteClass.',
      btnLabel: 'Promote',
      btnColor: _accent,
    );
    if (!ok) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in _promoteStudents) {
      if (_promoteSelected.contains(doc.id)) {
        batch.update(doc.reference, {'class': toClass});
      }
    }
    await batch.commit();
    _snack('${_promoteSelected.length} student(s) promoted to Class $toClass.');
    await _loadClassStudents(_promoteClass!); // refresh
  }

  Future<void> _promoteAll() async {
    if (_promoteClass == null || _promoteStudents.isEmpty) return;
    final from = int.parse(_promoteClass!);
    final toClass = '${from + 1}';

    final ok = await _confirm(
      title: 'Promote All ${_promoteStudents.length} Students?',
      body:
          'ALL students in Class $_promoteClass will be moved to Class $toClass.',
      btnLabel: 'Promote All',
      btnColor: _accent,
    );
    if (!ok) return;

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in _promoteStudents) {
      batch.update(doc.reference, {'class': toClass});
    }
    await batch.commit();
    _snack(
      'All ${_promoteStudents.length} students promoted to Class $toClass.',
    );
    setState(() {
      _promoteStudents = [];
      _promoteSelected = {};
      _promoteClass = null;
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DELETE LOGIC
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _deleteUser(DocumentSnapshot doc) async {
    final d = doc.data() as Map<String, dynamic>;
    final role = d['role']?.toString() ?? 'user';
    final name = d['name']?.toString() ?? 'this user';

    final ok = await _confirm(
      title: 'Remove ${role == 'Teacher' ? 'Teacher' : 'Student'}?',
      body: role == 'Teacher'
          ? 'Are you sure you want to remove this teacher?\n\n"$name" will be permanently deleted.'
          : 'Are you sure you want to remove "$name"?',
      btnLabel: 'Remove',
      btnColor: _red,
    );
    if (!ok) return;
    await doc.reference.delete();
    _snack('"$name" removed.');
  }

  Future<void> _deleteClass(String cls) async {
    final ok = await _confirm(
      title: 'Delete Entire Class $cls?',
      body:
          'This action will permanently remove ALL students of Class $cls.\n\nContinue?',
      btnLabel: 'Delete Class',
      btnColor: _red,
    );
    if (!ok) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Student')
        .where('class', isEqualTo: cls)
        .get();

    final batch = FirebaseFirestore.instance.batch();
    for (final d in snap.docs) batch.delete(d.reference);
    await batch.commit();
    _snack('Class $cls — ${snap.docs.length} student(s) deleted.');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // ASSIGN TEACHER CLASS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAssignDialog(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    String? picked;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, ss) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: EdgeInsets.zero,
          title: _dialogTitle(
            'Assign Class — ${d['name']}',
            Icons.class_outlined,
          ),
          contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          content: SizedBox(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: picked,
                  hint: const Text('Select class'),
                  items: _classes
                      .map(
                        (c) =>
                            DropdownMenuItem(value: c, child: Text('Class $c')),
                      )
                      .toList(),
                  onChanged: (v) => ss(() => picked = v),
                  decoration: _inDeco('Select class'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _navy,
                          side: const BorderSide(color: _navy),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: picked == null
                            ? null
                            : () async {
                                Navigator.pop(ctx);
                                final ok = await _confirm(
                                  title: 'Assign Class $picked?',
                                  body:
                                      'Assign "${d['name']}" to Class $picked?',
                                  btnLabel: 'Assign',
                                  btnColor: _accent,
                                );
                                if (!ok) return;
                                await doc.reference.update({'class': picked});
                                _snack(
                                  '"${d['name']}" assigned to Class $picked.',
                                );
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _navy,
                          foregroundColor: _white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        child: const Text(
                          'Assign',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isMob = w < 600;
        final isTab = w >= 600 && w < 900;
        final isDsk = w >= 900;

        return Scaffold(
          backgroundColor: _bg,
          appBar: _buildAppBar(isMob),
          body: _isImporting
              ? _importOverlay()
              : Column(
                  children: [
                    // ── Stats ──────────────────────────────────────────────────
                    _StatsBar(
                      isMobile: isMob,
                      isTablet: isTab,
                      isDesktop: isDsk,
                    ),
                    // ── Tabs ───────────────────────────────────────────────────
                    Expanded(
                      child: TabBarView(
                        controller: _tab,
                        children: [
                          _StudentsTab(
                            onDelete: _deleteUser,
                            isMobile: isMob,
                            classes: _classes,
                            onDeleteClass: _deleteClass,
                          ),
                          _PromoteTab(
                            classes: _classes.where((c) => c != '10').toList(),
                            promoteClass: _promoteClass,
                            students: _promoteStudents,
                            selected: _promoteSelected,
                            loading: _loadingPromote,
                            isMobile: isMob,
                            onClassChanged: (v) {
                              setState(() => _promoteClass = v);
                              if (v != null) _loadClassStudents(v);
                            },
                            onToggle: (id, val) => setState(() {
                              val
                                  ? _promoteSelected.add(id)
                                  : _promoteSelected.remove(id);
                            }),
                            onSelectAll: (val) => setState(() {
                              _promoteSelected = val
                                  ? _promoteStudents.map((d) => d.id).toSet()
                                  : {};
                            }),
                            onPromoteSelected: _promoteSelected_,
                            onPromoteAll: _promoteAll,
                          ),
                          _TeachersTab(
                            isMobile: isMob,
                            onDelete: _deleteUser,
                            onAssign: _showAssignDialog,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  AppBar _buildAppBar(bool isMob) {
    return AppBar(
      backgroundColor: _navy,
      foregroundColor: _white,
      elevation: 0,
      title: const Text(
        'Manage Users',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'import') {
                _pickFile();
              } else if (value == 'add') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddUserScreen()),
                );
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(Icons.person_add_alt_1, color: Colors.black),
                    SizedBox(width: 10),
                    Text('Add User'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(Icons.upload_file, color: Colors.black),
                    SizedBox(width: 10),
                    Text('Import Excel'),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: const [
                  Icon(Icons.add, color: Colors.white, size: 18),
                  SizedBox(width: 5),
                  Text(
                    "Add",
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
      bottom: TabBar(
        controller: _tab,
        indicatorColor: _white,
        indicatorWeight: 3,
        labelColor: _white,
        unselectedLabelColor: Colors.white60,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        tabs: const [
          Tab(icon: Icon(Icons.school_outlined, size: 16), text: 'Students'),
          Tab(
            icon: Icon(Icons.arrow_upward_rounded, size: 16),
            text: 'Promote',
          ),
          Tab(icon: Icon(Icons.person_outlined, size: 16), text: 'Teachers'),
        ],
      ),
    );
  }

  // ── Import overlay ─────────────────────────────────────────────────────────
  Widget _importOverlay() {
    final pct = _importTotal > 0 ? _importProgress / _importTotal : 0.0;
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(36),
        constraints: const BoxConstraints(maxWidth: 380),
        decoration: BoxDecoration(
          color: _white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 24),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.upload_file_outlined, size: 48, color: _navy),
            const SizedBox(height: 20),
            const Text(
              'Importing Users...',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F2937),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$_importProgress of $_importTotal',
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 22),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 12,
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

  // ── Import result dialog ───────────────────────────────────────────────────
  void _showImportResult() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: EdgeInsets.zero,
        title: _dialogTitle('Import Results', Icons.cloud_done_outlined),
        contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 12,
                children: [
                  _chip('Imported', '$_importedCount', _green),
                  _chip('Skipped', '${_skipped.length}', _amber),
                ],
              ),
              if (_skipped.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180),
                  decoration: BoxDecoration(
                    color: _amber.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _amber.withOpacity(0.3)),
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Skipped users:',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Color(0xFF92400E),
                          ),
                        ),
                        const SizedBox(height: 6),
                        ..._skipped.map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '• $s',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF92400E),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: _white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9),
                    ),
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  Future<bool> _confirm({
    required String title,
    required String body,
    required String btnLabel,
    required Color btnColor,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          content: Text(body, style: const TextStyle(fontSize: 14)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(c, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: btnColor,
                foregroundColor: _white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                btnLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ) ??
      false;

  void _snack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? _red : _green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static Widget _dialogTitle(String t, IconData icon) => Container(
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
        Icon(icon, color: Colors.white70, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            t,
            style: const TextStyle(
              color: _white,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  static Widget _chip(String label, String val, Color c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
    decoration: BoxDecoration(
      color: c.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: c.withOpacity(0.25)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          val,
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: c),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
        ),
      ],
    ),
  );

  static InputDecoration _inDeco(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFADB5BD), fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: _accent, width: 1.5),
    ),
    filled: true,
    fillColor: const Color(0xFFF9FAFB),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// STATS BAR — realtime Firestore counts
// ═══════════════════════════════════════════════════════════════════════════

class _StatsBar extends StatelessWidget {
  final bool isMobile, isTablet, isDesktop;
  const _StatsBar({
    required this.isMobile,
    required this.isTablet,
    required this.isDesktop,
  });

  static const _navy = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF2E86AB);
  static const _green = Color(0xFF28A745);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('users').snapshots(),
      builder: (_, snap) {
        final docs = snap.data?.docs ?? [];
        final students = docs
            .where((d) => (d.data() as Map)['role'] == 'Student')
            .length;
        final teachers = docs
            .where((d) => (d.data() as Map)['role'] == 'Teacher')
            .length;
        final total = docs.length;

        final cards = [
          _StatCard(
            label: 'Students',
            value: '$students',
            icon: Icons.school_outlined,
            color: _accent,
          ),
          _StatCard(
            label: 'Teachers',
            value: '$teachers',
            icon: Icons.person_outlined,
            color: _green,
          ),
          _StatCard(
            label: 'Total Users',
            value: '$total',
            icon: Icons.people_outline,
            color: _navy,
          ),
        ];

        return Container(
          color: const Color(0xFFF0F4F8),
          padding: EdgeInsets.fromLTRB(16, 12, 16, isMobile ? 8 : 12),
          child: isMobile
              // Mobile: vertical column
              ? Column(
                  children: cards
                      .map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: c,
                        ),
                      )
                      .toList(),
                )
              : isTablet
              // Tablet: 2+1
              ? Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: cards[0]),
                        const SizedBox(width: 12),
                        Expanded(child: cards[1]),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: cards[2]),
                        const Expanded(child: SizedBox()),
                      ],
                    ),
                  ],
                )
              // Desktop: 3 in one row
              : Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[2]),
                  ],
                ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STUDENTS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _StudentsTab extends StatefulWidget {
  final Future<void> Function(DocumentSnapshot) onDelete;
  final Future<void> Function(String) onDeleteClass;
  final List<String> classes;
  final bool isMobile;
  const _StudentsTab({
    required this.onDelete,
    required this.onDeleteClass,
    required this.classes,
    required this.isMobile,
  });
  @override
  State<_StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<_StudentsTab> {
  String? _openClass;
  final _searchCtrl = TextEditingController();
  String _searchQ = '';

  static const _navy = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF2E86AB);
  static const _red = Color(0xFFDC3545);

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(
      () => setState(() => _searchQ = _searchCtrl.text.toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Search
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search students...',
              hintStyle: const TextStyle(
                color: Color(0xFFADB5BD),
                fontSize: 13,
              ),
              prefixIcon: const Icon(
                Icons.search,
                color: Color(0xFF9CA3AF),
                size: 20,
              ),
              suffixIcon: _searchQ.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 16,
                        color: Color(0xFF9CA3AF),
                      ),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQ = '');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: _accent, width: 1.5),
              ),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE5E7EB)),

        // Class list
        Expanded(
          child: _searchQ.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(14),
                  children: widget.classes
                      .map(
                        (cls) => _ClassTile(
                          cls: cls,
                          isOpen: _openClass == cls,
                          searchQ: '',
                          isMobile: widget.isMobile,
                          onToggle: () => setState(
                            () => _openClass = _openClass == cls ? null : cls,
                          ),
                          onDeleteUser: widget.onDelete,
                          onDeleteClass: () => widget.onDeleteClass(cls),
                        ),
                      )
                      .toList(),
                )
              : _SearchStudentsList(
                  searchQ: _searchQ,
                  isMobile: widget.isMobile,
                  onDelete: widget.onDelete,
                ),
        ),
      ],
    );
  }
}

// ── Class expandable tile ─────────────────────────────────────────────────

class _ClassTile extends StatelessWidget {
  final String cls;
  final bool isOpen, isMobile;
  final String searchQ;
  final VoidCallback onToggle, onDeleteClass;
  final Future<void> Function(DocumentSnapshot) onDeleteUser;

  static const _navy = Color(0xFF1E3A5F);
  static const _red = Color(0xFFDC3545);
  static const _bg = Color(0xFFF0F4F8);

  const _ClassTile({
    required this.cls,
    required this.isOpen,
    required this.isMobile,
    required this.searchQ,
    required this.onToggle,
    required this.onDeleteClass,
    required this.onDeleteUser,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _navy.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: Text(
                        cls,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: _navy,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Class $cls',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  // Delete class btn
                  InkWell(
                    onTap: onDeleteClass,
                    borderRadius: BorderRadius.circular(7),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(color: _red.withOpacity(0.2)),
                      ),
                      child: const Icon(
                        Icons.delete_sweep_outlined,
                        color: _red,
                        size: 16,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    isOpen
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: const Color(0xFF9CA3AF),
                  ),
                ],
              ),
            ),
          ),

          // Expanded student list
          if (isOpen)
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .where('role', isEqualTo: 'Student')
                  .where('class', isEqualTo: cls)
                  .orderBy('name')
                  .snapshots(),
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: CircularProgressIndicator(color: _navy),
                    ),
                  );
                }
                var docs = snap.data?.docs ?? [];
                // if (searchQ.isNotEmpty) {
                //   docs = docs.where((d) {
                //     final data = d.data() as Map<String, dynamic>;
                //     return (data['name'] ?? '')
                //             .toString()
                //             .toLowerCase()
                //             .contains(searchQ) ||
                //         (data['rollNo'] ?? '')
                //             .toString()
                //             .toLowerCase()
                //             .contains(searchQ);
                //   }).toList();
                // }
                // if (docs.isEmpty) {
                //   return Padding(
                //     padding: const EdgeInsets.all(16),
                //     child: Text(
                //       searchQ.isNotEmpty
                //           ? 'No students match "$searchQ"'
                //           : 'No students in Class $cls.',
                //       style: const TextStyle(
                //         color: Color(0xFF9CA3AF),
                //         fontSize: 13,
                //       ),
                //     ),
                //   );
                // }
                if (docs.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No students in Class $cls.',
                      style: const TextStyle(color: Color(0xFF9CA3AF)),
                    ),
                  );
                }
                return Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      ...docs.map((doc) {
                        final d = doc.data() as Map<String, dynamic>;
                        final name = d['name']?.toString() ?? '—';
                        final roll = d['rollNo']?.toString() ?? '—';
                        final email = d['email']?.toString() ?? '—';
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 10,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: _navy.withOpacity(0.09),
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child: Text(
                                    name.isNotEmpty
                                        ? name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      color: _navy,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1F2937),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          'Roll# $roll',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                        if (!isMobile) ...[
                                          const Text(
                                            '  •  ',
                                            style: TextStyle(
                                              color: Color(0xFF9CA3AF),
                                            ),
                                          ),
                                          Flexible(
                                            child: Text(
                                              email,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF9CA3AF),
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => onDeleteUser(doc),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: _red,
                                  size: 18,
                                ),
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SearchStudentsList extends StatelessWidget {
  final String searchQ;
  final bool isMobile;
  final Future<void> Function(DocumentSnapshot) onDelete;

  const _SearchStudentsList({
    required this.searchQ,
    required this.isMobile,
    required this.onDelete,
  });

  static const _navy = Color(0xFF1E3A5F);
  static const _red = Color(0xFFDC3545);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'Student')
          .orderBy('name')
          .snapshots(),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        var docs = snap.data!.docs;

        docs = docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;

          final name = (d['name'] ?? '').toString().toLowerCase();

          final roll = (d['rollNo'] ?? '').toString().toLowerCase();

          return name.contains(searchQ) || roll.contains(searchQ);
        }).toList();

        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No student found',
              style: TextStyle(color: Colors.grey),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          itemBuilder: (_, index) {
            final doc = docs[index];
            final d = doc.data() as Map<String, dynamic>;

            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: ListTile(
                leading: CircleAvatar(
                  child: Text(d['name'].toString()[0].toUpperCase()),
                ),
                title: Text(d['name']),
                subtitle: Text(
                  'Roll# ${d['rollNo']}   •   Class ${d['class']}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, color: _red),
                  onPressed: () => onDelete(doc),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
// ═══════════════════════════════════════════════════════════════════════════
// PROMOTE TAB
// ═══════════════════════════════════════════════════════════════════════════

class _PromoteTab extends StatelessWidget {
  final List<String> classes;
  final String? promoteClass;
  final List<DocumentSnapshot> students;
  final Set<String> selected;
  final bool loading, isMobile;
  final void Function(String?) onClassChanged;
  final void Function(String, bool) onToggle;
  final void Function(bool) onSelectAll;
  final VoidCallback onPromoteSelected, onPromoteAll;

  static const _navy = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF2E86AB);

  const _PromoteTab({
    required this.classes,
    required this.promoteClass,
    required this.students,
    required this.selected,
    required this.loading,
    required this.isMobile,
    required this.onClassChanged,
    required this.onToggle,
    required this.onSelectAll,
    required this.onPromoteSelected,
    required this.onPromoteAll,
  });

  @override
  Widget build(BuildContext context) {
    final toClass = promoteClass != null
        ? '${int.parse(promoteClass!) + 1}'
        : '?';

    return SingleChildScrollView(
      padding: EdgeInsets.all(isMobile ? 14 : 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Step 1 ───────────────────────────────────────────────────────
          _sectionCard(
            step: '1',
            title: 'Select Class to Promote',
            child: DropdownButtonFormField<String>(
              value: promoteClass,
              hint: const Text('Select class (1–9)'),
              items: classes
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text('Class $c → Class ${int.parse(c) + 1}'),
                    ),
                  )
                  .toList(),
              onChanged: onClassChanged,
              decoration: InputDecoration(
                hintText: 'Select class',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _accent, width: 1.5),
                ),
                filled: true,
                fillColor: const Color(0xFFF9FAFB),
              ),
            ),
          ),

          if (promoteClass != null) ...[
            const SizedBox(height: 14),
            _sectionCard(
              step: '2',
              title: 'Select Students to Promote',
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(
                        child: CircularProgressIndicator(color: _navy),
                      ),
                    )
                  : students.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No students in this class.',
                        style: TextStyle(color: Color(0xFF9CA3AF)),
                      ),
                    )
                  : Column(
                      children: [
                        // Select all
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F4FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Checkbox(
                                value: selected.length == students.length,
                                onChanged: (v) => onSelectAll(v ?? false),
                                activeColor: _navy,
                              ),
                              const Text(
                                'Select All',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${selected.length}/${students.length} selected',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Color(0xFF6B7280),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Student rows
                        ...students.map((doc) {
                          final d = doc.data() as Map<String, dynamic>;
                          final name = d['name']?.toString() ?? '—';
                          final roll = d['rollNo']?.toString() ?? '—';
                          final isSel = selected.contains(doc.id);
                          return InkWell(
                            onTap: () => onToggle(doc.id, !isSel),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? const Color(0xFFF0F4FF)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSel
                                      ? _navy.withOpacity(0.3)
                                      : const Color(0xFFE5E7EB),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: isSel,
                                    onChanged: (v) =>
                                        onToggle(doc.id, v ?? false),
                                    activeColor: _navy,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      name,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _navy.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'Roll# $roll',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: _navy,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),

                        const SizedBox(height: 14),
                        // Promote buttons — wrap on small screens
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            SizedBox(
                              width: isMobile ? double.infinity : 200,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: selected.isEmpty
                                    ? null
                                    : onPromoteSelected,
                                icon: const Icon(
                                  Icons.people_outline,
                                  size: 16,
                                ),
                                label: Text(
                                  'Promote Selected (${selected.length}) → $toClass',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _accent,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                            SizedBox(
                              width: isMobile ? double.infinity : 200,
                              height: 44,
                              child: ElevatedButton.icon(
                                onPressed: students.isEmpty
                                    ? null
                                    : onPromoteAll,
                                icon: const Icon(
                                  Icons.groups_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  'Promote All (${students.length}) → $toClass',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _navy,
                                  foregroundColor: Colors.white,
                                  disabledBackgroundColor: Colors.grey.shade300,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String step,
    required String title,
    required Widget child,
  }) => Container(
    margin: const EdgeInsets.only(bottom: 0),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFE5E7EB)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: const BoxDecoration(
            color: Color(0xFFF0F4FF),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(14),
              topRight: Radius.circular(14),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: _navy,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    step,
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
                  fontWeight: FontWeight.w800,
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

// ═══════════════════════════════════════════════════════════════════════════
// TEACHERS TAB
// ═══════════════════════════════════════════════════════════════════════════

class _TeachersTab extends StatelessWidget {
  final bool isMobile;
  final Future<void> Function(DocumentSnapshot) onDelete;
  final void Function(DocumentSnapshot) onAssign;

  static const _navy = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF2E86AB);
  static const _red = Color(0xFFDC3545);

  const _TeachersTab({
    required this.isMobile,
    required this.onDelete,
    required this.onAssign,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'Teacher')
          .orderBy('name')
          .snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _navy));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_off_outlined,
                    size: 52,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No teachers found.',
                    style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                  ),
                ],
              ),
            ),
          );
        }
        return isMobile ? _mobileList(docs) : _desktopTable(docs, context);
      },
    );
  }

  Widget _desktopTable(List<QueryDocumentSnapshot> docs, BuildContext ctx) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF0F4FF)),
              headingTextStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _navy,
              ),
              dataRowMinHeight: 56,
              dataRowMaxHeight: 56,
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Email')),
                DataColumn(label: Text('Assigned Class')),
                DataColumn(label: Text('Actions')),
              ],
              rows: docs.map((doc) {
                final d = doc.data() as Map<String, dynamic>;
                final name = d['name']?.toString() ?? '—';
                final cls = d['class']?.toString() ?? '—';
                return DataRow(
                  cells: [
                    DataCell(
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        d['email'] ?? '—',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                    DataCell(
                      cls == '—'
                          ? const Text(
                              'Not Assigned',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF9CA3AF),
                              ),
                            )
                          : Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _navy.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Class $cls',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: _navy,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                    ),
                    DataCell(
                      Row(
                        children: [
                          _btn(
                            Icons.class_outlined,
                            _accent,
                            'Assign Class',
                            () => onAssign(doc),
                          ),
                          const SizedBox(width: 6),
                          _btn(
                            Icons.delete_outline,
                            _red,
                            'Remove Teacher',
                            () => onDelete(doc),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mobileList(List<QueryDocumentSnapshot> docs) {
    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: docs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) {
        final doc = docs[i];
        final d = doc.data() as Map<String, dynamic>;
        final name = d['name']?.toString() ?? '?';
        final cls = d['class']?.toString() ?? '';
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _navy.withOpacity(0.09),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: _navy,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        d['email'] ?? '—',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 5),
                      cls.isNotEmpty
                          ? Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: _navy.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Class $cls',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: _navy,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            )
                          : const Text(
                              'No class assigned',
                              style: TextStyle(
                                fontSize: 11,
                                color: Color(0xFF9CA3AF),
                              ),
                            ),
                    ],
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => onAssign(doc),
                      icon: const Icon(
                        Icons.class_outlined,
                        color: _accent,
                        size: 20,
                      ),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      tooltip: 'Assign Class',
                    ),
                    IconButton(
                      onPressed: () => onDelete(doc),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: _red,
                        size: 20,
                      ),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(),
                      tooltip: 'Remove Teacher',
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _btn(IconData icon, Color c, String tip, VoidCallback fn) {
    return Tooltip(
      message: tip,
      child: InkWell(
        onTap: fn,
        borderRadius: BorderRadius.circular(7),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: c.withOpacity(0.08),
            borderRadius: BorderRadius.circular(7),
            border: Border.all(color: c.withOpacity(0.2)),
          ),
          child: Icon(icon, color: c, size: 16),
        ),
      ),
    );
  }
}
