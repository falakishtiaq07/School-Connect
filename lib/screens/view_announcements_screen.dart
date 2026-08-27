import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ViewAnnouncementsScreen extends StatefulWidget {
  const ViewAnnouncementsScreen({super.key});

  @override
  State<ViewAnnouncementsScreen> createState() =>
      _ViewAnnouncementsScreenState();
}

class _ViewAnnouncementsScreenState extends State<ViewAnnouncementsScreen> {
  String userRole = '';
  bool isLoading = true;
  bool isSelectionMode = false;
  Set<String> selectedIds = {};

  @override
  void initState() {
    super.initState();
    loadUserRole();
  }

  Future<void> loadUserRole() async {
    try {
      String uid = FirebaseAuth.instance.currentUser!.uid;
      DocumentSnapshot userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      if (userDoc.exists) {
        setState(() {
          userRole = (userDoc.data() as Map<String, dynamic>)['role']
              .toString()
              .toLowerCase();
          isLoading = false;
        });
      }
    } catch (e) {
      setState(() => isLoading = false);
    }
  }

  Future<void> deleteSelectedAnnouncements() async {
    // 1. Pehle Confirmation Dialog dikhayein
    bool? confirm = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Confirm Delete"),
        content: Text(
          "Are you sure you want to delete ${selectedIds.length} announcements?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false), // Cancel
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(context, true), // Delete
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    // 2. Agar user ne 'Delete' click kiya (confirm == true), tabhi delete karein
    if (confirm == true) {
      for (String id in selectedIds) {
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(id)
            .delete();
      }
      setState(() {
        isSelectionMode = false;
        selectedIds.clear();
      });

      // Optional: Success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Selected announcements deleted successfully"),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FB),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF1E3A5F)),
              SizedBox(height: 18),
              Text(
                "Loading announcements...",
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Query announcementsQuery;
    if (userRole == 'student') {
      announcementsQuery = FirebaseFirestore.instance
          .collection('announcements')
          .where('students', isEqualTo: true)
          .orderBy('createdAt', descending: true);
    } else if (userRole == 'teacher') {
      announcementsQuery = FirebaseFirestore.instance
          .collection('announcements')
          .where('teachers', isEqualTo: true)
          .orderBy('createdAt', descending: true);
    } else {
      announcementsQuery = FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('createdAt', descending: true);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 70,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,

        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Announcements",
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1300),
            child: Column(
              children: [
                // Select Button area
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
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
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        bool mobile = constraints.maxWidth < 550;

                        if (mobile) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (!isSelectionMode)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1E3A5F),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  icon: const Icon(Icons.select_all),
                                  label: const Text("Select Announcements"),
                                  onPressed: () =>
                                      setState(() => isSelectionMode = true),
                                ),

                              if (isSelectionMode) ...[
                                Text(
                                  "${selectedIds.length} Selected",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),

                                const SizedBox(height: 15),

                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red,
                                          foregroundColor: Colors.white,
                                        ),
                                        icon: const Icon(Icons.delete),
                                        label: const Text("Delete"),
                                        onPressed: selectedIds.isEmpty
                                            ? null
                                            : deleteSelectedAnnouncements,
                                      ),
                                    ),

                                    const SizedBox(width: 10),

                                    Expanded(
                                      child: OutlinedButton.icon(
                                        icon: const Icon(Icons.close),
                                        label: const Text("Cancel"),
                                        onPressed: () {
                                          setState(() {
                                            isSelectionMode = false;
                                            selectedIds.clear();
                                          });
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          );
                        }

                        return Row(
                          children: [
                            Expanded(
                              child: Text(
                                isSelectionMode
                                    ? "${selectedIds.length} announcement(s) selected"
                                    : "School Announcements",
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),

                            if (!isSelectionMode)
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1E3A5F),
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.select_all),
                                label: const Text("Select"),
                                onPressed: () =>
                                    setState(() => isSelectionMode = true),
                              ),

                            if (isSelectionMode) ...[
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                icon: const Icon(Icons.delete),
                                label: const Text("Delete"),
                                onPressed: selectedIds.isEmpty
                                    ? null
                                    : deleteSelectedAnnouncements,
                              ),

                              const SizedBox(width: 10),

                              OutlinedButton.icon(
                                icon: const Icon(Icons.close),
                                label: const Text("Cancel"),
                                onPressed: () {
                                  setState(() {
                                    isSelectionMode = false;
                                    selectedIds.clear();
                                  });
                                },
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // List area
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: announcementsQuery.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text("No announcements available"),
                        );
                      }

                      final announcements = snapshot.data!.docs;
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: announcements.length,
                        itemBuilder: (context, index) {
                          final doc = announcements[index];
                          final String id = doc.id;
                          final data = doc.data() as Map<String, dynamic>;
                          final bool isSelected = selectedIds.contains(id);
                          Timestamp? timestamp =
                              data['createdAt'] as Timestamp?;
                          DateTime date = timestamp?.toDate() ?? DateTime.now();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFEAF2FF)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF1E3A5F)
                                    : Colors.grey.shade200,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(.05),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () {
                                if (isSelectionMode) {
                                  setState(() {
                                    if (isSelected) {
                                      selectedIds.remove(id);
                                    } else {
                                      selectedIds.add(id);
                                    }
                                  });
                                } else {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          AnnouncementDetailScreen(data: data),
                                    ),
                                  );
                                }
                              },

                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (isSelectionMode)
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (value) {
                                          setState(() {
                                            if (value == true) {
                                              selectedIds.add(id);
                                            } else {
                                              selectedIds.remove(id);
                                            }
                                          });
                                        },
                                      )
                                    else
                                      Container(
                                        height: 52,
                                        width: 52,
                                        decoration: BoxDecoration(
                                          color: const Color(
                                            0xFF1E3A5F,
                                          ).withOpacity(.08),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.campaign_rounded,
                                          color: Color(0xFF1E3A5F),
                                        ),
                                      ),

                                    const SizedBox(width: 16),

                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            data['title'] ?? "No Title",
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 17,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),

                                          const SizedBox(height: 10),

                                          Text(
                                            data['description'] ?? "",
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Colors.grey.shade700,
                                              height: 1.4,
                                            ),
                                          ),

                                          const SizedBox(height: 12),

                                          Row(
                                            children: [
                                              Icon(
                                                Icons.calendar_today_outlined,
                                                size: 15,
                                                color: Colors.grey.shade600,
                                              ),

                                              const SizedBox(width: 6),

                                              Expanded(
                                                child: Text(
                                                  "${date.day}/${date.month}/${date.year}",
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: Colors.grey.shade600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    if (!isSelectionMode)
                                      const Padding(
                                        padding: EdgeInsets.only(left: 10),
                                        child: Icon(
                                          Icons.arrow_forward_ios_rounded,
                                          size: 18,
                                          color: Colors.grey,
                                        ),
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
            ),
          ),
        ),
      ),
    );
  }
}

