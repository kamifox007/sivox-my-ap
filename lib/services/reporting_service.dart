import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// ignore: unused_import
import 'package:my_app/services/translation_service.dart';
import 'package:my_app/services/audit_service.dart';
import 'package:my_app/services/booking_service.dart';
import 'package:my_app/services/localization_service.dart';
import 'package:my_app/models/booking.dart';
import 'package:intl/intl.dart';

class ReportingService {
  final supabase = Supabase.instance.client;
  final _audit = AuditService();
  final _booking = BookingService();

  /// Generates a professional PDF report for a specific event based on the user's role.
  Future<Uint8List> generateEventReport({
    String? eventId,
    required String userRole,
    required String eventTitle,
    required String clubName,
  }) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.notoSansArabicRegular();
    final fontBold = await PdfGoogleFonts.notoSansArabicBold();

    // Fetch operational data
    final logs = await _audit.getLogs(eventId: eventId);
    final bookings = eventId != null ? await _booking.getEventBookings(eventId) : <Booking>[];
    
    // Aggregated stats
    final totalGuests = bookings.fold(0, (sum, b) => sum + b.numGuests);
    final totalUsed = bookings.where((b) => b.paymentStatus == 'used').fold(0, (sum, b) => sum + b.numGuests);
    final totalRevenue = bookings.where((b) => b.paymentStatus == 'used').fold(0.0, (sum, b) => sum + b.totalPricePaid);
    final refusalCount = logs.where((l) => l['action_type'].toString().contains('REFUSED') || l['action_type'].toString().contains('DENY')).length;

    // Fetch Organizer Profile for branding if requested by organizer
    Map<String, dynamic>? organizerProfile;
    if (userRole == 'organizer' || userRole == 'owner') {
      try {
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
           organizerProfile = await supabase.from('organizer_profiles').select('*, profiles(full_name, avatar_url)').eq('id', userId).single();
        }
      } catch (_) {}
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          _buildBrandingHeader(organizerProfile, clubName),
          pw.SizedBox(height: 10),
          _buildHeader(clubName, eventTitle),
          pw.SizedBox(height: 20),
          _buildSummarySection(totalGuests, totalUsed, totalRevenue, refusalCount),
          pw.SizedBox(height: 30),
          if (userRole == 'organizer' || userRole == 'role_manager' || userRole == 'manager') ...[
            _buildSectionTitle('FINANCIAL_LEDGER'.tr),
            _buildFinancialTable(bookings),
            pw.SizedBox(height: 30),
          ],
          _buildSectionTitle('OPERATIONAL_LOGS'.tr),
          _buildLogsTable(logs, userRole),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 40),
            child: pw.Text(
              '${'generated_by'.tr}: Sivox Tactical Engine | ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey),
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildBrandingHeader(Map<String, dynamic>? profile, String defaultClub) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Sivox PREMIUM OPERATIONS', style: pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey400, letterSpacing: 2)),
              pw.SizedBox(height: 4),
              pw.Text(profile?['profiles']?['full_name'] ?? defaultClub, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
              if (profile?['bio'] != null)
                pw.SizedBox(
                  width: 300,
                  child: pw.Text(profile!['bio'], style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ),
            ],
          ),
          if (profile?['profiles']?['avatar_url'] != null)
             pw.Text('[LOGO]', style: pw.TextStyle(color: PdfColors.grey300, fontSize: 10)), // Placeholder for image if we add it late
        ],
      ),
    );
  }

  pw.Widget _buildHeader(String club, String event) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(event.toUpperCase(), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey900)),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: const pw.BoxDecoration(color: PdfColors.blueGrey900),
              child: pw.Text('TACTICAL_AUDIT'.tr, style: pw.TextStyle(fontSize: 8, color: PdfColors.white, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        pw.Divider(thickness: 1, color: PdfColors.blueGrey100),
      ],
    );
  }

  pw.Widget _buildSummarySection(int guests, int used, double revenue, int refusals) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: const pw.BoxDecoration(
        color: PdfColors.grey50,
        borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
        children: [
          _summaryItem('TOTAL_PASSES'.tr, '$guests', PdfColors.blueGrey700),
          _summaryItem('SCANNED'.tr, '$used', PdfColors.teal700),
          _summaryItem('REVENUE'.tr, LocalizationService.formatPrice(revenue, 'DZ'), PdfColors.blue900),
          _summaryItem('REFUSALS'.tr, '$refusals', PdfColors.red700),
        ],
      ),
    );
  }

  pw.Widget _summaryItem(String label, String value, PdfColor color) {
    return pw.Column(
      children: [
        pw.Text(label, style: pw.TextStyle(fontSize: 7, color: PdfColors.grey700, letterSpacing: 1)),
        pw.SizedBox(height: 4),
        pw.Text(value, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: color)),
      ],
    );
  }

  pw.Widget _buildSectionTitle(String title) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 12),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
           pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blueGrey800)),
           pw.Container(height: 1, width: 40, color: PdfColors.blueGrey200),
        ],
      ),
    );
  }

  pw.Widget _buildFinancialTable(List<Booking> bookings) {
    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['GUEST'.tr, 'TYPE'.tr, 'PAID'.tr, 'STATUS'.tr],
      data: bookings.take(50).map((b) => [
        b.userName.toUpperCase(),
        b.ticketType.toUpperCase(),
        LocalizationService.formatPrice(b.totalPricePaid, 'DZ'),
        b.paymentStatus.toUpperCase(),
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.white),
      cellStyle: const pw.TextStyle(fontSize: 7),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey100, width: 0.5))),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }

  pw.Widget _buildLogsTable(List<Map<String, dynamic>> logs, String role) {
    // Role-Based Filtering
    final filteredLogs = (role == 'role_security' || role == 'security')
        ? logs.where((l) {
            final action = l['action_type'].toString().toUpperCase();
            return action.contains('SCAN') || action.contains('REFUSED') || action.contains('EJECT') || action.contains('ENTRY');
          }).toList()
        : logs;

    return pw.TableHelper.fromTextArray(
      context: null,
      headers: ['TIME'.tr, 'AGENT'.tr, 'ACTION'.tr, 'DETAILS'.tr],
      data: filteredLogs.take(100).map((l) => [
        l['created_at']?.toString().substring(11, 16) ?? '',
        l['user_name'] ?? 'Staff',
        l['action_type']?.toString().tr ?? '',
        l['description'] ?? '',
      ]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 8, color: PdfColors.blueGrey900),
      cellStyle: const pw.TextStyle(fontSize: 7),
      headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
      rowDecoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey50, width: 0.5))),
      cellAlignment: pw.Alignment.centerLeft,
    );
  }
}
