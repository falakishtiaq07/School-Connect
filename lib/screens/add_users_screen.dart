import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:school_connect/service/email_verification_service.dart';

class AddUserScreen extends StatefulWidget {
  const AddUserScreen({super.key});

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rollNoController = TextEditingController();
  final RegExp _emailRx = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
  String? _selectedClass;
  String? _selectedRole;

  @override
  void initState() {
    super.initState();
    // Name change hone par auto-generate password logic
    _nameController.addListener(_generatePassword);
  }

  void _generatePassword() {
    final fullName = _nameController.text.trim();

    if (fullName.isEmpty) {
      setState(() {
        _passwordController.text = '';
      });
      return;
    }

    // Sirf first name lo
    final firstName = fullName.split(' ').first.toLowerCase();

    setState(() {
      _passwordController.text = '$firstName@123';
    });
  }

  Future<bool> checkRollNoExists(String rollNo) async {
    var snapshot = await FirebaseFirestore.instance
        .collection('users') // Ya jahan aapne students ka data rakha hai
        .where('role', isEqualTo: 'Student')
        .where('rollNo', isEqualTo: rollNo)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  Future<bool> checkEmailExists(String email) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    return snapshot.docs.isNotEmpty;
  }

  // ------------------------------------------------------------------
  // FIX: create the new user through a SECONDARY, temporary Firebase
  // App instance. FirebaseAuth.instanceFor(app: tempApp) has its own
  // isolated auth session, completely separate from the default app's
  // FirebaseAuth.instance — so the Admin's login (on the default app)
  // is never touched, replaced, or logged out. Once the new user is
  // created we immediately sign that temp session out and delete the
  // temp app, releasing its resources.
  // ------------------------------------------------------------------
  Future<UserCredential> _createUserWithoutSigningInAdminOut({
    required String email,
    required String password,
  }) async {
    final String tempAppName =
        'createUserTemp_${DateTime.now().millisecondsSinceEpoch}';

    // Reuse the same project config (google-services.json /
    // GoogleService-Info.plist / firebase_options.dart) as the main app.
    final FirebaseApp tempApp = await Firebase.initializeApp(
      name: tempAppName,
      options: Firebase.app().options,
    );

    try {
      final FirebaseAuth tempAuth = FirebaseAuth.instanceFor(app: tempApp);

      final UserCredential credential = await tempAuth
          .createUserWithEmailAndPassword(email: email, password: password);
      await credential.user!.sendEmailVerification();

      debugPrint("Verification email sent to: $email");

      // Sign out of the temporary session (not the Admin's session).
      await tempAuth.signOut();

      return credential;
    } finally {
      // Always clean up the temporary app, even if creation throws.
      await tempApp.delete();
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_generatePassword);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rollNoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          "Create User",
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(20), // Padding yahan aayegi
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        "CREATE NEW USER",
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Name Field
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Full Name",
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      ),
                      const SizedBox(height: 15),

