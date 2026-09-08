import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:school_connect/service/notification_service.dart';

const Color kNavy = Color(0xFF1E3A5F);
const Color kAccentBlue = Color(0xFF2E86AB);
const Color kBgLight = Color(0xFFF4F7FB);

const List<String> _kStatuses = ['Pending', 'Paid', 'Rejected'];

// =========================================================================
// LEVEL 1 — ALL CLASSES
// =========================================================================

/// Entry point: "Verify Challan". Shows all classes that currently have at
/// least one Student in the `users` collection — this is the single source
/// of truth used everywhere else in the app (Manage Users, Promote,
/// Generate Challan). If every student in a class is removed from `users`,
/// that class automatically disappears from this list.
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

  /// Reads distinct `class` values from `users` (role == Student only) and
  /// counts students per class. Client-side grouping keeps this working
  /// without needing a separate `classes` collection.
  Future<List<_ClassSummary>> _loadClasses() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Student')
        .get();

    final Map<String, int> counts = {};
    final Map<String, List<String>> classToUids = {};

    for (final doc in snap.docs) {
      final data = doc.data();
      final className = data['class']?.toString().trim();
      final uid = data['uid']?.toString() ?? doc.id;

      if (className == null || className.isEmpty) continue;

      counts[className] = (counts[className] ?? 0) + 1;
      classToUids.putIfAbsent(className, () => []).add(uid);
    }

    // Sabhi unread pending receipts la kar check karein ke kis class mein hain
    final receiptsSnap = await FirebaseFirestore.instance
        .collection('fee_receipts')
        .where('status', isEqualTo: 'Pending')
        .get();

    final unreadUids = <String>{};
    for (final doc in receiptsSnap.docs) {
      final data = doc.data();
      if (data['adminRead'] != true) {
        final studentId = data['studentId']?.toString();
        if (studentId != null) {
          unreadUids.add(studentId);
        }
      }
    }

    final list = counts.entries.map((e) {
      final className = e.key;
      final uidsInClass = classToUids[className] ?? [];

      // Check karein ke kya is class ke kisi student ki unread receipt hai
      final hasUnread = uidsInClass.any((uid) => unreadUids.contains(uid));

      return _ClassSummary(
        className: className,
        studentCount: e.value,
        hasUnread: hasUnread,
      );
    }).toList();

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
            return _errorState(
              'Could not load classes: ${snapshot.error}',
              _refresh,
            );
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
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    ClassReceiptsScreen(className: summary.className),
              ),
            );
            // Jab wapas aayein toh classes list refresh hojaye taake red dot hat jaye
            setState(() {});
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
                // 🔴 Stack laga kar Icon par Red Dot lagaya hai
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kAccentBlue.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.school, color: kAccentBlue),
                    ),
                    if (summary.hasUnread)
                      Positioned(
                        right: -2,
                        top: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
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
  final bool hasUnread;
  _ClassSummary({
    required this.className,
    required this.studentCount,
    required this.hasUnread,
  });
}

// =========================================================================
// LEVEL 2 — RECEIPTS FOR THE SELECTED CLASS
// =========================================================================

/// Combines a `fee_receipts` document with the matching `users` record
/// (looked up by uid, i.e. `studentId`) so the card can show name/roll/
/// class without depending on any separate profile collection staying in
/// sync.
class _ReceiptItem {
  final String docId;
  final Map<String, dynamic> receipt;
  final Map<String, dynamic>? student;
  bool get hasUnread =>
      status.toLowerCase() == 'pending' && receipt['adminRead'] != true;

  _ReceiptItem({required this.docId, required this.receipt, this.student});

  String get studentUid => (receipt['studentId'] ?? '').toString();
  String get studentName => (student?['name'] ?? 'Unknown').toString();
  String get rollNo =>
      (student?['rollNo'] ?? receipt['roll_no'] ?? '—').toString();
  String get studentClass => (student?['class'] ?? '—').toString();
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

  Map<String, Map<String, dynamic>> _rosterByUid = {}; // uid -> student data
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
    // Cancel any subscriptions from a previous attempt (e.g. the user
    // tapped "Retry" after an error) so they don't leak/duplicate.
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
    _receiptsById.clear();

    setState(() {
      _loadingRoster = true;
      _rosterError = null;
    });

    try {
      // Single source of truth: `users` collection. If a student is
      // removed from here, they automatically disappear from this roster
      // too — no separate profile collection to keep in sync.
      final rosterSnap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'Student')
          .where('class', isEqualTo: widget.className)
          .get();

      _rosterByUid = {
        for (final doc in rosterSnap.docs)
          (doc.data()['uid'] ?? doc.id).toString(): doc.data(),
      };

      final uids = _rosterByUid.keys.where((id) => id.isNotEmpty).toList();

      if (mounted) setState(() => _loadingRoster = false);

      if (uids.isEmpty) return; // empty state handles this

