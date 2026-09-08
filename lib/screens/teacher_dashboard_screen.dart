import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:school_connect/screens/attendance_screen.dart';
import 'package:school_connect/screens/monthly_reports_screen.dart';
import 'package:school_connect/screens/view_announcements_screen.dart';
import 'package:school_connect/screens/welcome_screen.dart';
import 'package:school_connect/screens/teacher_profile_screen.dart';
import 'package:school_connect/screens/list_of_students_screen.dart';
import 'package:school_connect/screens/manage_leave_screen.dart';
import 'package:school_connect/screens/post_homework_screen.dart';
import 'package:school_connect/service/one_signal_service.dart';
import 'package:school_connect/service/unread_status_service.dart';

class TeacherDashboardScreen extends StatefulWidget {
  const TeacherDashboardScreen({super.key});

  @override
  State<TeacherDashboardScreen> createState() => _TeacherDashboardScreenState();
}

class _TeacherDashboardScreenState extends State<TeacherDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _navy = Color(0xFF1E3A5F);
  static const _bg = Color(0xFFF0F4F8);
  static const _white = Colors.white;

  // ── Dynamic data — fetched from Firestore ───────────────────────────────
  String _userName = 'Loading...';
  String _userClass = 'Loading...';

  // ── Unread Status ───────────────────────────────────────────────────────
  Map<String, bool> _unreadStatus = {'announcements': false, 'leaves': false};

  @override
  void initState() {
    super.initState();
    fetchTeacherData();
    _loadUnreadStatus();
  }

  // ── Fetch Teacher Data ───────────────────────────────────────────────────
  Future<void> fetchTeacherData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>;

          if (mounted) {
            setState(() {
              _userName = data['name'] ?? 'Teacher';
              _userClass = data.containsKey('class')
                  ? data['class'].toString()
                  : 'No Class Assigned';
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching data: $e');
    }
  }

  // ── Load Unread Status ──────────────────────────────────────────────────
  Future<void> _loadUnreadStatus() async {
    try {
      final status = await UnreadService.getUnreadStatus();

      if (!mounted) return;

      setState(() {
        _unreadStatus = status;
      });
    } catch (e) {
      debugPrint('Error loading teacher unread status: $e');
    }
  }

  // ── Logout ───────────────────────────────────────────────────────────────
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text(
          'Logout',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await OneSignalService.logout();
                await FirebaseAuth.instance.signOut();

                if (!ctx.mounted) return;

                Navigator.pushAndRemoveUntil(
                  ctx,
                  MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                );
              } catch (e) {
                debugPrint('Logout Error: $e');

                if (ctx.mounted) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(
                      content: Text('Logout failed. Please try again.'),
                      backgroundColor: Colors.red,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // ── Cards list ──────────────────────────────────────────────────────────
  List<_CardData> _cards(BuildContext context) => [
    _CardData(
      icon: Icons.check_circle_outline,
      title: 'Attendance',
      description: 'Mark daily attendance for class $_userClass.',
      buttonText: 'Mark Attendance',
      onPressed: () {
        if (_userClass == 'Loading...' || _userClass == 'No Class Assigned') {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Class data not ready yet!')),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AttendanceManagementScreen(teacherClass: _userClass),
            ),
          );
        }
      },
    ),

    // ── Manage Leaves ───────────────────────────────────────────────
    _CardData(
      icon: Icons.calendar_month_outlined,
      title: 'Manage Leaves',
      description: 'View, accept or reject student leave requests.',
      buttonText: 'View Requests',
      hasUnread: _unreadStatus['leaves'] ?? false,
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ManageLeavePage()),
        );

        // Refresh after returning
        await _loadUnreadStatus();
      },
    ),

    // ── Announcements ───────────────────────────────────────────────
    _CardData(
      icon: Icons.campaign_outlined,
      title: 'School Announcements',
      description:
          'View notices, meetings, and updates from the administration.',
      buttonText: 'View Announcements',
      hasUnread: _unreadStatus['announcements'] ?? false,
      onPressed: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ViewAnnouncementsScreen()),
        );

        // Refresh after returning
        await _loadUnreadStatus();
      },
    ),

    _CardData(
      icon: Icons.assignment_outlined,
      title: 'Post Homework',
      description: 'Post daily class diary or homework for students.',
      buttonText: 'Post Homework',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HomeworkManagementScreen()),
        );
      },
    ),

    _CardData(
      icon: Icons.assessment_outlined,
      title: 'Monthly Reports',
      description: 'Create and send student progress reports.',
      buttonText: 'Upload Reports',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MonthlyReportsScreen()),
        );
      },
    ),

    _CardData(
      icon: Icons.group_outlined,
      title: 'My Students',
      description: 'View all students enrolled in your class.',
      buttonText: 'View Class',
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ListOfStudentsScreen(teacherClass: _userClass),
          ),
        );
      },
    ),
  ];

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth > 900;
    final isMobile = screenWidth <= 600;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildHeader(isMobile),
          Expanded(
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isDesktop ? 32 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),

                    // ── Title + class badge ─────────────────────────────
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'Overview',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF6B7280),
                                  letterSpacing: 0.8,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Teacher Dashboard',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1F2937),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Class badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: _navy.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: _navy.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.class_outlined,
                                color: _navy,
                                size: 13,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _userClass,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: _navy,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // ── Responsive cards ─────────────────────────────────
                    if (isMobile)
                      ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _cards(context).length,
                        itemBuilder: (_, i) => Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: _buildMobileCard(_cards(context)[i]),
                        ),
                      )
                    else
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: isDesktop ? 3 : 2,
                          crossAxisSpacing: 16,
                          mainAxisSpacing: 16,
                          childAspectRatio: isDesktop ? 1.35 : 1.4,
                        ),
                        itemCount: _cards(context).length,
                        itemBuilder: (_, i) =>
                            _buildGridCard(_cards(context)[i]),
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────────────────
  Widget _buildHeader(bool isMobile) {
    final statusBarHeight = MediaQuery.of(context).padding.top;

    final initial = _userName.isNotEmpty && _userName != 'Loading...'
        ? _userName[0].toUpperCase()
        : 'T';

    return Container(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: isMobile ? statusBarHeight + 8 : 0,
        bottom: isMobile ? 8 : 0,
      ),
      height: isMobile ? null : 64,
      decoration: BoxDecoration(
        color: _navy,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: isMobile
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.menu_rounded,
                          color: _white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: _white,
                        size: 15,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'SchoolConnect',
                        style: TextStyle(
                          color: _white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.3,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  constraints: const BoxConstraints(minHeight: 42),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            initial,
                            style: const TextStyle(
                              color: _white,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Welcome, $_userName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            )
          : Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    InkWell(
                      onTap: () => _scaffoldKey.currentState?.openDrawer(),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.menu_rounded,
                          color: _white,
                          size: 22,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.school_rounded,
                        color: _white,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'SchoolConnect',
                      style: TextStyle(
                        color: _white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'Welcome, $_userName',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withOpacity(0.3),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initial,
                          style: const TextStyle(
                            color: _white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  // ── Drawer ──────────────────────────────────────────────────────────────
  Widget _buildDrawer() {
    final initial = _userName.isNotEmpty && _userName != 'Loading...'
        ? _userName[0].toUpperCase()
        : 'T';

    return Drawer(
      backgroundColor: _white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 52, 20, 24),
            color: _navy,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: _white,
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _userName,
                  style: const TextStyle(
                    color: _white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Class: $_userClass',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _drawerItem(
            Icons.grid_view_rounded,
            'Dashboard',
            isSelected: true,
            onTap: () => Navigator.pop(context),
          ),
          _drawerItem(
            Icons.person_outline_rounded,
            'Profile',
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),
          const Spacer(),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          const SizedBox(height: 8),
          _drawerItem(
            Icons.logout_rounded,
            'Logout',
            isLogout: true,
            onTap: () {
              Navigator.pop(context);
              _showLogoutDialog(context);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _drawerItem(
    IconData icon,
    String title, {
    bool isSelected = false,
    bool isLogout = false,
    required VoidCallback onTap,
  }) {
    final color = isLogout
        ? Colors.red.shade600
        : (isSelected ? _navy : const Color(0xFF374151));

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? _navy.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        dense: true,
        onTap: onTap,
        leading: Icon(icon, color: color, size: 20),
        title: Text(
          title,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ── Grid card ───────────────────────────────────────────────────────────
  Widget _buildGridCard(_CardData card) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
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
            height: 4,
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        // existing icon container
                        child: Icon(
                          card.icon,
                          // existing styling
                        ),
                      ),

                      if (card.hasUnread)
                        Positioned(
                          right: -3,
                          top: -3,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    card.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1A2A3A),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Expanded(
                    child: Text(
                      card.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6B7280),
                        height: 1.6,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 36,
                    child: ElevatedButton(
                      onPressed: card.onPressed,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _navy,
                        foregroundColor: _white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.2,
                        ),
                      ),
                      child: Text(card.buttonText),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Mobile card ─────────────────────────────────────────────────────────
  Widget _buildMobileCard(_CardData card) {
    return Container(
      decoration: BoxDecoration(
        color: _white,
        borderRadius: BorderRadius.circular(16),
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
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 4,
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      // existing icon container
                      child: Icon(
                        card.icon,
                        // existing styling
                      ),
                    ),

                    if (card.hasUnread)
                      Positioned(
                        right: -3,
                        top: -3,
                        child: Container(
                          width: 12,
                          height: 12,
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
                        card.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1A2A3A),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        card.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 32,
                        child: ElevatedButton(
                          onPressed: card.onPressed,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: _white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            textStyle: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          child: Text(card.buttonText),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CARD DATA
// ═════════════════════════════════════════════════════════════════════════════

class _CardData {
  final IconData icon;
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onPressed;
  final bool hasUnread;

  _CardData({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onPressed,
    this.hasUnread = false,
  });
}
