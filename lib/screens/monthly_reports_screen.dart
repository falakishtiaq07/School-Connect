import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'dart:typed_data';

import 'package:school_connect/service/notification_service.dart';

class MonthlyReportsScreen extends StatefulWidget {
  const MonthlyReportsScreen({super.key});

  @override
  State<MonthlyReportsScreen> createState() => _MonthlyReportsScreenState();
}

class _MonthlyReportsScreenState extends State<MonthlyReportsScreen> {
  final _formKey = GlobalKey<FormState>();
  final totalDaysController = TextEditingController();
  final presentController = TextEditingController();
  final absentController = TextEditingController();
  final remarksController = TextEditingController();
  final cloudinary = CloudinaryPublic(
    'dkjsza6pw',
    'monthly_reports',
    cache: false,
  );
  File? _selectedImage;
  final ImagePicker _picker = ImagePicker();

  // State variables
  List<String> classesList = [
    "Class 1",
    "Class 2",
    "Class 3",
    "Class 4",
    "Class 5",
  ];
  String? selectedClass;
  String? selectedStudentId;
  String? selectedStudentName;
  String? selectedMonth;
  String? selectedPerformance;
  String? selectedHomework;
  String? selectedParticipation;

  List<String> classes = [];
  List<QueryDocumentSnapshot> students = [];
  List<XFile> _selectedImages = [];
  bool isLoadingStudents = false;
  bool isSaving = false;
  // Design Constants
  final Color primaryBlue = const Color(0xFF1746A2);
  final Color successGreen = const Color(0xFF166534);

  List<String> getMonthsList() {
    List<String> months = [
      "January",
      "February",
      "March",
      "April",
      "May",
      "June",
      "July",
      "August",
      "September",
      "October",
      "November",
      "December",
    ];
    return months;
  }

  @override
  void initState() {
    super.initState();
    loadClasses();
  }

  Future<void> loadClasses() async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Student')
        .get();

    Set<String> uniqueClasses = {};
    for (var doc in snapshot.docs) {
      if (doc.data() is Map && (doc.data() as Map).containsKey('class')) {
        uniqueClasses.add(doc['class']);
      }
    }

