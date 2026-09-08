import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';

class StudentHomeworkListScreen extends StatefulWidget {
  const StudentHomeworkListScreen({super.key});

  @override
  State<StudentHomeworkListScreen> createState() =>
      _StudentHomeworkListScreenState();
}

class _StudentHomeworkListScreenState extends State<StudentHomeworkListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // ------------------------------------------------------------
  // READ DIARY IDS
  // ------------------------------------------------------------
  Set<String> _readDiaryIds = {};

  @override
  void initState() {
    super.initState();
    _loadReadDiaries();
  }

  // ------------------------------------------------------------
  // LOAD DIARIES ALREADY READ BY CURRENT STUDENT
  // ------------------------------------------------------------
  Future<void> _loadReadDiaries() async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('diary_reads')
          .where('studentId', isEqualTo: user.uid)
          .get();

      if (!mounted) return;

      setState(() {
        _readDiaryIds = snapshot.docs
            .map((doc) => doc['diaryId'].toString())
            .toSet();
      });
    } catch (e) {
      debugPrint('Error loading read diaries: $e');
    }
  }

  // ------------------------------------------------------------
  // MARK DIARY AS READ
  // ------------------------------------------------------------
  Future<void> _markDiaryAsRead(String diaryId) async {
    final user = FirebaseAuth.instance.currentUser;

    if (user == null || diaryId.isEmpty) return;

    // Already read
    if (_readDiaryIds.contains(diaryId)) return;

    try {
      await FirebaseFirestore.instance
          .collection('diary_reads')
          .doc('${user.uid}_$diaryId')
          .set({
            'studentId': user.uid,
            'diaryId': diaryId,
            'readAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      setState(() {
        _readDiaryIds.add(diaryId);
      });
    } catch (e) {
      debugPrint('Error marking diary as read: $e');
    }
  }

  // ------------------------------------------------------------
  // VIEW IMAGE
  // ------------------------------------------------------------
  void _viewImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
          ),
          backgroundColor: Colors.black,
          body: Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(
                imageUrl,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 60,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // SHOW DIARY DETAILS
  // ------------------------------------------------------------
  void _showHomeworkDetails(BuildContext context, Map<String, dynamic> data) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HomeworkDetailScreen(data: data)),
    );
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),

      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,

        title: const Text(
          "Class Diary",
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),

        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF16304E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),

      body: Column(
        children: [
          // ----------------------------------------------------
          // SEARCH
          // ----------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.05),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),

              child: TextField(
                controller: _searchController,

                onChanged: (value) {
                  setState(() {
                    _searchQuery = value.toLowerCase();
                  });
                },

                decoration: InputDecoration(
                  hintText: "Search diary...",

                  hintStyle: TextStyle(color: Colors.grey.shade500),

                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF1E3A5F),
                  ),

                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _searchController.clear();

                            setState(() {
                              _searchQuery = "";
                            });
                          },
                        )
                      : null,

                  filled: true,
                  fillColor: Colors.white,

                  contentPadding: const EdgeInsets.symmetric(vertical: 16),

                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),

                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),

                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(
                      color: Color(0xFF1E3A5F),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ----------------------------------------------------
          // DIARY LIST
          // ----------------------------------------------------
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('homework')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),

              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Text(
                      "Something went wrong.\n${snapshot.error}",
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text("No diary available."));
                }

                // ------------------------------------------------
                // FILTER
                // ------------------------------------------------
                var filteredDocs = snapshot.data!.docs.where((doc) {
                  var data = doc.data() as Map<String, dynamic>;

                  final title = (data['title'] ?? "").toString().toLowerCase();

                  final description = (data['description'] ?? "")
                      .toString()
                      .toLowerCase();

                  return title.contains(_searchQuery) ||
                      description.contains(_searchQuery);
                }).toList();

                if (filteredDocs.isEmpty) {
                  return const Center(child: Text("No diary found."));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),

                  itemCount: filteredDocs.length,

                  itemBuilder: (context, index) {
                    final doc = filteredDocs[index];

                    var data = doc.data() as Map<String, dynamic>;

                    // Firestore document ID internally add
                    data['id'] = doc.id;

                    return _buildHomeworkCard(context, data);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // DIARY CARD
  // ------------------------------------------------------------
  Widget _buildHomeworkCard(BuildContext context, Map<String, dynamic> data) {
    final String diaryId = data['id']?.toString() ?? "";

    final bool isUnread = !_readDiaryIds.contains(diaryId);

    // Automatic posted date
    DateTime postedDate = DateTime.now();

    if (data['timestamp'] is Timestamp) {
      postedDate = (data['timestamp'] as Timestamp).toDate();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),

      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),

        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),

      child: InkWell(
        borderRadius: BorderRadius.circular(16),

        onTap: () async {
          // ----------------------------------------------
          // MARK AS READ FIRST
          // ----------------------------------------------
          await _markDiaryAsRead(diaryId);

          // ----------------------------------------------
          // THEN OPEN DETAILS
          // ----------------------------------------------
          if (!context.mounted) return;

          _showHomeworkDetails(context, data);
        },

        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),

              child: Row(
                children: [
                  // ------------------------------------------
                  // ICON
                  // ------------------------------------------
                  Container(
                    height: 50,
                    width: 50,

                    decoration: BoxDecoration(
                      color: const Color(0xFF1E3A5F).withOpacity(.08),

                      borderRadius: BorderRadius.circular(12),
                    ),

                    child: const Icon(
                      Icons.menu_book_outlined,
                      color: Color(0xFF1E3A5F),
                    ),
                  ),

                  const SizedBox(width: 14),

                  // ------------------------------------------
                  // CONTENT
                  // ------------------------------------------
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,

                      children: [
                        // TITLE
                        Text(
                          data['title'] ?? "No Title",

                          maxLines: 1,

                          overflow: TextOverflow.ellipsis,

                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                          ),
                        ),

                        const SizedBox(height: 8),

                        // CLASS
                        Row(
                          children: [
                            const Icon(
                              Icons.class_outlined,
                              size: 15,
                              color: Colors.grey,
                            ),

                            const SizedBox(width: 5),

                            Expanded(
                              child: Text(
                                data['class'] ?? "N/A",

                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        // POSTED DATE
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 15,
                              color: Colors.grey,
                            ),

                            const SizedBox(width: 5),

                            Text(
                              DateFormat('dd MMM yyyy').format(postedDate),

                              style: TextStyle(
                                color: Colors.grey.shade700,

                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 10),

                  // ARROW
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 16,
                    color: Colors.grey.shade500,
                  ),
                ],
              ),
            ),

            // ------------------------------------------------
            // RED UNREAD DOT
            // ------------------------------------------------
            if (isUnread)
              Positioned(
                top: 10,
                right: 10,

                child: Container(
                  width: 11,
                  height: 11,

                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// HOMEWORK / DIARY DETAIL SCREEN
// ============================================================

class HomeworkDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const HomeworkDetailScreen({super.key, required this.data});

  // ------------------------------------------------------------
  // VIEW IMAGE
  // ------------------------------------------------------------
  void _viewImage(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: Colors.black,

            iconTheme: const IconThemeData(color: Colors.white),
          ),

          backgroundColor: Colors.black,

          body: Center(
            child: InteractiveViewer(
              panEnabled: true,

              boundaryMargin: const EdgeInsets.all(20),

              minScale: 0.5,
              maxScale: 4,

              child: Image.network(
                imageUrl,

                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.broken_image,
                    color: Colors.white,
                    size: 60,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    List<dynamic> attachments = data['attachments'] ?? [];

    DateTime? postedDate;

    if (data['timestamp'] is Timestamp) {
      postedDate = (data['timestamp'] as Timestamp).toDate();
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),

      appBar: AppBar(
        elevation: 0,
        centerTitle: true,

        backgroundColor: const Color(0xFF1E3A5F),

        foregroundColor: Colors.white,

        title: Text(
          data['title'] ?? 'Diary Detail',

          maxLines: 1,
          overflow: TextOverflow.ellipsis,

          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),

        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,

          children: [
            // --------------------------------------------------
            // CLASS
            // --------------------------------------------------
            Container(
              width: double.infinity,

              padding: const EdgeInsets.all(14),

              decoration: BoxDecoration(
                color: Colors.white,

                borderRadius: BorderRadius.circular(12),

                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(.04),

                    blurRadius: 6,

                    offset: const Offset(0, 2),
                  ),
                ],
              ),

              child: Row(
                children: [
                  const Icon(Icons.class_outlined, color: Color(0xFF1E3A5F)),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      "Class: ${data['class'] ?? 'N/A'}",

                      style: const TextStyle(
                        fontWeight: FontWeight.w600,

                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // --------------------------------------------------
            // POSTED DATE
            // --------------------------------------------------
            if (postedDate != null)
              Container(
                width: double.infinity,

                padding: const EdgeInsets.all(14),

                decoration: BoxDecoration(
                  color: Colors.white,

                  borderRadius: BorderRadius.circular(12),

                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.04),

                      blurRadius: 6,

                      offset: const Offset(0, 2),
                    ),
                  ],
                ),

                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,

                      color: Color(0xFF1E3A5F),
                    ),

                    const SizedBox(width: 10),

                    Expanded(
                      child: Text(
                        "Posted: ${DateFormat('dd MMM yyyy, hh:mm a').format(postedDate)}",

                        style: const TextStyle(
                          fontWeight: FontWeight.w600,

                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // DESCRIPTION
            // --------------------------------------------------
            const Text(
              "Description:",

              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),

            const SizedBox(height: 8),

            Text(
              data['description'] ?? "No description provided.",

              style: const TextStyle(fontSize: 15),
            ),

            const SizedBox(height: 20),

            // --------------------------------------------------
            // ATTACHMENTS
            // --------------------------------------------------
            if (attachments.isNotEmpty) ...[
              const Text(
                "Attachments:",

                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),

              const SizedBox(height: 10),

              Wrap(
                spacing: 10,
                runSpacing: 10,

                children: attachments.map((url) {
                  bool isPdf = url.toString().toLowerCase().contains(".pdf");

                  return InkWell(
                    onTap: () {
                      if (!isPdf) {
                        _viewImage(context, url.toString());
                      }
                    },

                    child: Container(
                      padding: const EdgeInsets.all(8),

                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,

                        borderRadius: BorderRadius.circular(8),

                        border: Border.all(color: Colors.blue.shade200),
                      ),

                      child: Column(
                        children: [
                          Icon(
                            isPdf ? Icons.picture_as_pdf : Icons.image,

                            color: isPdf ? Colors.red : Colors.blue,

                            size: 40,
                          ),

                          Text(
                            isPdf ? "PDF" : "View",

                            style: const TextStyle(fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
