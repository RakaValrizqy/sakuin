import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/features/report/report_providers.dart';
import 'package:share_plus/share_plus.dart';

class ReportExportService {
  ReportExportService(this._db);

  final AppDatabase _db;

  String _csvEscape(String value) {
    final needsQuote =
        value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    if (!needsQuote) return value;
    return '"${value.replaceAll('"', '""')}"';
  }

  Future<String> buildCsv(DatePeriod period) async {
    final rows = await _db.fetchTransactionsPage(
      limit: 10000,
      startDayKey: period.startDayKey,
      endDayKey: period.endDayKey,
    );

    final buf = StringBuffer();
    buf.writeln(
      'Tanggal,Waktu,Tipe,Item,Kategori,Dompet,Dompet Tujuan,Nominal,Biaya Admin,Catatan',
    );
    for (final d in rows) {
      final tx = d.transaction;
      final dt = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt).toLocal();
      final typeId = switch (tx.type) {
        'income' => 'Pemasukan',
        'expense' => 'Pengeluaran',
        _ => 'Transfer',
      };
      final fields = [
        AppDateUtils.formatShortDate(dt),
        AppDateUtils.formatTime(dt),
        typeId,
        tx.itemName ?? '',
        d.category?.name ?? '',
        d.wallet.name,
        d.toWallet?.name ?? '',
        tx.amount.toString(),
        tx.fee.toString(),
        tx.note,
      ];
      buf.writeln(fields.map(_csvEscape).join(','));
    }
    return buf.toString();
  }

  Future<void> exportCsvAndShare(DatePeriod period) async {
    final csv = await buildCsv(period);
    final dir = await getTemporaryDirectory();
    final filename =
        'sakuin_laporan_${period.startDayKey}_${period.endDayKey}.csv';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(utf8.encode('\uFEFF$csv')); // UTF-8 BOM untuk Excel
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'Laporan Sakuin (${period.label})',
        text: 'Ekspor CSV laporan keuangan Sakuin periode ${period.label}.',
      ),
    );
  }

  Future<void> exportPdfAndShare(ReportData data) async {
    final txs = await _db.fetchTransactionsPage(
      limit: 500,
      startDayKey: data.period.startDayKey,
      endDayKey: data.period.endDayKey,
    );
    final expenseCats = await _db.getCategoryBreakdown(
      startDayKey: data.period.startDayKey,
      endDayKey: data.period.endDayKey,
      type: 'expense',
    );

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Header(
            level: 0,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Laporan Keuangan Sakuin',
                      style: pw.TextStyle(
                        fontSize: 20,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text('Periode: ${data.period.label}'),
                  ],
                ),
                pw.Text(
                  'Dicetak ${AppDateUtils.formatShortDate(DateTime.now())}',
                  style: const pw.TextStyle(fontSize: 10),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
              children: [
                _pdfStat(
                  'Pemasukan',
                  CurrencyFormatter.format(data.summary.income),
                  PdfColors.green800,
                ),
                _pdfStat(
                  'Pengeluaran',
                  CurrencyFormatter.format(data.summary.expense),
                  PdfColors.red700,
                ),
                _pdfStat(
                  'Selisih',
                  CurrencyFormatter.formatSigned(data.summary.net),
                  PdfColors.blueGrey800,
                ),
                _pdfStat(
                  'Rata-rata / Hari',
                  CurrencyFormatter.format(data.dailyAverageExpense),
                  PdfColors.grey800,
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          if (expenseCats.isNotEmpty) ...[
            pw.Text(
              'Ringkasan Pengeluaran per Kategori',
              style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            pw.TableHelper.fromTextArray(
              headers: const ['Kategori', 'Transaksi', 'Total', 'Porsi'],
              data: [
                for (final cat in expenseCats)
                  [
                    cat.categoryName,
                    '${cat.count}x',
                    CurrencyFormatter.format(cat.total),
                    data.summary.expense > 0
                        ? '${((cat.total / data.summary.expense) * 100).toStringAsFixed(1)}%'
                        : '0%',
                  ],
              ],
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
              cellAlignment: pw.Alignment.centerLeft,
            ),
            pw.SizedBox(height: 18),
          ],
          pw.Text(
            'Daftar Transaksi (${txs.length})',
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 8),
          if (txs.isEmpty)
            pw.Text('Tidak ada transaksi pada periode ini.')
          else
            pw.TableHelper.fromTextArray(
              headers: const [
                'Tanggal',
                'Tipe',
                'Item / Kategori',
                'Dompet',
                'Nominal',
              ],
              data: [
                for (final d in txs)
                  [
                    AppDateUtils.formatShortDate(
                      DateTime.fromMillisecondsSinceEpoch(
                        d.transaction.occurredAt,
                      ).toLocal(),
                    ),
                    d.transaction.type == 'income'
                        ? 'Masuk'
                        : (d.transaction.type == 'expense'
                              ? 'Keluar'
                              : 'Transfer'),
                    d.transaction.itemName ??
                        d.category?.name ??
                        d.transaction.note,
                    d.wallet.name,
                    CurrencyFormatter.format(d.transaction.amount),
                  ],
              ],
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                fontSize: 10,
              ),
              cellStyle: const pw.TextStyle(fontSize: 9.5),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColors.grey200,
              ),
            ),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await getTemporaryDirectory();
    final filename =
        'sakuin_laporan_${data.period.startDayKey}_${data.period.endDayKey}.pdf';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);

    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'application/pdf')],
        subject: 'Laporan PDF Sakuin (${data.period.label})',
        text: 'Laporan keuangan Sakuin periode ${data.period.label}.',
      ),
    );
  }

  pw.Widget _pdfStat(String label, String value, PdfColor color) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(height: 2),
        pw.Text(
          value,
          style: pw.TextStyle(
            fontSize: 11,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

final reportExportServiceProvider = Provider<ReportExportService>((ref) {
  return ReportExportService(ref.watch(appDatabaseProvider));
});
