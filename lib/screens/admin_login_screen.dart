import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:school_connect/auth/forgot_password_screen.dart';
import 'package:school_connect/screens/admin_dashboard_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  // 1. Ek variable banaya jo track rakhega ke password chhupana hai ya dikhana hai
  bool _isPasswordHidden = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // --- TOP CURVED CURTAIN BACKGROUND ---
            ClipPath(
              clipper: LoginHeaderClipper(),
              child: Container(
                height: 240,
                width: double.infinity,
                color: const Color(0xFF1E3A5F), // Global primary blue color
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),
                    const Text(
                      'Welcome to SchoolConnect',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 20,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Hello, Admin.',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 40),

            // --- INPUT FIELDS & LOGIN BUTTON ---
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Column(
                children: [
                  // Email Input Field
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.email_outlined),
                      hintText: 'Admin Email',
                      border: OutlineInputBorder(),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Password Input Field
                  TextField(
                    controller: passwordController,
                    obscureText:
                        _isPasswordHidden, // Variable text ko hide/show karega
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      hintText: 'Password',
                      border: const OutlineInputBorder(),
                      // 🌟 EYE ICON TOGGLE LOGIC:
                      suffixIcon: IconButton(
                        icon: Icon(
                          _isPasswordHidden
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () {
                          // Isse click karne par password hide/show hoga aur screen refresh hogi
                          setState(() {
                            _isPasswordHidden = !_isPasswordHidden;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Forgot Password Link// Forgot Password Link (Right Aligned)
                  Align(
                    alignment: Alignment
                        .centerRight, // Is se text right side par chala jaye ga
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ForgotPasswordScreen(userRole: 'admin'),
                          ),
                        );
                      },
                      child: const Text(
                        'Forgot Password?',
                        style: TextStyle(
                          color: Color(0xFF1D4ED8),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          decoration: TextDecoration
                              .underline, // Text ke niche line ke liye
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Login Button (ElevatedButton)
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1E3A5F),
                        foregroundColor: Colors.white, // Text color white
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(
                            12,
                          ), // Premium rounded corners
                        ),
                      ),
                      onPressed: () async {
                        // 1. Controllers se text uthayein aur extra spaces khatam (trim) karein
                        String email = emailController.text.trim();
                        String password = passwordController.text.trim();

                        // 2. Input Validation (Agar fields khali hon)
                        if (email.isEmpty || password.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please enter email and password'),
                              backgroundColor: Colors.orange,
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                          return;
                        }

                        // 3. 🌟 REAL FIREBASE LOGIN LOGIC WITH ROLE CHECK
                        try {
                          // Firebase auth ko call kr k sign in krwana
                          final credential = await FirebaseAuth.instance
                              .signInWithEmailAndPassword(
                                email: email,
                                password: password,
                              );

                          String? uid = credential.user?.uid;

                          if (uid != null) {
                            // 🔥 FIRESTORE SE ROLE VERIFY KAREIN
                            DocumentSnapshot userDoc = await FirebaseFirestore
                                .instance
                                .collection('users')
                                .doc(uid)
                                .get();

                            if (userDoc.exists) {
                              // Firestore se role uthayein (Ensure karein aapke DB mein field ka naam 'role' hi ho)
                              String userRole = userDoc
                                  .get('role')
                                  .toString()
                                  .toLowerCase();

                              if (userRole == 'admin') {
                                if (!kIsWeb) {
                                  await OneSignal.login(uid);
                                  await OneSignal.User.addTagWithKey(
                                    "role",
                                    userRole,
                                  );
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Admin Login Successful!'),
                                      backgroundColor: Color(0xFF4CAF50),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );

                                  print(
                                    "Connected successfully! Admin UID: $uid",
                                  );

                                  // Dashboard ka route yahan open kar dein
                                  Navigator.pushReplacement(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const AdminDashboardScreen(),
                                    ),
                                  );
                                }
                              } else {
                                // Toh foran Auth session se sign out karwadein taake login block ho jaye
                                await FirebaseAuth.instance.signOut();

                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Access Denied: You are not an Admin.',
                                      ),
                                      backgroundColor: Colors.red,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                            } else {
                              // Agar Auth mein user hai par Firestore database mein uska record nahi mila
                              await FirebaseAuth.instance.signOut();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Error: User record not found in database.',
                                    ),
                                    backgroundColor: Colors.red,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                            }
                          }
                        } on FirebaseAuthException catch (e) {
                          // ❌ Agar Firebase ki taraf se koi error aaye (Wrong password, User not found wagerah)
                          String errorMessage =
                              'An error occurred. Please try again.';

                          if (e.code == 'user-not-found' ||
                              e.code == 'invalid-credential') {
                            errorMessage = 'Incorrect email or password.';
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
                          // Kisi bhi aur qism k error k liye
                          print(e.toString());
                        }
                      },
                      child: const Text(
                        'LOGIN',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  // Go Back Navigation Option
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(
                        context,
                      ); // Wapas welcome screen par le jayega
                    },
                    icon: const Icon(
                      Icons.arrow_back,
                      size: 18,
                      color: Colors.grey,
                    ),
                    label: const Text(
                      'Not an Admin? Go Back',
                      style: TextStyle(color: Colors.grey),
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

// Custom Clipper Class jo background ko wave/curtain cut deti hai
class LoginHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    Path path = Path();
    path.lineTo(0, size.height - 50);

    var controlPoint = Offset(size.width / 2, size.height + 10);
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