class FullScreenImagePage extends StatelessWidget {
  final String imageUrl;

  const FullScreenImagePage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;

              return const Center(
                child: CircularProgressIndicator(color: Colors.white),
              );
            },
          ),
        ),
      ),
    );
  }
}

class AnnouncementDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;

  const AnnouncementDetailScreen({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    Timestamp? timestamp = data['createdAt'] as Timestamp?;
    DateTime date = timestamp?.toDate() ?? DateTime.now();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        title: const Text(
          "Announcement Details",
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            /// Title Value
            Text(
              data['title'] ?? "No Title",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),

            const SizedBox(height: 10),

            /// Date
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 6),
                Text(
                  "${date.day}/${date.month}/${date.year}",
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
              ],
            ),

            const SizedBox(height: 25),

            /// Description
            const Text(
              "Description",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1746A2),
              ),
            ),

            const SizedBox(height: 8),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F7FB),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                data['description'] ?? "No description",
                style: const TextStyle(fontSize: 14, height: 1.6),
              ),
            ),

            const SizedBox(height: 22),

            /// Attachment
            if (data['attachment'] != null &&
                data['attachment'].toString().trim().isNotEmpty) ...[
              const Text(
                "Attachment",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1746A2),
                ),
              ),

              const SizedBox(height: 10),

              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          FullScreenImagePage(imageUrl: data['attachment']),
                    ),
                  );
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    data['attachment'],
                    width: 180,
                    height: 120,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                "Tap to view",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
