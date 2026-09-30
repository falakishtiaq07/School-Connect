import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:school_connect/auth/forgot_password_screen.dart';
import 'package:school_connect/screens/admin_dashboard_screen.dart';
import 'package:school_connect/screens/student_dashboard_screen.dart';
import 'package:school_connect/screens/teacher_dashboard_screen.dart';
import 'package:school_connect/service/one_signal_service.dart';

class UserLoginScreen extends StatefulWidget {
  const UserLoginScreen({super.key});

  @override
  State<UserLoginScreen> createState() => _UserLoginScreenState();
}

class _UserLoginScreenState extends State<UserLoginScreen> {
  bool _isPasswordHidden = true;
  bool _isLoading = false;

  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            ClipPath(
              clipper: UserHeaderClipper(),
              child: Container(
                height: 260,
                width: double.infinity,
                color: const Color(0xFF1E3A5F),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(height: 30),
                    Icon(Icons.school_outlined, size: 65, color: Colors.white),
                    SizedBox(height: 12),
                    Text(
                      'SchoolConnect',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 35),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Email Address',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.email_outlined),
                      hintText: 'Enter Email Address',
                    ),
                  ),

                  const SizedBox(height: 20),

                  const Text(
                    'Password',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: passwordController,
                    obscureText: _isPasswordHidden,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      hintText: 'Enter Password',
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordHidden
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          setState(() {
                            _isPasswordHidden = !_isPasswordHidden;
                          });
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: 35),

                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: _isLoading
                          ? null
                          : () async {
                              String email = emailController.text.trim();
                              String password = passwordController.text.trim();

                              if (email.isEmpty || password.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please input your Email and Password',
                                    ),
                                    backgroundColor: Colors.orange,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                return;
                              }

                              setState(() {
                                _isLoading = true;
                              });

                              try {
                                final credential = await FirebaseAuth.instance
                                    .signInWithEmailAndPassword(
                                      email: email,
                                      password: password,
                                    );

                                final User? loggedInUser = credential.user;
                                if (loggedInUser == null) {
                                  if (!mounted) return;
                                  setState(() => _isLoading = false);
                                  return;
                                }

                                await loggedInUser.reload();
                                final User? refreshedUser =
                                    FirebaseAuth.instance.currentUser;

                                if (refreshedUser == null) {
                                  if (!mounted) return;
                                  setState(() => _isLoading = false);
                                  return;
                                }

                                if (!refreshedUser.emailVerified) {
                                  try {
                                    await refreshedUser.sendEmailVerification();
                                  } catch (e) {
                                    debugPrint("Verification email error: $e");
                                  }

                                  await FirebaseAuth.instance.signOut();
                                  if (!mounted) return;
                                  setState(() => _isLoading = false);

                                  showDialog(
                                    context: context,
                                    builder: (context) {
                                      return AlertDialog(
                                        title: const Text("Email Not Verified"),
                                        content: Text(
                                          "Your email has not been verified yet.\n\nA verification link has been sent to:\n$email\n\nPlease verify and login again.",
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context),
                                            child: const Text("OK"),
                                          ),
                                        ],
                                      );
                                    },
                                  );
                                  return;
                                }
                                if (refreshedUser.emailVerified) {
                                  try {
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(loggedInUser.uid)
                                        .update({'isVerified': true});
                                  } catch (e) {
                                    debugPrint(
                                      "Failed to update isVerified in Firestore: $e",
                                    );
                                  }
                                }
                                String uid = loggedInUser.uid;
                                debugPrint("Login UID: $uid");
                                DocumentSnapshot userDoc =
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .get();

                                if (!userDoc.exists) {
                                  await FirebaseAuth.instance.signOut();
                                  if (!mounted) return;
                                  setState(() => _isLoading = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'User record not found in database.',
                                      ),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }

                                final data =
                                    userDoc.data() as Map<String, dynamic>?;
                                if (data == null || !data.containsKey('role')) {
                                  await FirebaseAuth.instance.signOut();
                                  if (!mounted) return;
                                  setState(() => _isLoading = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Access Denied: User role is not defined.',
                                      ),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                  return;
                                }

                                String userRole = data['role']
                                    .toString()
                                    .toLowerCase()
                                    .trim();
                                String? studentClass;
                                if (userRole == 'student' &&
                                    data.containsKey('class')) {
                                  studentClass = data['class']?.toString();
                                }

                                try {
                                  await OneSignalService.setupOneSignal(
                                    uid,
                                    userRole,
                                    studentClass: studentClass,
                                    forceRefresh: true,
                                  );
                                } catch (e) {
                                  debugPrint('OneSignal setup error: $e');
                                }

                                if (!mounted) return;
                                setState(() => _isLoading = false);

                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Login Successful!'),
                                    backgroundColor: Colors.green,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );

                                if (!mounted) return;
                                if (userRole == 'admin') {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminDashboardScreen(),
                                    ),
                                  );
                                } else if (userRole == 'teacher') {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const TeacherDashboardScreen(),
                                    ),
                                  );
                                } else if (userRole == 'student') {
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const StudentDashboardScreen(),
                                    ),
                                  );
                                } else {
                                  await FirebaseAuth.instance.signOut();
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Access Denied: Role not recognized.',
                                      ),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } on FirebaseAuthException catch (e) {
                                if (!mounted) return;
                                setState(() => _isLoading = false);
                                String errorMessage =
                                    'An error occurred. Please try again.';
                                if (e.code == 'user-not-found' ||
                                    e.code == 'invalid-credential' ||
                                    e.code == 'wrong-password') {
                                  errorMessage = 'Incorrect email or password.';
                                } else if (e.code == 'invalid-email') {
                                  errorMessage =
                                      'The email address is badly formatted.';
                                } else if (e.code == 'network-request-failed') {
                                  errorMessage = 'No internet connection.';
                                }

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(errorMessage),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                setState(() => _isLoading = false);
                              }
                            },
                      child: _isLoading
                          ? const SizedBox(
                              height: 24,
                              width: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text(
                              'LOG IN',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerRight,
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const ForgotPasswordScreen(userRole: 'user'),
                          ),
                        );
                      },
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class UserHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 50);

    var controlPoint = Offset(size.width / 2, size.height + 15);
    var endPoint = Offset(size.width, size.height - 50);

    path.quadraticBezierTo(
      controlPoint.dx,
      controlPoint.dy,
      endPoint.dx,
      endPoint.dy,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
