import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

class ViewChallanScreen extends StatefulWidget {
  const ViewChallanScreen({super.key});

  @override
  State<ViewChallanScreen> createState() => _ViewChallanScreenState();
}

class _ViewChallanScreenState extends State<ViewChallanScreen> {
  static const _navy = Color(0xFF1E3A5F);
  static const _accent = Color(0xFF2E86AB);
  static const _green = Color(0xFF28A745);

  String? _myRollNo;
  String? _studentName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMyRollNo();
  }

  Future<void> _fetchMyRollNo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // users collection se roll_no fetch karo
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (mounted) {
        setState(() {
          _myRollNo = doc.data()?['rollNo']?.toString();
          _studentName = doc.data()?['name']?.toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── PDF URL fix: Cloudinary raw URL ko inline viewer ke liye convert ──────
  // fl_inline add karo taake browser directly show kare
  String _inlineUrl(String url) {
    // Cloudinary URL format:
    // https://res.cloudinary.com/{cloud}/raw/upload/{preset}/{file}
    // fl_inline add karna hai after /upload/
    if (url.contains('/upload/') && !url.contains('fl_inline')) {
      return url.replaceFirst('/upload/', '/upload/fl_inline/');
    }
    return url;
  }

  // Download URL: fl_attachment add karo
  String _downloadUrl(String url) {
    if (url.contains('/upload/') && !url.contains('fl_attachment')) {
      return url.replaceFirst('/upload/', '/upload/fl_attachment/');
    }
    return url;
  }

  // ── View PDF ───────────────────────────────────────────────────────────────
  Future<void> _viewPdf(BuildContext ctx, String pdfUrl, String month) async {
    if (kIsWeb) {
      // Web pe: browser mein kholo (fl_inline se PDF tab mein open hoga)
      final uri = Uri.parse(pdfUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showError(ctx, 'Could not open PDF.');
      }
    } else {
      // Android/iOS: download karke SfPdfViewer mein show karo
      try {
        _showLoadingDialog(ctx);

        final dio = Dio();
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/challan_$month.pdf';

        await dio.download(
          pdfUrl,
          filePath,
          options: Options(headers: {'User-Agent': 'Mozilla/5.0'}),
        );

        if (!ctx.mounted) return;
        Navigator.pop(ctx); // close loading dialog

        Navigator.push(
          ctx,
          MaterialPageRoute(
            builder: (_) => _PdfViewerPage(
              filePath: filePath,
              title: 'Challan — $month',
              pdfUrl: pdfUrl,
              downloadUrl: _downloadUrl(pdfUrl),
            ),
          ),
        );
      } catch (e) {
        if (ctx.mounted) {
          Navigator.pop(ctx); // close loading dialog
          _showError(ctx, 'Error opening PDF: $e');
        }
      }
    }
  }

  // ── Download PDF ───────────────────────────────────────────────────────────
  Future<void> _downloadPdf(BuildContext ctx, String pdfUrl) async {
    final uri = Uri.parse(_downloadUrl(pdfUrl));

    final success = await launchUrl(uri, mode: LaunchMode.platformDefault);

    if (!success) {
      _showError(ctx, 'Could not download PDF.');
    }
  }

  void _showLoadingDialog(BuildContext ctx) {
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Color(0xFF1E3A5F)),
              SizedBox(height: 14),
              Text('Opening PDF...', style: TextStyle(fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }

  void _showError(BuildContext ctx, String msg) {
    if (!ctx.mounted) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text(
          'My Fee Challans',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: _navy))
          : _myRollNo == null
          ? _emptyOrError('Roll number not found.\nPlease contact admin.')
          : _buildChallanList(),
    );
  }

  Widget _buildChallanList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('challans')
          .where('rollNo', isEqualTo: _myRollNo)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _navy));
        }
        if (snapshot.hasError) {
          return _emptyOrError('Error: ${snapshot.error}');
        }

        final docs = snapshot.data?.docs ?? [];

        return CustomScrollView(
          slivers: [
            // ── Student header banner ──────────────────────────────────────
            SliverToBoxAdapter(child: _headerBanner(docs.length)),

            if (docs.isEmpty)
              SliverFillRemaining(
                child: _emptyOrError(
                  'No challans yet.\nYour fee challans will appear here\nonce the admin generates them.',
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _challanCard(ctx, docs[i]),
                    childCount: docs.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _headerBanner(int count) {
    return Container(
      color: _navy,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  (_studentName?.isNotEmpty == true)
                      ? _studentName![0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _studentName ?? 'Student',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        color: Colors.white70,
                        size: 13,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Roll# $_myRollNo',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '$count Challan(s)',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Challan Card ───────────────────────────────────────────────────────────
  Widget _challanCard(BuildContext ctx, QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final month = data['month'] ?? '—';
    final dueDate = data['dueDate'] ?? '—';
    final validTill = data['valid_till'] ?? '—';
    final grade = data['classSection'] ?? '—';
    final pdfUrl = data['pdfUrl'] ?? '';
    final status = data['status'] ?? 'unpaid';
    final schoolFee = (data['school_fee'] ?? 0).toDouble();
    final transportFee = (data['transport_fee'] ?? 0).toDouble();
    final totalFee = (data['totalAmount'] ?? 0).toDouble();
    final isPaid = status == 'paid';
    final statusColor = isPaid ? _green : Colors.orange;
    final statusLabel = isPaid ? 'Paid' : 'Unpaid';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.receipt_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Fee Challan — $month',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withOpacity(0.4)),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Body ────────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Info row
                Row(
                  children: [
                    Expanded(child: _infoTile('Grade', grade)),
                    Expanded(child: _infoTile('Due Date', dueDate)),
                    Expanded(child: _infoTile('Valid Till', validTill)),
                  ],
                ),
                const SizedBox(height: 14),

                // Fee breakdown table
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FA),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      // Table header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: _navy.withOpacity(0.05),
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(10),
                            topRight: Radius.circular(10),
                          ),
                        ),
                        child: Row(
                          children: const [
                            Expanded(
                              child: Text(
                                'Particulars',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: _navy,
                                ),
                              ),
                            ),
                            Text(
                              'Amount',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (schoolFee > 0) ...[_feeRow('School Fee', schoolFee)],
                      if (transportFee > 0) ...[
                        const Divider(height: 1, color: Color(0xFFE5E7EB)),
                        _feeRow('Transport Fee', transportFee),
                      ],
                      const Divider(height: 1, color: Color(0xFFE5E7EB)),
                      // Total
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE8F0FE),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(10),
                            bottomRight: Radius.circular(10),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Total Amount',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                            Text(
                              'Rs. ${totalFee.toStringAsFixed(0)}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: _navy,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // Action buttons
                if (pdfUrl.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _viewPdf(ctx, pdfUrl, month),
                          icon: const Icon(Icons.visibility_outlined, size: 17),
                          label: const Text(
                            'View PDF',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _downloadPdf(ctx, pdfUrl),
                          icon: const Icon(Icons.download_outlined, size: 17),
                          label: const Text(
                            'Download',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _navy,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(9),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_outlined,
                          color: Colors.orange.shade700,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'PDF not available. Please contact admin.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF92400E),
                            ),
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

  Widget _infoTile(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  Widget _feeRow(String label, double amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151)),
          ),
          Text(
            'Rs. ${amount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1F2937),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyOrError(String msg) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 60,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Color(0xFF9CA3AF)),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PDF Viewer Page — Android/iOS only
// ═══════════════════════════════════════════════════════════════════════════

class _PdfViewerPage extends StatelessWidget {
  final String filePath;
  final String title;
  final String pdfUrl;
  final String downloadUrl;

  const _PdfViewerPage({
    required this.filePath,
    required this.title,
    required this.pdfUrl,
    required this.downloadUrl,
  });

  static const _navy = Color(0xFF1E3A5F);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        actions: [
          // Download button in appbar
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download PDF',
            onPressed: () async {
              final uri = Uri.parse(downloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ],
      ),
      body: SfPdfViewer.file(
        File(filePath),
        canShowScrollHead: true,
        canShowScrollStatus: true,
      ),
    );
  }
}
