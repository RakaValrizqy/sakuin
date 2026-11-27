import 'package:sakuin/core/utils/qris_email_parser.dart';

class ParsedNotificationTx {
  const ParsedNotificationTx({
    required this.uid,
    required this.bankName,
    required this.merchantName,
    required this.amount,
    required this.occurredAt,
    required this.title,
    required this.snippet,
    this.txType = 'expense',
  });

  final String uid;
  final String bankName;
  final String merchantName;
  final int amount;
  final DateTime occurredAt;
  final String title;
  final String snippet;
  final String txType; // 'expense' | 'income'
}

/// Parser 100% lokal untuk notifikasi push transaksi dari aplikasi bank & e-wallet Indonesia.
class NotificationTxParser {
  NotificationTxParser._();

  static const Map<String, String> _packageToBank = {
    'id.bmri.livin': 'Mandiri',
    'com.bca': 'BCA',
    'com.bca.mybca.omni.android': 'BCA',
    'id.co.bri.brimo': 'BRI',
    'src.com.bni': 'BNI',
    'id.bni.wondr': 'BNI',
    'com.bsm.activity2': 'BSI',
    'id.co.bankbsi.byond': 'BSI',
    'com.gojek.app': 'GoPay',
    'com.gojek.gopay': 'GoPay',
    'ovo.id': 'OVO',
    'id.dana': 'DANA',
    'com.shopee.id': 'ShopeePay',
    'com.shopeepay.id': 'ShopeePay',
    'id.co.bankbkemobile.digitalbank': 'SeaBank',
    'com.jago.digitalBanking': 'Jago',
    'com.bcadigital.blu': 'Blu',
    'id.co.cimbniaga.mobile.android': 'CIMB',
    'com.btpn.dc': 'Jenius',
    'com.telkom.mwallet': 'LinkAja',
    'net.myinfosys.PermataMobileX': 'Permata',
    'com.allo.bank': 'Allo Bank',
    'com.bnc.finance': 'Neo Bank',
    'com.ocbc.mobile': 'OCBC',
    'id.co.danamon.dbankpro': 'Danamon',
    'id.superbank.app': 'Superbank',
    'id.krom.bank': 'Krom',
  };

  static const List<String> _hardRejectPhrases = [
    'kode otp',
    'otp ',
    'kode verifikasi',
    'verification code',
    'gagal',
    'failed',
    'dibatalkan',
    'ditolak',
    'diskon hingga',
    'cashback hingga',
    'promo spesial',
    'voucher menunggu',
    'klaim sekarang',
    'kirim uang ke teman yuk',
  ];

  static const List<String> _incomeSignals = [
    'dana masuk',
    'uang masuk',
    'saldo masuk',
    'transfer masuk',
    'kamu menerima',
    'anda menerima',
    'terima dana',
    'terima transfer',
    'top up berhasil',
    'isi saldo berhasil',
    'cashback masuk',
    'kredit sebesar',
    'credited',
  ];

  static const List<String> _expenseSignals = [
    'qris',
    'pembayaran',
    'bayar',
    'transaksi',
    'pembelian',
    'beli',
    'berhasil dibayar',
    'payment',
    'paid',
    'debet',
    'debit',
    'terpotong',
    'pengeluaran',
    'transfer berhasil',
    'berhasil dikirim',
  ];

  static String bankNameForPackage(String packageName) {
    return _packageToBank[packageName] ?? 'Notifikasi Bank';
  }