                      // Email Field
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: "Email",
                          border: OutlineInputBorder(),
                          hintText: "example@gmail.com",
                        ),
                        validator: (value) {
                          final email = value?.trim() ?? '';

                          if (email.isEmpty) {
                            return 'Email is required';
                          }

                          if (!_emailRx.hasMatch(email)) {
                            return 'Enter a valid email';
                          }

                          return null;
                        },
                      ),
                      const SizedBox(height: 15),

                      // Auto Password Field
                      TextFormField(
                        controller: _passwordController,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: "Generated Password",
                          prefixIcon: Icon(Icons.lock_outline),
                          border: OutlineInputBorder(),
                          filled: true,
                          fillColor: Color(0xFFF0F0F0),
                        ),
                      ),
                      const SizedBox(height: 25),

                      // Role Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: "Select Role",
                          border: OutlineInputBorder(),
                        ),
                        items: ["Student", "Teacher"]
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedRole = v),
                        validator: (v) =>
                            v == null ? "Please select a role" : null,
                      ),

                      const SizedBox(height: 15),
                      if (_selectedRole == "Student") ...[
                        TextFormField(
                          controller: _rollNoController,
                          decoration: const InputDecoration(
                            labelText: "Roll Number *",
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return "Roll Number is required";
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 15),
                      ],

                      // Class Dropdown
                      DropdownButtonFormField<String>(
                        initialValue: _selectedClass,
                        decoration: const InputDecoration(
                          labelText: "Select Class",
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(10, (i) => (i + 1).toString())
                            .map(
                              (c) => DropdownMenuItem(
                                value: c,
                                child: Text("Class $c"),
                              ),
                            )
                            .toList(),
                        onChanged: (v) => setState(() => _selectedClass = v),
                        validator: (v) => v == null || v.isEmpty
                            ? "Please select a class"
                            : null,
                      ),
                      const SizedBox(height: 25),

                      // Buttons Row
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text("Cancel"),
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                if (_formKey.currentState!.validate()) {
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                  print("🔥 EMAIL VALIDATION STARTED");
                                  print(
                                    "🔥 EMAIL: ${_emailController.text.trim()}",
                                  );

                                  bool isRealEmail =
                                      await EmailVerificationService.isEmailValid(
                                        _emailController.text.trim(),
                                      );
                                  print(
                                    "🔥 EMAIL VALIDATION RESULT: $isRealEmail",
                                  );
                                  if (!isRealEmail) {
                                    if (mounted) {
                                      Navigator.pop(
                                        context,
                                      ); // loading dialog band karein
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "Email does not exist. Please enter a valid email.",
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  if (mounted) Navigator.pop(context);
                                  bool emailExists = await checkEmailExists(
                                    _emailController.text.trim(),
                                  );

                                  if (emailExists) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          "This email already exists.",
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }
                                  if (_selectedRole == "Student") {
                                    bool exists = await checkRollNoExists(
                                      _rollNoController.text.trim(),
                                    );
                                    if (exists) {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "Error: This Roll Number already exists!",
                                          ),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      return;
                                    }
                                  }
                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const Center(
                                      child: CircularProgressIndicator(),
                                    ),
                                  );

                                  try {
                                    // FIX: use the secondary-app helper
                                    // instead of
                                    // FirebaseAuth.instance.createUserWithEmailAndPassword(),
                                    // so the Admin stays signed in.
                                    UserCredential userCredential =
                                        await _createUserWithoutSigningInAdminOut(
                                          email: _emailController.text.trim(),
                                          password: _passwordController.text
                                              .trim(),
                                        );
                                    final Map<String, dynamic> userData = {
                                      "uid": userCredential.user!.uid,
                                      "name": _nameController.text.trim(),
                                      "email": _emailController.text.trim(),
                                      "role": _selectedRole,
                                      "class": _selectedClass ?? "N/A",
                                      "password": _passwordController.text
                                          .trim(),
                                      "isPasswordChanged": false,
                                      "emailVerified": false,
                                      "createdAt": FieldValue.serverTimestamp(),
                                    };

                                    // Sirf Student ke liye rollNo save hoga
                                    if (_selectedRole == "Student") {
                                      userData["rollNo"] = _rollNoController
                                          .text
                                          .trim();
                                    }

                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(userCredential.user!.uid)
                                        .set(userData);

                                    if (mounted) {
                                      Navigator.pop(context);
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            "User created! Verification email has been sent. User must verify the email before logging in.",
                                          ),
                                        ),
                                      );
                                    }
                                  } on FirebaseAuthException catch (e) {
                                    String errorMessage =
                                        e.message ?? "Error occurred";
                                    if (e.code == 'email-already-in-use') {
                                      errorMessage = "Email Already in Use.";
                                    }

                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(errorMessage),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  } catch (e) {
                                    if (mounted) {
                                      Navigator.pop(context);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text("Error: $e"),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                    }
                                  }
                                }
                              },
                              child: const Text("Create User"),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
