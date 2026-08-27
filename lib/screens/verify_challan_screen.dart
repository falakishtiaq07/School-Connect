import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

const Color kNavy = Color(0xFF1E3A5F);
const Color kAccentBlue = Color(0xFF2E86AB);
const Color kBgLight = Color(0xFFF4F7FB);

const List<String> _kStatuses = ['Pending', 'Paid', 'Rejected'];

// =========================================================================
// LEVEL 1 — ALL CLASSES
// =========================================================================

/// Entry point: "Verify Challan". Shows all classes, fetched dynamically
/// from `student_profile`, each with a receipt-relevant count. Does NOT
/// touch the student-side upload logic or existing challan collections.
class AdminVerifyChallanScreen extends StatefulWidget {
  const AdminVerifyChallanScreen({super.key});

  @override
  State<AdminVerifyChallanScreen> createState() =>
      _AdminVerifyChallanScreenState();
}

class _AdminVerifyChallanScreenState extends State<AdminVerifyChallanScreen> {
  late Future<List<_ClassSummary>> _classesFuture;

  @override
  void initState() {
    super.initState();
    _classesFuture = _loadClasses();
  }

  /// Reads distinct `grade` values from `student_profile` and counts
  /// students per class. Client-side grouping keeps this working without
  /// needing a separate `classes` collection.
  Future<List<_ClassSummary>> _loadClasses() async {
    final snap = await FirebaseFirestore.instance.collection('users').get();

    final Map<String, int> counts = {};

    for (final doc in snap.docs) {
      final data = doc.data();

      final className = data['class']?.toString().trim();

      if (className == null || className.isEmpty) continue;

      counts[className] = (counts[className] ?? 0) + 1;
    }

    final list = counts.entries
        .map((e) => _ClassSummary(className: e.key, studentCount: e.value))
        .toList();

    // Sort numerically where possible ("9", "10", "11" ...), fall back to
    // string sort for non-numeric class labels.
    list.sort((a, b) {
      final an = int.tryParse(a.className);
      final bn = int.tryParse(b.className);
      if (an != null && bn != null) return an.compareTo(bn);
      return a.className.compareTo(b.className);
    });

    return list;
  }

  Future<void> _refresh() async {
    setState(() => _classesFuture = _loadClasses());
    await _classesFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgLight,
      appBar: AppBar(
        title: const Text(
          'Verify Challan',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: kNavy,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 4,
      ),
      body: FutureBuilder<List<_ClassSummary>>(
        future: _classesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: kAccentBlue),
            );
          }
          if (snapshot.hasError) {
            return _errorState('Could not load classes.', _refresh);
          }
          final classes = snapshot.data ?? [];
          if (classes.isEmpty) {
            return _emptyState(
              icon: Icons.school_outlined,
              title: 'No Classes Found',
              subtitle: 'No student records are available yet.',
            );
          }

