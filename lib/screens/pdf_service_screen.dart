import 'dart:typed_data';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

// ─── Data Models ──────────────────────────────────────────────────────────────

class FeeParticular {
  final String name;
  final double amount;
  const FeeParticular({required this.name, required this.amount});
}

class ChallanData {
  final String challanNo;
  final String schoolName;
  final String schoolAddress;
  final String schoolPhone;
  final String kuickpayId;
  final String rollNo;
  final String studentName;
  final String fatherName;
  final String classSection;
  final String month;
  final String issueDate;
  final String dueDate;
  final String validTill;
  final List<FeeParticular> feeParticulars;

  double get totalAmount =>
      feeParticulars.fold(0.0, (sum, f) => sum + f.amount);

  const ChallanData({
    required this.challanNo,
    required this.schoolName,
    required this.schoolAddress,
    required this.schoolPhone,
    required this.kuickpayId,
    required this.rollNo,
    required this.studentName,
    required this.fatherName,
    required this.classSection,
    required this.month,
    required this.issueDate,
    required this.dueDate,
    required this.validTill,
    required this.feeParticulars,
  });
}

// ─── PDF Service ──────────────────────────────────────────────────────────────

class ChallanPdfService {
  static const _navy = PdfColor.fromInt(0xFF1E3A5F);
  static const _lightBlue = PdfColor.fromInt(0xFFE8F0FE);
  static const _border = PdfColor.fromInt(0xFFCCCCCC);
  static const _black = PdfColors.black;
  static const _white = PdfColors.white;
  static const _grey = PdfColor.fromInt(0xFF555555);

  // A4 = 841pt height, margin 8 top+8 bottom = 825pt usable
  // 3 copies + 2 dividers(8pt each) = 825 - 16 = 809 / 3 = 269 → use 268
  static const double _copyHeight = 268.0;

  // ── buildPageWidget ──────────────────────────────────────────────────────
  static pw.Widget buildPageWidget(ChallanData data) {
    return pw.Column(
      children: [
        pw.SizedBox(height: _copyHeight, child: _buildCopy('Bank Copy', data)),
        _dashed(),
        pw.SizedBox(
          height: _copyHeight,
          child: _buildCopy('Office Copy', data),
        ),
        _dashed(),
        pw.SizedBox(
          height: _copyHeight,
          child: _buildCopy('Student Copy', data),
        ),
      ],
    );
  }

