import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

class ChallanPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;

  const ChallanPreviewScreen({super.key, required this.pdfBytes});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Challan Preview'),
        backgroundColor: const Color(0xFF1E3A5F),
        foregroundColor: Colors.white,
      ),
      body: PdfPreview(
        build: (format) async => pdfBytes,
        // Baqi tamam default buttons ko disable kar diya gaya hai
        allowPrinting: false,
        allowSharing: false,
        canChangeOrientation: false,
        canChangePageFormat: false,
        canDebug: false,
      ),
    );
  }
}
