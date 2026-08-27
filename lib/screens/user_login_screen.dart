import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:school_connect/auth/forgot_password_screen.dart';
import 'package:school_connect/screens/student_dashboard_screen.dart';
import 'package:school_connect/screens/teacher_dashboard_screen.dart';
//import 'package:school_connect/auth/otp_verification_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class UserLoginScreen extends StatefulWidget {
  const UserLoginScreen({super.key});

  @override
  State<UserLoginScreen> createState() => _UserLoginScreenState();
}

class _UserLoginScreenState extends State<UserLoginScreen> {
  // Password hide/unhide karne ke liye variable
  bool _isPasswordHidden = true;

  // Controllers taake text fields ka data get kiya ja sakay
  final TextEditingController usernameController = TextEditingController();
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  @override
  void dispose() {
    usernameController.dispose();
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
            // --- TOP CURVED HEADER WITH SCHOOL ICON ---
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
                    // School Building Icon
                    Icon(Icons.school_outlined, size: 65, color: Colors.white),
                    SizedBox(height: 12),
                    // App Name
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

            // --- INPUT FIELDS & BUTTONS SECTION ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Username Field
                  const Text(
                    'Name',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: usernameController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person_outline),
                      hintText: 'Enter Name',
                    ),
                  ),

                  const SizedBox(height: 20),

                  // 2. Email Address Field
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

                  // 3. Password Field with Eye Button
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

                  // 4. Main Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F), // Navy Theme
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () async {
                        String username = usernameController.text.trim();
                        String email = emailController.text.trim();
                        String password = passwordController.text.trim();

                        if (username.isEmpty ||
                            email.isEmpty ||
                            password.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please input your data (Name, Email and Password)',
                              ),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        // 🌟 SECURE REAL FIREBASE USER LOGIN
                        try {
                          final credential = await FirebaseAuth.instance
                              .signInWithEmailAndPassword(
                                email: email,
                                password: password,
                              );

                          final User? loggedInUser = credential.user;

                          if (loggedInUser == null) {
                            return;
                          }

                          // Firebase se latest verification status lao
                          await loggedInUser.reload();

                          final User? refreshedUser =
                              FirebaseAuth.instance.currentUser;

                          if (refreshedUser == null) {
                            return;
                          }
                          // Agar email verify nahi hui
                          if (!refreshedUser.emailVerified) {
                            // Verification email dobara bhej do
                            try {
                              await refreshedUser.sendEmailVerification();
                            } catch (e) {
                              print("Verification email resend error: $e");
                            }

                            // User ko logout karo
                            await FirebaseAuth.instance.signOut();

                            if (context.mounted) {
                              showDialog(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: const Text("Email Not Verified"),
                                    content: Text(
                                      "Your email has not been verified yet.\n\n"
                                      "A verification email has been sent to:\n"
                                      "$email\n\n"
                                      "Please open your email, click the verification link, "
                                      "and then login again.",
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () {
                                          Navigator.pop(context);
                                        },
                                        child: const Text("OK"),
                                      ),
                                    ],
                                  );
                                },
                              );
                            }

                            return;
                          }
                          
                          String? uid = credential.user?.uid;

                          if (uid != null) {
                            DocumentSnapshot userDoc = await FirebaseFirestore
                                .instance
                                .collection('users')
                                .doc(uid)
                                .get();

                            if (userDoc.exists) {
                              String userRole = userDoc
                                  .get('role')
                                  .toString()
                                  .toLowerCase()
                                  .trim();

                              print("USER ROLE IS: $userRole");

                              await OneSignal.login(uid);
                              await OneSignal.User.addTagWithKey(
                                "role",
                                userRole,
                              );
                              if (userRole == 'student') {
                                String studentClass = userDoc
                                    .get('class')
                                    .toString(); // ya jo bhi field name ho
                                await OneSignal.User.addTagWithKey(
                                  "class",
                                  studentClass,
                                );
                              }

                              // 1. Check: Agar Admin user screen se login karne aaye (Strictly Block)
                              if (userRole == 'admin') {
                                await FirebaseAuth.instance.signOut();

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Error: Admins cannot login from the User Screen!',
                                      ),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                              // ✅ 2. Agar sab sahi hai (Yahan Role Check karega)
                              else {
                                if (context.mounted) {
                                  // Pehle Success message dikhayen
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('User Login Successful!'),
                                      backgroundColor: Colors.green,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );

                                  // FCM TOKEN SAVE
                                  // 👩‍🏫 AGAR TEACHER HAI TO TEACHER DASHBOARD
                                  if (userRole == 'teacher') {
                                    if (context.mounted) {
                                      // <-- Yeh check zaroor add karein
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const TeacherDashboardScreen(),
                                        ),
                                      );
                                    }
                                  }
                                  // 🎓 AGAR STUDENT HAI TO STUDENT DASHBOARD
                                  else if (userRole == 'student') {
                                    if (context.mounted) {
                                      // <-- Yeh check yahan bhi add karein
                                      Navigator.pushReplacement(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) =>
                                              const StudentDashboardScreen(),
                                        ),
                                      );
                                    }
                                  }
                                  // Agar Firestore me role recognize na ho
                                  else {
                                    await FirebaseAuth.instance.signOut();
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
                                }
                              }
                            } else {
                              // Document database mein na mile
                              await FirebaseAuth.instance.signOut();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Incorrect username, email or password.',
                                    ),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          }
                        } on FirebaseAuthException catch (e) {
                          String errorMessage =
                              'An error occurred. Please try again.';

                          if (e.code == 'user-not-found' ||
                              e.code == 'invalid-credential' ||
                              e.code == 'wrong-password') {
                            errorMessage =
                                'Incorrect username, email or password.';
                          } else if (e.code == 'invalid-email') {
                            errorMessage =
                                'The email address is badly formatted.';
                          } else if (e.code == 'network-request-failed') {
                            errorMessage = 'No internet connection.';
                          }

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(errorMessage),
                                backgroundColor: Colors.red,
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          }
                        } catch (e) {
                          print(e.toString());
                        }
                      },
                      child: const Text(
                        'LOGIN AS USER',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Forgot Password Link for User (Teacher/Student) - Right Aligned
                  Align(
                    alignment: Alignment
                        .centerRight, // Is se text right side par hi rahe ga
                    child: GestureDetector(
                      onTap: () {
                        // Ab yeh direct OTP Verification Screen par le kar jaye ga
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const ForgotPasswordScreen(
                              userRole:
                                  'user', // Role humne 'user' pass kar diya
                              // Yahan aap khali string "" ya koi default text de sakti hain
                            ),
                          ),
                        );
                      },
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Color(
                            0xFF1D4ED8,
                          ), // Same professional blue color
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          decoration: TextDecoration
                              .underline, // Text ke niche line ke liye
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30), // Spacing ke liye
                  // Back Option to go to Welcome Screen
                  Center(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        'Go Back',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Custom Clipper jo header ko exact image jaisa smooth wave cut deta hai
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