          return RefreshIndicator(
            onRefresh: _refresh,
            color: kAccentBlue,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Padding(
                  padding: EdgeInsets.only(bottom: 14, left: 4),
                  child: Text(
                    'Select a class to view payment receipts',
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ),
                ...classes.map((c) => _classCard(c)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _classCard(_ClassSummary summary) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ClassReceiptsScreen(className: summary.className),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: kAccentBlue.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.school, color: kAccentBlue),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Class ${summary.className}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'View payment receipts • ${summary.studentCount} students',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ClassSummary {
  final String className;
  final int studentCount;
  _ClassSummary({required this.className, required this.studentCount});
}

// =========================================================================
// LEVEL 2 — RECEIPTS FOR THE SELECTED CLASS
// =========================================================================

/// Combines a `fee_receipts` document with the matching `student_profile`
/// record so the card can show name/roll/class without changing either
/// collection's schema.
class _ReceiptItem {
  final String docId;
  final Map<String, dynamic> receipt;
  final Map<String, dynamic>? student;

  _ReceiptItem({required this.docId, required this.receipt, this.student});

  String get studentName => student?['student_name']?.toString() ?? 'Unknown';
  String get rollNo =>
      receipt['roll_no']?.toString() ?? student?['roll_no']?.toString() ?? '—';
  String get status => (receipt['status'] ?? 'Pending').toString();
  String? get challanId => receipt['challanId']?.toString();
  String? get receiptUrl => receipt['receiptImageUrl']?.toString();
  Timestamp? get uploadedAt => receipt['uploadedAt'] is Timestamp
      ? receipt['uploadedAt'] as Timestamp
      : null;
}

class ClassReceiptsScreen extends StatefulWidget {
  final String className;
  const ClassReceiptsScreen({super.key, required this.className});

  @override
  State<ClassReceiptsScreen> createState() => _ClassReceiptsScreenState();
}

class _ClassReceiptsScreenState extends State<ClassReceiptsScreen> {
  final _searchController = TextEditingController();
  String _searchTerm = '';

  bool _loadingRoster = true;
  String? _rosterError;

  Map<String, Map<String, dynamic>> _rosterByRollNo =
      {}; // roll_no -> student data
  final Map<String, _ReceiptItem> _receiptsById = {}; // merged, live-updating

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    setState(() {
      _loadingRoster = true;
      _rosterError = null;
    });

    try {
      final rosterSnap = await FirebaseFirestore.instance
          .collection('student_profile')
          .where('grade', isEqualTo: widget.className)
          .get();

      _rosterByRollNo = {
        for (final doc in rosterSnap.docs)
          if (doc.data()['roll_no'] != null)
            doc.data()['roll_no'].toString(): doc.data(),
      };

      final rollNumbers = _rosterByRollNo.keys.toList();

      setState(() => _loadingRoster = false);

      if (rollNumbers.isEmpty) return; // empty state handles this

      // Firestore `whereIn` supports up to 30 values — chunk the roster
      // and merge the resulting streams so this still works for large
      // classes.
      const chunkSize = 30;
      for (var i = 0; i < rollNumbers.length; i += chunkSize) {
        final chunk = rollNumbers.sublist(
          i,
          i + chunkSize > rollNumbers.length
              ? rollNumbers.length
              : i + chunkSize,
        );

        final sub = FirebaseFirestore.instance
            .collection('fee_receipts')
            .where('roll_no', whereIn: chunk)
            .snapshots()
            .listen(
              _onReceiptsSnapshot,
              onError: (_) {
                if (mounted) {
                  setState(
                    () => _rosterError =
                        'Could not load receipts for this class.',
                  );
                }
              },
            );
        _subscriptions.add(sub);
      }
    } catch (e) {
      setState(() {
        _loadingRoster = false;
        _rosterError = 'Could not load the class roster.';
      });
    }
  }

  void _onReceiptsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final change in snap.docChanges) {
      final rollNo = change.doc.data()?['roll_no']?.toString();
      final student = rollNo != null ? _rosterByRollNo[rollNo] : null;

      if (change.type == DocumentChangeType.removed) {
        _receiptsById.remove(change.doc.id);
      } else {
        _receiptsById[change.doc.id] = _ReceiptItem(
          docId: change.doc.id,
          receipt: change.doc.data() ?? {},
          student: student,
        );
      }
    }
    if (mounted) setState(() {});
  }

