import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

class AddUserScreen extends StatefulWidget {
  const AddUserScreen({super.key});

  @override
  State<AddUserScreen> createState() => _AddUserScreenState();
}

class _AddUserScreenState extends State<AddUserScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _fatherNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _rollNoController = TextEditingController();
  final _classController = TextEditingController();

  final RegExp _emailRx = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');

  String? _selectedRole;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_generatePassword);
  }

  void _generatePassword() {
    final fullName = _nameController.text.trim();

    if (fullName.isEmpty) {
      if (mounted) {
        setState(() {
          _passwordController.text = '';
        });
      }
      return;
    }

    final firstName = fullName.split(' ').first.toLowerCase();

    if (mounted) {
      setState(() {
        _passwordController.text = '$firstName@123';
      });
    }
  }

  String _formatClassSection(String input) {
    String cleaned = input.trim().toUpperCase();
    cleaned = cleaned.replaceAll(RegExp(r'[\s_]+'), '-');
    return cleaned;
  }

  Future<bool> checkRollNoExists(String rollNo) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
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

  Future<UserCredential> _createUserWithoutSigningInAdminOut({
    required String email,
    required String password,
  }) async {
    final String tempAppName =
        'createUserTemp_${DateTime.now().millisecondsSinceEpoch}';

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

      await tempAuth.signOut();

      return credential;
    } finally {
      await tempApp.delete();
    }
  }

  @override
  void dispose() {
    _nameController.removeListener(_generatePassword);

    _nameController.dispose();
    _fatherNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _rollNoController.dispose();
    _classController.dispose();

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
            padding: const EdgeInsets.all(20),
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

                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: "Full Name *",
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Full Name is required";
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 15),

                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: "Email *",
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

                      DropdownButtonFormField<String>(
                        initialValue: _selectedRole,
                        decoration: const InputDecoration(
                          labelText: "Select Role *",
                          border: OutlineInputBorder(),
                        ),
                        items: ["Student", "Teacher"]
                            .map(
                              (r) => DropdownMenuItem(value: r, child: Text(r)),
                            )
                            .toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedRole = v;

                            if (v != "Student") {
                              _rollNoController.clear();
                              _fatherNameController.clear();
                            }
                          });
                        },
                        validator: (v) {
                          if (v == null) {
                            return "Please select a role";
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 15),

                      if (_selectedRole == "Student") ...[
                        TextFormField(
                          controller: _rollNoController,
                          keyboardType: TextInputType.text,
                          decoration: const InputDecoration(
                            labelText: "Roll Number *",
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return "Roll Number is required";
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 15),

                        TextFormField(
                          controller: _fatherNameController,
                          keyboardType: TextInputType.name,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: "Father Name *",
                            border: OutlineInputBorder(),
                            hintText: "Enter father's name",
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return "Father Name is required";
                            }
                            return null;
                          },
                        ),

                        const SizedBox(height: 15),
                      ],

                      TextFormField(
                        controller: _classController,
                        decoration: const InputDecoration(
                          labelText: "Class / Section *",
                          hintText: "e.g. 1-A, 5-B",
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return "Class is required";
                          }
                          return null;
                        },
                      ),

                      const SizedBox(height: 25),

                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                Navigator.pop(context);
                              },
                              child: const Text("Cancel"),
                            ),
                          ),

                          const SizedBox(width: 15),

                          Expanded(
                            child: FilledButton(
                              onPressed: () async {
                                if (!_formKey.currentState!.validate()) {
                                  return;
                                }

                                showDialog(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (context) {
                                    return const Center(
                                      child: CircularProgressIndicator(),
                                    );
                                  },
                                );

                                try {
                                  final emailExists = await checkEmailExists(
                                    _emailController.text.trim(),
                                  );

                                  if (!mounted) return;

                                  Navigator.pop(context);

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
                                    final rollExists = await checkRollNoExists(
                                      _rollNoController.text.trim(),
                                    );

                                    if (!mounted) return;

                                    if (rollExists) {
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
                                    builder: (context) {
                                      return const Center(
                                        child: CircularProgressIndicator(),
                                      );
                                    },
                                  );

                                  final UserCredential userCredential =
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
                                    "class": _formatClassSection(
                                      _classController.text,
                                    ),
                                    "password": _passwordController.text.trim(),
                                    "isPasswordChanged": false,
                                    "emailVerified": false,
                                    "createdAt": FieldValue.serverTimestamp(),
                                  };

                                  if (_selectedRole == "Student") {
                                    userData["rollNo"] = _rollNoController.text
                                        .trim();

                                    userData["father_name"] =
                                        _fatherNameController.text.trim();
                                  }

                                  await FirebaseFirestore.instance
                                      .collection('users')
                                      .doc(userCredential.user!.uid)
                                      .set(userData);

                                  if (!mounted) return;

                                  Navigator.pop(context);
                                  Navigator.pop(context);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "User created! Verification email has been sent. User must verify the email before logging in.",
                                      ),
                                    ),
                                  );
                                } on FirebaseAuthException catch (e) {
                                  if (!mounted) return;

                                  Navigator.pop(context);

                                  String errorMessage =
                                      e.message ?? "Error occurred";

                                  if (e.code == 'email-already-in-use') {
                                    errorMessage = "Email Already in Use.";
                                  }

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(errorMessage),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
                                } catch (e) {
                                  if (!mounted) return;

                                  // Loading dialog close
                                  Navigator.pop(context);

                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text("Error: $e"),
                                      backgroundColor: Colors.red,
                                    ),
                                  );
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