  /// Parse notifikasi bank/e-wallet menjadi transaksi pengeluaran (atau pemasukan jika
  /// [captureIncome] aktif) untuk antrean Review.
  /// Mengembalikan `null` jika notifikasi adalah promo, OTP, atau transaksi gagal.
  static ParsedNotificationTx? parse({
    required String packageName,
    required String title,
    required String text,
    required DateTime timestamp,
    bool captureIncome = false,
  }) {
    final combined = '${title.trim()}\n${text.trim()}'.trim();
    if (combined.isEmpty) return null;

    final lower = combined.toLowerCase();
    for (final reject in _hardRejectPhrases) {
      if (lower.contains(reject)) return null;
    }

    final isIncome = _incomeSignals.any(lower.contains);
    if (isIncome && !captureIncome) return null;

    final txType = isIncome ? 'income' : 'expense';
    if (!isIncome) {
      final hasSignal = _expenseSignals.any(lower.contains);
      if (!hasSignal) return null;
    }

    final amount = QrisEmailParser.extractAmount(combined);
    if (amount == null || amount < 100) return null;

    final bankName = bankNameForPackage(packageName);
    final merchant = isIncome
        ? _extractSenderForIncome(combined, bankName)
        : _extractMerchant(combined, title, bankName);
    // Buat UID unik berbasis paket + menit + tipe + nominal + merchant agar tidak dobel
    final minuteBucket = timestamp.millisecondsSinceEpoch ~/ 60000;
    final uid =
        'notif:$packageName:$txType:$minuteBucket:$amount:${merchant.toLowerCase().hashCode}';

    final snippet = combined.length > 180
        ? '${combined.substring(0, 180)}...'
        : combined;

    return ParsedNotificationTx(
      uid: uid,
      bankName: bankName,
      merchantName: merchant,
      amount: amount,
      occurredAt: timestamp,
      title: title.isNotEmpty ? title : 'Notifikasi $bankName',
      snippet: snippet,
      txType: txType,
    );
  }

  static String _extractSenderForIncome(String combined, String bankName) {
    final m = RegExp(
      r'\b(?:dari|from)\s+([A-Za-z0-9][A-Za-z0-9\s&._\-/]{1,42}?)(?:\s+(?:berhasil|sukses|sebesar|senilai|ke|pada|rp\.?|idr)\b|[.,\r\n]|$)',
      caseSensitive: false,
    ).firstMatch(combined);
    if (m != null) {
      final name = (m.group(1) ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
      if (name.length >= 2 &&
          !name.toLowerCase().startsWith('rp') &&
          !RegExp(r'^[0-9.,\s]+$').hasMatch(name)) {
        return name;
      }
    }
    return 'Dana Masuk $bankName';
  }

  static String _extractMerchant(
    String combined,
    String title,
    String bankName,
  ) {
    final labeled = QrisEmailParser.extractMerchant(combined, title);
    if (labeled != null && labeled.isNotEmpty) return labeled;

    // Pola umum notifikasi: "Pembayaran Rp 25.000 di WARUNG GEPREK berhasil" atau "ke KOPI KENANGAN"
    final patterns = [
      RegExp(
        r'\b(?:di|ke|at|to)\s+([A-Za-z0-9][A-Za-z0-9\s&._\-/]{1,42}?)(?:\s+(?:berhasil|sukses|sebesar|senilai|dengan|menggunakan|via|pada|telah|rp\.?|idr)\b|[.,\r\n]|$)',
        caseSensitive: false,
      ),
      RegExp(
        r'\b(?:merchant|toko)\s+([A-Za-z0-9][A-Za-z0-9\s&._\-/]{1,42}?)(?:\s+(?:berhasil|sukses|sebesar|rp\.?|idr)\b|[.,\r\n]|$)',
        caseSensitive: false,
      ),
    ];

    for (final p in patterns) {
      final m = p.firstMatch(combined);
      if (m != null) {
        final name = (m.group(1) ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
        final lower = name.toLowerCase();
        if (name.length >= 2 &&
            !lower.startsWith('rp') &&
            !lower.startsWith('idr') &&
            lower != 'qris' &&
            lower != 'rekening' &&
            lower != 'akun' &&
            !RegExp(r'^[0-9.,\s]+$').hasMatch(name)) {
          return name;
        }
      }
    }

    return 'Transaksi $bankName';
  }
}