  List<_ReceiptItem> get _filteredReceipts {
    final all = _receiptsById.values.toList()
      ..sort((a, b) {
        final at = a.uploadedAt?.toDate();
        final bt = b.uploadedAt?.toDate();
        if (at == null || bt == null) return 0;
        return bt.compareTo(at); // newest first
      });

    if (_searchTerm.trim().isEmpty) return all;

    final term = _searchTerm.trim().toLowerCase();
    return all.where((item) {
      final name = item.studentName.toLowerCase();
      final roll = item.rollNo.toLowerCase();
      final challan = (item.challanId ?? '').toLowerCase();
      return name.contains(term) ||
          roll.contains(term) ||
          challan.contains(term);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBgLight,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Class ${widget.className}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ],
        ),
        backgroundColor: kNavy,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 4,
        actions: [
          if (!_loadingRoster && _rosterError == null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Text(
                  '${_receiptsById.length} Receipts',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: _loadingRoster
          ? const Center(child: CircularProgressIndicator(color: kAccentBlue))
          : _rosterError != null
          ? _errorState(_rosterError!, _init)
          : Column(
              children: [
                _buildSearchBar(),
                Expanded(
                  child: _rosterByRollNo.isEmpty
                      ? _emptyState(
                          icon: Icons.groups_outlined,
                          title: 'No Students Found',
                          subtitle:
                              'No students are recorded under Class ${widget.className} yet.',
                        )
                      : _filteredReceipts.isEmpty
                      ? (_searchTerm.isEmpty
                            ? _emptyState(
                                icon: Icons.receipt_long_outlined,
                                title: 'No Payment Receipts',
                                subtitle:
                                    'No students from this class have uploaded a payment receipt yet.',
                              )
                            : _emptyState(
                                icon: Icons.search_off,
                                title: 'No Matches',
                                subtitle:
                                    'No receipts in Class ${widget.className} match "$_searchTerm".',
                              ))
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                          itemCount: _filteredReceipts.length,
                          itemBuilder: (context, index) =>
                              _receiptCard(_filteredReceipts[index]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchTerm = v),
        decoration: InputDecoration(
          hintText: 'Search student, roll no or challan...',
          hintStyle: const TextStyle(fontSize: 13.5, color: Colors.grey),
          prefixIcon: const Icon(Icons.search, color: kAccentBlue),
          suffixIcon: _searchTerm.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchTerm = '');
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 0,
            horizontal: 14,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _receiptCard(_ReceiptItem item) {
    final config = _statusConfig(item.status);
    final uploadedDisplay = item.uploadedAt != null
        ? DateFormat('d MMM yyyy').format(item.uploadedAt!.toDate())
        : '—';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReceiptDetailScreen(item: item),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: item.receiptUrl != null
                      ? Image.network(
                          item.receiptUrl!,
                          height: 60,
                          width: 60,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 60,
                              width: 60,
                              color: Colors.grey.shade100,
                              child: const Center(
                                child: SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            height: 60,
                            width: 60,
                            color: Colors.grey.shade100,
                            child: const Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                              size: 20,
                            ),
                          ),
                        )
                      : Container(
                          height: 60,
                          width: 60,
                          color: Colors.grey.shade100,
                          child: const Icon(
                            Icons.image_not_supported,
                            color: Colors.grey,
                            size: 20,
                          ),
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 15,
                            color: kAccentBlue,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              item.studentName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14.5,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Roll No: ${item.rollNo}  •  Class: ${widget.className}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Challan: ${item.challanId ?? '—'}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
                      Text(
                        'Uploaded: $uploadedDisplay',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(config.icon, size: 14, color: config.color),
                          const SizedBox(width: 4),
                          Text(
                            config.label,
                            style: TextStyle(
                              color: config.color,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =========================================================================
// LEVEL 3 — RECEIPT DETAIL + STATUS UPDATE
// =========================================================================

class ReceiptDetailScreen extends StatefulWidget {
  final _ReceiptItem item;
  const ReceiptDetailScreen({super.key, required this.item});

  @override
  State<ReceiptDetailScreen> createState() => _ReceiptDetailScreenState();
}

class _ReceiptDetailScreenState extends State<ReceiptDetailScreen> {
  late String _selectedStatus;
  final _remarksController = TextEditingController();
  bool _saving = false;

  Map<String, dynamic>? _challanData;
  bool _loadingChallan = true;

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.item.status;
    _remarksController.text = (widget.item.receipt['adminRemarks'] ?? '')
        .toString();
    _loadChallan();
  }

  @override
  void dispose() {
    _remarksController.dispose();
    super.dispose();
  }

  Future<void> _loadChallan() async {
    final challanId = widget.item.challanId;
    if (challanId == null) {
      setState(() => _loadingChallan = false);
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('challans')
          .doc(challanId)
          .get();
      if (doc.exists) _challanData = doc.data();
    } catch (_) {
      // Non-fatal — challan info is supplementary here.
    } finally {
      if (mounted) setState(() => _loadingChallan = false);
    }
  }

  Future<void> _updateStatus() async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('fee_receipts')
          .doc(widget.item.docId)
          .update({
            'status': _selectedStatus,
            'adminRemarks': _remarksController.text.trim(),
          });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status updated to $_selectedStatus.'),
          backgroundColor: kNavy,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update the status. Please try again.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
          body: Center(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 4,
              child: Image.network(
                url,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image,
                  color: Colors.white,
                  size: 48,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return Scaffold(
      backgroundColor: kBgLight,
      appBar: AppBar(
        title: const Text(
          'Receipt Details',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        backgroundColor: kNavy,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 4,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard(
            title: 'Student Information',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(Icons.person, 'Name', item.studentName),
                _infoRow(Icons.badge, 'Roll Number', item.rollNo),
                _infoRow(
                  Icons.class_,
                  'Class',
                  item.student?['grade']?.toString() ?? '—',
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            title: 'Challan Information',
            child: _loadingChallan
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(
                      child: SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _challanData == null
                ? _infoRow(
                    Icons.receipt_long,
                    'Challan No',
                    item.challanId ?? '—',
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _infoRow(
                        Icons.confirmation_number,
                        'Challan No',
                        (_challanData?['challanNumber'] ??
                                _challanData?['challan_number'] ??
                                item.challanId ??
                                '—')
                            .toString(),
                      ),
                      if (_challanData?['totalFee'] != null ||
                          _challanData?['total_fee'] != null)
                        _infoRow(
                          Icons.payments,
                          'Amount',
                          (_challanData?['totalFee'] ??
                                  _challanData?['total_fee'])
                              .toString(),
                        ),
                      if (_dueDateDisplay() != null)
                        _infoRow(Icons.event, 'Due Date', _dueDateDisplay()!),
                      if (_challanData?['feeMonth'] != null ||
                          _challanData?['fee_month'] != null)
                        _infoRow(
                          Icons.calendar_month,
                          'Fee Month',
                          (_challanData?['feeMonth'] ??
                                  _challanData?['fee_month'])
                              .toString(),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            title: 'Payment Receipt',
            padding: EdgeInsets.zero,
            child: item.receiptUrl == null
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No receipt image available for this record.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : GestureDetector(
                    onTap: () => _openFullScreenImage(item.receiptUrl!),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Image.network(
                          item.receiptUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                color: kAccentBlue,
                              ),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: Icon(
                                Icons.broken_image,
                                color: Colors.grey,
                                size: 40,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          _sectionCard(
            title: 'Payment Status',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _kStatuses.map((s) => _statusChip(s)).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Admin Remarks (optional)',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _remarksController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'e.g. Payment verified successfully.',
                    hintStyle: const TextStyle(fontSize: 12.5),
                    filled: true,
                    fillColor: kBgLight,
                    contentPadding: const EdgeInsets.all(12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _updateStatus,
              style: ElevatedButton.styleFrom(
                backgroundColor: kAccentBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 3,
              ),
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Text(
                      'Update Status',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  String? _dueDateDisplay() {
    final raw = _challanData?['dueDate'] ?? _challanData?['due_date'];
    if (raw is Timestamp) return DateFormat('d MMM yyyy').format(raw.toDate());
    if (raw is String) return raw;
    return null;
  }

  Widget _statusChip(String status) {
    final config = _statusConfig(status);
    final selected = _selectedStatus == status;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            config.icon,
            size: 16,
            color: selected ? Colors.white : config.color,
          ),
          const SizedBox(width: 6),
          Text(
            status,
            style: TextStyle(
              color: selected ? Colors.white : config.color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      selected: selected,
      onSelected: (_) => setState(() => _selectedStatus = status),
      selectedColor: config.color,
      backgroundColor: config.bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: config.color.withOpacity(0.4)),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    EdgeInsets? padding,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (padding == EdgeInsets.zero)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            child,
          ],
        ),
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
}

// =========================================================================
// SHARED HELPERS
// =========================================================================

class _StatusConfig {
  final Color color;
  final Color bg;
  final IconData icon;
  final String label;
  _StatusConfig({
    required this.color,
    required this.bg,
    required this.icon,
    required this.label,
  });
}

_StatusConfig _statusConfig(String status) {
  switch (status) {
    case 'Paid':
      return _StatusConfig(
        color: Colors.green.shade700,
        bg: Colors.green.shade50,
        icon: Icons.check_circle,
        label: 'Paid',
      );
    case 'Rejected':
      return _StatusConfig(
        color: Colors.red.shade700,
        bg: Colors.red.shade50,
        icon: Icons.cancel,
        label: 'Rejected',
      );
    default:
      return _StatusConfig(
        color: Colors.orange.shade800,
        bg: Colors.orange.shade50,
        icon: Icons.access_time_filled,
        label: 'Pending',
      );
  }
}

Widget _emptyState({
  required IconData icon,
  required String title,
  required String subtitle,
}) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

Widget _errorState(String message, VoidCallback onRetry) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRetry,
            style: ElevatedButton.styleFrom(backgroundColor: kAccentBlue),
            child: const Text('Retry'),
          ),
        ],
      ),
    ),
  );
}
