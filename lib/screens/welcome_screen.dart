import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

import 'login_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const Color primaryBlue = Color(0xFF1746A2);
  static const Color lightGreen = Color(0xFF8BE3B3);

  @override
  Widget build(BuildContext context) {
    final double screenWidth = MediaQuery.of(context).size.width;

    // Responsive Width

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: SizedBox(
              width: double.infinity,
              child: Column(
                children: [
                  // ================= TOP SECTION =================
                  // === TOP SECTION (SIRF AIK DAFA RAKHEIN) ===
                  Stack(
                    alignment: Alignment.topCenter,
                    clipBehavior: Clip.none,
                    children: [
                      // 1. Blue Background
                      Container(
                        height: 250,
                        width: double.infinity,
                        color: const Color(0xFF1E3A5F),
                      ),

                      // 2. White Curve
                      Positioned.fill(
                        top: 160,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(160),
                            ),
                          ),
                        ),
                      ),

                      // 3. Main Content (Welcome Text & Cap Icon - NO DUPLICATE)
                      Positioned(
                        top: 30,
                        left: 0,
                        right: 0,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Welcome to SchoolConnect',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w500,
                                fontFamily: 'Roboto',
                              ),
                            ),
                            const SizedBox(height: 0),
                            const Icon(
                              Icons.school_outlined,
                              size: 120,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // --- SCHOOL IMAGE AREA ---
                  const SizedBox(height: 10),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    child: Image.asset(
                      'assets/school.png',
                      width: double.infinity,
                      height: 260,
                      fit: BoxFit.fill,
                    ),
                  ),

                  const SizedBox(height: 35),
                  // ================= ADMIN LOGIN BUTTON =================
                  InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const UserLoginScreen(),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(40),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Container(
                        height: 75,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E3A5F),
                          borderRadius: BorderRadius.circular(40),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 25),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.login_rounded,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                'Log In',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),
                  // ================= FOOTER =================
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    color: const Color.fromARGB(255, 181, 190, 201),
                    child: const Center(
                      child: Text(
                        'Connecting Education, Building Futures',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.black87,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
