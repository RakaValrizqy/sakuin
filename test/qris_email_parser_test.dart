import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/utils/qris_email_parser.dart';

void main() {
  group('QrisEmailParser', () {
    test('parses Livin by Mandiri QRIS HTML email', () {
      const from = 'Livin by Mandiri <notifikasi@bankmandiri.co.id>';
      const subject = 'Transaksi QRIS Berhasil';
      const body = '''
      <html><body>
        <table>
          <tr><td>Status</td><td>Berhasil</td></tr>
          <tr><td>Jenis Transaksi</td><td>Pembayaran QRIS</td></tr>
          <tr><td>Nama Merchant</td><td>WARUNG GEPREK MAS BUDI</td></tr>
          <tr><td>Total Pembayaran</td><td>Rp 20.000,00</td></tr>
        </table>
      </body></html>
      ''';

      expect(QrisEmailParser.isLikelyQrisHeader(from, subject), isTrue);
      final parsed = QrisEmailParser.parse(
        from: from,
        subject: subject,
        rawBody: body,
        emailDate: DateTime(2026, 11, 26, 12, 15),
      );
      expect(parsed, isNotNull);
      expect(parsed!.bankName, 'Mandiri');
      expect(parsed.merchantName, 'WARUNG GEPREK MAS BUDI');
      expect(parsed.amount, 20000);
    });

    test('parses BCA QRIS email with IDR format and decimals', () {
      const from = 'BCA <bca@bca.co.id>';
      const subject = 'Notifikasi Transaksi QRIS';
      const body = '''
      Transaksi QRIS Anda berhasil diproses.
      Penerima : KOPI KENANGAN GRAND INDONESIA
      Nominal Transaksi : IDR 45,500.00
      ''';

      final parsed = QrisEmailParser.parse(
        from: from,
        subject: subject,
        rawBody: body,
      );
      expect(parsed, isNotNull);
      expect(parsed!.bankName, 'BCA');
      expect(parsed.merchantName, 'KOPI KENANGAN GRAND INDONESIA');
      expect(parsed.amount, 45500);
    });

    test('decodes Quoted-Printable & RFC 2047 headers', () {
      final subj = QrisEmailParser.decodeRfc2047(
        '=?UTF-8?Q?Pembayaran_QRIS_Berhasil?=',
      );
      expect(subj, 'Pembayaran QRIS Berhasil');

      const qpBody =
          'Pembayaran QRIS=0D=0AMerchant: KEDAI KOPI=0D=0ATotal: Rp 18.000';
      final parsed = QrisEmailParser.parse(
        from: 'GoPay <no-reply@gojek.com>',
        subject: subj,
        rawBody: qpBody,
      );
      expect(parsed, isNotNull);
      expect(parsed!.bankName, 'GoPay');
      expect(parsed.merchantName, 'KEDAI KOPI');
      expect(parsed.amount, 18000);
    });

    test('rejects OTP, failed payments, promos, and incoming QRIS funds', () {
      expect(
        QrisEmailParser.isLikelyQrisHeader(
          'BCA <bca@bca.co.id>',
          'Kode OTP Transaksi Anda',
        ),
        isFalse,
      );
      expect(
        QrisEmailParser.parse(
          from: 'Mandiri <livin@bankmandiri.co.id>',
          subject: 'Transaksi QRIS Gagal',
          rawBody: 'Pembayaran QRIS gagal sebesar Rp 20.000',
        ),
        isNull,
      );
      expect(
        QrisEmailParser.parse(
          from: 'DANA <noreply@dana.id>',
          subject: 'Dana Masuk QRIS',
          rawBody: 'Anda menerima dana masuk QRIS sebesar Rp 50.000',
        ),
        isNull,
      );
    });

    test('parses RFC 2822 email Date header', () {
      final dt = QrisEmailParser.parseEmailDate(
        'Thu, 26 Nov 2026 12:30:00 +0700',
      );
      expect(dt, isNotNull);
      expect(dt!.toUtc(), DateTime.utc(2026, 11, 26, 5, 30, 0));
    });
  });
}