    setState(() {
      classes = uniqueClasses.toList()..sort();
    });
  }

  Future<void> loadStudents(String className) async {
    setState(() {
      isLoadingStudents = true;
      students = [];
      selectedStudentId = null;
    });

    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection('users')
        .where('role', isEqualTo: 'Student')
        .where('class', isEqualTo: className)
        .get();

    setState(() {
      students = snapshot.docs;
      isLoadingStudents = false;
    });
  }

  Future<void> sendReport() async {
    // 1. Validation Check
    if (!_formKey.currentState!.validate()) return;

    // Student selection check
    if (selectedStudentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please select a student!"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      List<String> uploadedImageUrls = [];

      for (var image in _selectedImages) {
        final bytes = await image.readAsBytes();

        CloudinaryResponse response = await cloudinary.uploadFile(
          CloudinaryFile.fromByteData(
            // Try this method
            bytes.buffer.asByteData(),
            identifier: image.name,
            resourceType: CloudinaryResourceType.Image,
            folder: 'monthly_reports',
          ),
        );
        uploadedImageUrls.add(response.secureUrl);
      }

      // 3. Firestore Data Save
      DocumentReference reportRef = await FirebaseFirestore.instance
          .collection('monthly_reports')
          .add({
            'studentId': selectedStudentId,
            'studentName': selectedStudentName,
            'class': selectedClass,
            'month': selectedMonth,
            'overallPerformance': selectedPerformance,
            'homeworkCompletion': selectedHomework,
            'classParticipation': selectedParticipation,
            'totalDays': totalDaysController.text,
            'presentDays': presentController.text,
            'absentDays': absentController.text,
            'remarks': remarksController.text,
            'attachmentUrls': uploadedImageUrls, // List of URLs save hogi
            'createdAt': FieldValue.serverTimestamp(),
          });
      await NotificationService.sendPushNotification(
        targetRole: 'student',
        title: 'Monthly Report Available',
        body: 'Your report card for $selectedMonth is ready to view.',
        notificationType: 'report',
        relatedId: reportRef.id,
      );
      // 4. Fields Reset Logic
      _formKey.currentState!.reset();

      totalDaysController.clear();
      presentController.clear();
      absentController.clear();
      remarksController.clear();

      setState(() {
        _selectedImages = []; // Images list clear karein
        selectedClass = null;
        selectedStudentId = null;
        selectedStudentName = null;
        selectedMonth = null;
        selectedPerformance = null;
        selectedHomework = null;
        selectedParticipation = null;
        students = [];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Monthly Report Sent Successfully!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  final List<PlatformFile> _selectedFiles = [];
  Future<void> _pickImages() async {
    final List<XFile> pickedFiles = await _picker.pickMultiImage();
    if (pickedFiles.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(pickedFiles);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 70,
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF1E3A5F),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A5F), Color(0xFF16304E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        title: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Monthly Reports",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 21),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Form(
            key: _formKey,
            // Validation sirf button click par hogi
            autovalidateMode: AutovalidateMode.disabled,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle("Student & Report Month"),
                _buildCard([
                  DropdownButtonFormField<String>(
                    decoration: InputDecoration(
                      labelText: "Select Class",
                      prefixIcon: const Icon(
                        Icons.class_rounded,
                        color: Color(0xFF1E3A5F),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 18,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(
                          color: Color(0xFF1746A2),
                          width: 2,
                        ),
                      ),
                    ),
                    items: classes
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => selectedClass = val);
                        loadStudents(val);
                        // validate() hata diya
                      }
                    },
                    validator: (v) => v == null ? "Required" : null,
                  ),
                  const SizedBox(height: 15),
                  isLoadingStudents
                      ? const CircularProgressIndicator()
                      : DropdownButtonFormField<String>(
                          initialValue: selectedStudentId,
                          decoration: InputDecoration(
                            labelText: "Select Student",
                            prefixIcon: const Icon(
                              Icons.person_rounded,
                              color: Color(0xFF1E3A5F),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 18,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                              borderSide: BorderSide(
                                color: Colors.grey.shade300,
                              ),
                            ),
                            focusedBorder: const OutlineInputBorder(
                              borderRadius: BorderRadius.all(
                                Radius.circular(14),
                              ),
                              borderSide: BorderSide(
                                color: Color(0xFF1746A2),
                                width: 2,
                              ),
                            ),
                          ),
                          items: students.map((student) {
                            return DropdownMenuItem(
                              value: student.id,
                              child: Text(
                                "${student['name']} (${student['rollNo']})",
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              final student = students.firstWhere(
                                (s) => s.id == value,
                              );
                              setState(() {
                                selectedStudentId = value;
                                selectedStudentName = student['name'];
                              });
                              // validate() hata diya
                            }
                          },
                          validator: (v) =>
                              v == null ? "Please select a student" : null,
                        ),
                  const SizedBox(height: 15),
                  _buildDropdown("Select Month", getMonthsList(), (val) {
                    setState(() => selectedMonth = val);
                    // validate() hata diya
                  }),
                ]),
                _buildSectionTitle("Academic Performance"),
                _buildCard([
                  _buildDropdown(
                    "Overall Performance",
                    ["Excellent", "Good", "Average"],
                    (val) => setState(() => selectedPerformance = val),
                  ),
                  const SizedBox(height: 15),
                  _buildDropdown(
                    "Homework Completion",
                    ["Always", "Mostly", "Rarely"],
                    (val) => setState(() => selectedHomework = val),
                  ),
                  const SizedBox(height: 15),
                  _buildDropdown(
                    "Class Participation",
                    ["Active", "Moderate", "Low"],
                    (val) => setState(() => selectedParticipation = val),
                  ),
                ]),
                _buildSectionTitle("Attendance & Remarks"),
                _buildCard([
                  LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 700) {
                        return Column(
                          children: [
                            _buildTextField("Total Days", totalDaysController),
                            const SizedBox(height: 15),
                            _buildTextField("Present Days", presentController),
                            const SizedBox(height: 15),
                            _buildTextField("Absent Days", absentController),
                          ],
                        );
                      }

                      return Row(
                        children: [
                          Expanded(
                            child: _buildTextField(
                              "Total Days",
                              totalDaysController,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _buildTextField(
                              "Present Days",
                              presentController,
                            ),
                          ),
                          const SizedBox(width: 15),
                          Expanded(
                            child: _buildTextField(
                              "Absent Days",
                              absentController,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  TextFormField(
                    controller: remarksController,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: "Teacher Remarks",
                      alignLabelWithHint: true,
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(bottom: 60),
                        child: Icon(
                          Icons.edit_note_rounded,
                          color: Color(0xFF1E3A5F),
                        ),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide(color: Colors.grey.shade300),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(
                          color: Color(0xFF1746A2),
                          width: 2,
                        ),
                      ),
                    ),
                    validator: (value) =>
                        value!.isEmpty ? 'Please enter remarks' : null,
                  ),
                ]),
                const SizedBox(height: 10),
                _buildSectionTitle("Attachments (Optional)"),
                _buildAttachmentSection(),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          side: BorderSide(color: primaryBlue),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: Text(
                          "Cancel",
                          style: TextStyle(
                            color: primaryBlue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 15),

                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A5F),
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(52),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: isSaving
                            ? null
                            : () {
                                if (_formKey.currentState!.validate()) {
                                  sendReport();
                                }
                              },
                        child: isSaving
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: Colors.white,
                                ),
                              )
                            : const Text(
                                "Send Report",
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 12),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 22,
            decoration: BoxDecoration(
              color: primaryBlue,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: primaryBlue,
              letterSpacing: .2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildDropdown(
    String label,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: Color(0xFF1E3A5F),
        ),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1746A2), width: 2),
        ),
      ),
      // Validation add ki
      validator: (value) =>
          value == null || value.isEmpty ? 'Please select $label' : null,
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.numbers, color: Color(0xFF1E3A5F)),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
          borderSide: BorderSide(color: Color(0xFF1746A2), width: 2),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Required'; // Ye error red text mein dikhayega
        }
        return null;
      },
    );
  }

  Widget _buildAttachmentSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.attach_file, color: primaryBlue),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Attachments",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      "Upload report images",
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _pickImages,
              icon: const Icon(Icons.upload_file),
              label: const Text(
                "Choose Images",
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryBlue,
                side: BorderSide(color: primaryBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          if (_selectedImages.isNotEmpty) ...[
            const SizedBox(height: 18),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _selectedImages.map((image) {
                return FutureBuilder<Uint8List>(
                  future: image.readAsBytes(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Colors.grey.shade100,
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    return Stack(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(.08),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              snapshot.data!,
                              width: 90,
                              height: 90,
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),

                        Positioned(
                          right: -4,
                          top: -4,
                          child: IconButton(
                            icon: const Icon(Icons.cancel, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _selectedImages.remove(image);
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