      // Firestore `whereIn` supports up to 30 values — chunk the roster
      // and merge the resulting streams so this still works for large
      // classes. Matching by uid (not roll_no) avoids any field-name or
      // formatting mismatch between collections.
      const chunkSize = 30;
      for (var i = 0; i < uids.length; i += chunkSize) {
        final chunk = uids.sublist(
          i,
          i + chunkSize > uids.length ? uids.length : i + chunkSize,
        );

        final sub = FirebaseFirestore.instance
            .collection('fee_receipts')
            .where('studentId', whereIn: chunk)
            .snapshots()
            .listen(
              _onReceiptsSnapshot,
              onError: (Object error) {
                debugPrint('fee_receipts listener ERROR: $error');
                if (mounted) {
                  setState(
                    () => _rosterError =
                        'Could not load receipts for this class: $error',
                  );
                }
              },
            );
        _subscriptions.add(sub);
      }
    } catch (e) {
      debugPrint('Class roster loading error: $e');
      if (mounted) {
        setState(() {
          _loadingRoster = false;
          _rosterError = 'Could not load the class roster: $e';
        });
      }
    }
  }

  void _onReceiptsSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final change in snap.docChanges) {
      final uid = change.doc.data()?['studentId']?.toString();
      final student = uid != null ? _rosterByUid[uid] : null;

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
                  child: _rosterByUid.isEmpty
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

  /// Challans are generated into `student_challans` (see
  /// GenerateChallanScreen), not the older `challans` collection this used
  /// to point at. Tries the stored `challanId` first (when the upload flow
  /// managed to attach one), then falls back to the student's most recent
  /// challan by uid — so this card still shows something useful even when
  /// the receipt's own `challanId` link is missing.
  Future<void> _loadChallan() async {
    try {
      final challanId = widget.item.challanId;
      DocumentSnapshot<Map<String, dynamic>>? doc;

      if (challanId != null && challanId.isNotEmpty) {
        final byId = await FirebaseFirestore.instance
            .collection('student_challans')
            .doc(challanId)
            .get();
        if (byId.exists) doc = byId;
      }

      final studentUid = widget.item.studentUid;
      if (doc == null && studentUid.isNotEmpty) {
        final snap = await FirebaseFirestore.instance
            .collection('student_challans')
            .where('studentId', isEqualTo: studentUid)
            .orderBy('createdAt', descending: true)
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) doc = snap.docs.first;
      }

      if (doc != null && doc.exists) _challanData = doc.data();
    } catch (e) {
      debugPrint('Challan loading error: $e');
      // Non-fatal — challan info is supplementary here.
    } finally {
      if (mounted) setState(() => _loadingChallan = false);
    }
  }

  Future<void> _updateStatus() async {
    setState(() => _saving = true);
    try {
      // 1. Firestore mein receipt ka status update karein
      await FirebaseFirestore.instance
          .collection('fee_receipts')
          .doc(widget.item.docId)
          .update({
            'status': _selectedStatus,
            'adminRemarks': _remarksController.text.trim(),
          });

      // 2. [NEW STEP] Student ko Push Notification bhejein
      try {
        String notificationTitle = 'Fee Receipt Update';
        String notificationBody =
            'Your fee receipt status has been updated to $_selectedStatus.';

        if (_selectedStatus == 'Paid') {
          notificationTitle = 'Fee Verified! 🎉';
          notificationBody =
              'Your fee payment has been successfully verified and accepted.';
        } else if (_selectedStatus == 'Rejected') {
          notificationTitle = 'Fee Receipt Rejected ';
          notificationBody =
              'Your fee receipt was rejected. Check remarks for details.';
        }

        await NotificationService.sendPushToUser(
          targetUserId: widget.item.studentUid, // Student ki unique UID
          title: notificationTitle,
          body: notificationBody,
          notificationType: 'receipt_update',
          relatedId: widget.item.docId,
        );
      } catch (notificationError) {
        debugPrint('NOTIFICATION ERROR: $notificationError');
        // Notification fail hone par bhi status update nahi rukega
      }

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
        SnackBar(
          content: Text('Could not update the status: $e'),
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
                _infoRow(Icons.class_, 'Class', item.studentClass),
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
                        (_challanData?['challanNo'] ?? item.challanId ?? '—')
                            .toString(),
                      ),
                      if (_challanData?['totalAmount'] != null)
                        _infoRow(
                          Icons.payments,
                          'Amount',
                          'Rs. ${_challanData?['totalAmount']}',
                        ),
                      if (_challanData?['dueDate'] != null)
                        _infoRow(
                          Icons.event,
                          'Due Date',
                          _challanData!['dueDate'].toString(),
                        ),
                      if (_challanData?['month'] != null)
                        _infoRow(
                          Icons.calendar_month,
                          'Fee Month',
                          _challanData!['month'].toString(),
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