  // ── addChallanPage: adds one A4 page to existing Document ───────────────
  static void addChallanPage(pw.Document pdf, ChallanData data) {
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        build: (_) => pw.Column(
          children: [
            pw.SizedBox(
              height: _copyHeight,
              child: _buildCopy('Bank Copy', data),
            ),
            _dashed(),
            pw.SizedBox(
              height: _copyHeight,
              child: _buildCopy('Office Copy', data),
            ),
            _dashed(),
            pw.SizedBox(
              height: _copyHeight,
              child: _buildCopy('Student Copy', data),
            ),
          ],
        ),
      ),
    );
  }

  // ── generatePdf: returns bytes for single student ───────────────────────
  static Future<Uint8List> generatePdf(ChallanData data) async {
    final pdf = pw.Document();
    addChallanPage(pdf, data);
    return pdf.save();
  }

  // ── generateAndShare ─────────────────────────────────────────────────────
  // ── generateAndUploadToCloudinary ────────────────────────────────────────
  static Future<String?> generateAndUploadToCloudinary(
    ChallanData data,
    String cloudName,
    String uploadPreset,
  ) async {
    try {
      // 1. PDF bytes generate karein
      final bytes = await generatePdf(data);

      // 2. Cloudinary par upload karein
      final cloudinary = CloudinaryPublic(
        cloudName,
        uploadPreset,
        cache: false,
      );

      CloudinaryResponse response = await cloudinary.uploadFile(
        CloudinaryFile.fromByteData(
          ByteData.sublistView(
            bytes,
          ), // Uint8List ko ByteData mein convert kiya
          folder: 'challans',
          identifier: 'challan_${data.rollNo}_${data.challanNo}',
          resourceType: CloudinaryResourceType.Auto,
        ),
      );

      // 3. Cloudinary ka secure URL return kar dega
      return response.secureUrl;
    } catch (e) {
      print('Cloudinary PDF Upload Error: $e');
      return null;
    }
  }

  // ── Dashed divider (8pt height) ──────────────────────────────────────────
  static pw.Widget _dashed() {
    return pw.Container(
      height: 8,
      child: pw.CustomPaint(
        size: const PdfPoint(double.infinity, 4),
        painter: (canvas, size) {
          canvas
            ..setStrokeColor(PdfColors.grey400)
            ..setLineWidth(0.5);
          double x = 0;
          while (x < size.x) {
            canvas.drawLine(x, 2, x + 5, 2);
            x += 9;
          }
          canvas.strokePath();
        },
      ),
    );
  }

  // ── One copy ─────────────────────────────────────────────────────────────
  static pw.Widget _buildCopy(String copyType, ChallanData data) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(2)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          _header(copyType, data),
          _info(data),
          _table(data),
          _footer(),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────────────────────
  static pw.Widget _header(String copyType, ChallanData data) {
    return pw.Container(
      color: _navy,
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  data.schoolName.toUpperCase(),
                  style: pw.TextStyle(
                    color: _white,
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '${data.schoolAddress}  |  Ph: ${data.schoolPhone}',
                  style: const pw.TextStyle(
                    color: PdfColor(1, 1, 1, 0.75),
                    fontSize: 6.5,
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: const pw.BoxDecoration(
                  color: PdfColors.white,
                  borderRadius: pw.BorderRadius.all(pw.Radius.circular(3)),
                ),
                child: pw.Text(
                  copyType,
                  style: pw.TextStyle(
                    color: _navy,
                    fontSize: 7,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Kuickpay ID: ${data.kuickpayId}',
                style: pw.TextStyle(
                  color: _white,
                  fontSize: 6.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Info Section ─────────────────────────────────────────────────────────
  static pw.Widget _info(ChallanData data) {
    return pw.Container(
      color: _lightBlue,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _iRow('Roll No', data.rollNo),
                _iRow("Student Name", data.studentName),
                _iRow("Father Name", data.fatherName),
                _iRow('Grade', data.classSection),
              ],
            ),
          ),
          pw.Container(width: 0.5, height: 52, color: _border),
          pw.SizedBox(width: 10),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _iRow('Challan No', data.challanNo),
                _iRow('Month', data.month),
                _iRow('Issue Date', data.issueDate),
                _iRow('Due Date', data.dueDate),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _iRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1.8),
      child: pw.Row(
        children: [
          pw.SizedBox(
            width: 68,
            child: pw.Text(
              label,
              style: pw.TextStyle(
                fontSize: 7,
                color: _grey,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Text(': ', style: const pw.TextStyle(fontSize: 7, color: _grey)),
          pw.Expanded(
            child: pw.Text(
              value,
              style: pw.TextStyle(
                fontSize: 7.5,
                color: _black,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Particulars Table ────────────────────────────────────────────────────
  static pw.Widget _table(ChallanData data) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.symmetric(
          horizontal: pw.BorderSide(color: _border, width: 0.5),
        ),
      ),
      child: pw.Column(
        children: [
          // Header
          pw.Container(
            color: _navy,
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 6,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      'Particulars',
                      style: pw.TextStyle(
                        color: _white,
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.Container(
                  width: 0.5,
                  height: 18,
                  color: const PdfColor(1, 1, 1, 0.3),
                ),
                pw.SizedBox(
                  width: 80,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      'Amount',
                      style: pw.TextStyle(
                        color: _white,
                        fontSize: 7.5,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Fee rows
          ...data.feeParticulars.map(
            (item) => _tRow(item.name, 'Rs. ${_fmt(item.amount)}', _white),
          ),
          // Total
          pw.Container(
            color: _lightBlue,
            child: pw.Row(
              children: [
                pw.Expanded(
                  flex: 6,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      'Total Amount',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: _navy,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                pw.Container(width: 0.5, height: 20, color: _border),
                pw.SizedBox(
                  width: 80,
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: pw.Text(
                      'Rs. ${_fmt(data.totalAmount)}',
                      style: pw.TextStyle(
                        fontSize: 8,
                        color: _navy,
                        fontWeight: pw.FontWeight.bold,
                      ),
                      textAlign: pw.TextAlign.right,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _tRow(String particular, String amount, PdfColor bg) {
    return pw.Container(
      color: bg,
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 6,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              child: pw.Text(
                particular,
                style: const pw.TextStyle(fontSize: 7.5, color: _black),
              ),
            ),
          ),
          pw.Container(width: 0.5, height: 18, color: _border),
          pw.SizedBox(
            width: 80,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              child: pw.Text(
                amount,
                style: const pw.TextStyle(fontSize: 7.5, color: _black),
                textAlign: pw.TextAlign.right,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Footer — 2 lines only ────────────────────────────────────────────────
  static pw.Widget _footer() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Above due date is only for current month. Previous dues must be paid immediately.',

                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.red700,
                  ),
                ),
                pw.Text(
                  "Fee must be paid on or before the due date.",
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.Text(
                  "Keep the student copy safe for future record verification.",
                  style: const pw.TextStyle(fontSize: 12),
                ),
                pw.SizedBox(height: 12),
                pw.Text(
                  'Pay via Kuickpay: JazzCash, Easypaisa, HBL, Meezan, MCB, UBL or any 1Link bank.',
                  style: const pw.TextStyle(fontSize: 6.5, color: _grey),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 12),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(height: 16),
              pw.Container(width: 70, height: 0.5, color: _black),
              pw.SizedBox(height: 2),
              pw.Text(
                'Signature & Stamp',
                style: const pw.TextStyle(fontSize: 6, color: _grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Number formatter ─────────────────────────────────────────────────────
  static String _fmt(double v) {
    if (v == v.truncateToDouble()) {
      return v.toInt().toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
    }
    return v.toStringAsFixed(2);
  }
}
