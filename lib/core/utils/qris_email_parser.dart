import 'dart:convert';

class ParsedQrisEmail {
  const ParsedQrisEmail({
    required this.bankName,
    required this.merchantName,
    required this.amount,
    required this.occurredAt,
    required this.snippet,
  });

  final String bankName;
  final String merchantName;
  final int amount;
  final DateTime occurredAt;
  final String snippet;
}

/// Parser email transaksi QRIS bank & e-wallet Indonesia (pure Dart, tanpa dependensi tambahan).
class QrisEmailParser {
  QrisEmailParser._();

  static const Map<String, List<String>> _bankKeywords = {
    'Mandiri': ['mandiri', 'livin'],
    'BCA': ['bca', 'mybca', 'klikbca'],
    'BRI': ['bri', 'brimo'],
    'BNI': ['bni', 'wondr'],
    'BSI': ['bsi', 'bankbsi', 'byond'],
    'GoPay': ['gopay', 'gojek'],
    'OVO': ['ovo'],
    'DANA': ['dana.id', 'dana'],
    'ShopeePay': ['shopeepay', 'shopee'],
    'SeaBank': ['seabank'],
    'Jago': ['jago'],
    'Blu': ['blubybcadigital', 'blu by bca'],
    'CIMB': ['cimb', 'octo'],
    'Permata': ['permata'],
    'Jenius': ['jenius', 'btpn'],
    'LinkAja': ['linkaja'],
  };

  static const List<String> _rejectKeywords = [
    'kode otp',
    'otp anda',
    'verification code',
    'kode verifikasi',
    'transaksi gagal',
    'pembayaran gagal',
    'qris gagal',
    'dibatalkan',
    'login dari perangkat',
    'reset password',
    'promo ',
    'diskon hingga',
    'cashback hingga',
    'newsletter',
  ];

  static final RegExp _failedWordRegex = RegExp(
    r'\b(gagal|failed|ditolak|dibatalkan|declined|expired)\b',
    caseSensitive: false,
  );

  static const List<String> _qrisPositiveKeywords = [
    'qris',
    'qr payment',
    'pembayaran qr',
    'bayar qr',
    'scan qr',
    'transaksi berhasil',
    'pembayaran berhasil',
    'bukti transaksi',
    'notifikasi transaksi',
    'payment successful',
    'payment receipt',
  ];

  /// Filter cepat berdasarkan header FROM + SUBJECT agar hanya mengunduh body email relevan.
  static bool isLikelyQrisHeader(String from, String subject) {
    final combined = '${from.toLowerCase()} ${subject.toLowerCase()}';
    for (final reject in _rejectKeywords) {
      if (combined.contains(reject)) return false;
    }

    final hasBank = detectBankName(from, subject, '') != 'QRIS';
    final hasQrisWord = _qrisPositiveKeywords.any(combined.contains);

    if (combined.contains('qris')) return true;
    return hasBank && hasQrisWord;
  }

  static String detectBankName(String from, String subject, String body) {
    final header = '${from.toLowerCase()} ${subject.toLowerCase()}';
    for (final entry in _bankKeywords.entries) {
      for (final kw in entry.value) {
        if (header.contains(kw)) return entry.key;
      }
    }
    final lowerBody = body.toLowerCase();
    for (final entry in _bankKeywords.entries) {
      for (final kw in entry.value) {
        if (lowerBody.contains(kw)) return entry.key;
      }
    }
    return 'QRIS';
  }

  /// Parse email transaksi QRIS menjadi nominal, nama merchant, bank, dan tanggal.
  /// Mengembalikan `null` jika email bukan transaksi pengeluaran QRIS yang valid.
  static ParsedQrisEmail? parse({
    required String from,
    required String subject,
    required String rawBody,
    DateTime? emailDate,
  }) {
    final cleanText = normalizeEmailBody(rawBody);
    final lowerAll = '${subject.toLowerCase()}\n${cleanText.toLowerCase()}';

    for (final reject in _rejectKeywords) {
      if (lowerAll.contains(reject)) return null;
    }
    if (_failedWordRegex.hasMatch(subject) ||
        _failedWordRegex.hasMatch(cleanText)) {
      return null;
    }

    // Wajib mengandung indikasi QRIS atau pembayaran ke merchant
    final hasQris =
        lowerAll.contains('qris') ||
        lowerAll.contains('pembayaran qr') ||
        lowerAll.contains('qr payment') ||
        lowerAll.contains('scan qr');
    if (!hasQris) return null;

    // Pastikan bukan email pemasukan/terima dana QRIS merchant
    if (lowerAll.contains('dana masuk') ||
        lowerAll.contains('anda menerima') ||
        lowerAll.contains('uang masuk')) {
      return null;
    }

    final amount = extractAmount(cleanText) ?? extractAmount(subject);
    if (amount == null || amount <= 0) return null;

    final bankName = detectBankName(from, subject, cleanText);
    final merchant = extractMerchant(cleanText, subject) ?? 'Pembayaran QRIS';
    final snippet = cleanText.length > 180
        ? '${cleanText.substring(0, 180)}...'
        : cleanText;

    return ParsedQrisEmail(
      bankName: bankName,
      merchantName: merchant,
      amount: amount,
      occurredAt: emailDate ?? DateTime.now(),
      snippet: snippet,
    );
  }

  /// Ekstrak nominal Rupiah dari teks email (prioritaskan label Total/Nominal/Jumlah).
  static int? extractAmount(String text) {
    final labeledPatterns = [
      RegExp(
        r'(?:total\s*(?:pembayaran|transaksi|bayar|tagihan)?|nominal\s*(?:transaksi)?|jumlah\s*(?:pembayaran|transaksi)?|amount|nilai\s*transaksi)\s*[:\-]?\s*(?:rp\.?|idr)\s*([0-9][0-9.,]*)',
        caseSensitive: false,
      ),
      RegExp(r'(?:rp\.?|idr)\s*([0-9][0-9.,]*)', caseSensitive: false),
    ];

    for (final regex in labeledPatterns) {
      final matches = regex.allMatches(text);
      for (final m in matches) {
        final rawNum = m.group(1);
        if (rawNum == null) continue;
        final parsed = _parseRupiahNumber(rawNum);
        if (parsed != null && parsed >= 100 && parsed <= 1000000000) {
          return parsed;
        }
      }
    }
    return null;
  }

  static int? _parseRupiahNumber(String raw) {
    var s = raw.trim();
    // Hapus desimal sen (,00 atau .00 di akhir)
    if (RegExp(r'[,.]\d{2}$').hasMatch(s)) {
      s = s.substring(0, s.length - 3);
    }
    // Hapus pemisah ribuan (. atau ,)
    final digitsOnly = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return null;
    return int.tryParse(digitsOnly);
  }

  static String? extractMerchant(String body, String subject) {
    final patterns = [
      RegExp(
        r'(?:nama\s*merchant|merchant\s*name|merchant|dibayarkan\s*ke|bayar\s*ke|penerima|kepada|nama\s*toko|outlet|tujuan)\s*[:\-]\s*([^\n\r|]{2,60})',
        caseSensitive: false,
      ),
      RegExp(
        r'(?:pembayaran\s+qris\s+ke|bayar\s+qris\s+di|transaksi\s+di)\s+([^\n\r.,]{2,50})',
        caseSensitive: false,
      ),
    ];

    for (final p in patterns) {
      final match = p.firstMatch(body) ?? p.firstMatch(subject);
      if (match != null) {
        var name = (match.group(1) ?? '').trim();
        // Bersihkan teks ikutan yang tidak perlu
        name = name.replaceAll(RegExp(r'\s{2,}'), ' ');
        if (name.length >= 2 &&
            !name.toLowerCase().startsWith('rp') &&
            !RegExp(r'^[0-9.,\s]+$').hasMatch(name)) {
          return name;
        }
      }
    }
    return null;
  }

  /// Decode Quoted-Printable, Base64 MIME, RFC 2047 header, dan bersihkan tag HTML.
  static String decodeRfc2047(String input) {
    final regex = RegExp(
      r'=\?([^?]+)\?([bBqQ])\?([^?]*)\?=',
      caseSensitive: false,
    );
    return input.replaceAllMapped(regex, (m) {
      final encoding = (m.group(2) ?? '').toUpperCase();
      final payload = m.group(3) ?? '';
      try {
        if (encoding == 'B') {
          return utf8.decode(base64.decode(payload), allowMalformed: true);
        }
        if (encoding == 'Q') {
          return decodeQuotedPrintable(payload.replaceAll('_', ' '));
        }
      } catch (_) {}
      return m.group(0) ?? '';
    });
  }

  static String decodeQuotedPrintable(String input) {
    final softJoined = input.replaceAll(RegExp(r'=\r?\n'), '');
    final bytes = <int>[];
    for (var i = 0; i < softJoined.length; i++) {
      if (softJoined[i] == '=' && i + 2 < softJoined.length) {
        final hex = softJoined.substring(i + 1, i + 3);
        final val = int.tryParse(hex, radix: 16);
        if (val != null) {
          bytes.add(val);
          i += 2;
          continue;
        }
      }
      bytes.add(softJoined.codeUnitAt(i));
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String normalizeEmailBody(String rawBody) {
    var text = rawBody;

    // Jika multipart MIME dengan bagian base64, coba decode bagian text/plain atau text/html
    if (text.contains('Content-Transfer-Encoding: base64') ||
        text.contains('Content-Transfer-Encoding: BASE64')) {
      text = _decodeMimeBase64Blocks(text);
    }
    if (RegExp(r'=(?:[0-9A-Fa-f]{2}|\r?\n)').hasMatch(text)) {
      text = decodeQuotedPrintable(text);
    }

    // Hapus tag style & script beserta isinya
    text = text.replaceAll(
      RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
      ' ',
    );
    text = text.replaceAll(
      RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
      ' ',
    );
    // Ubah pemisah blok HTML menjadi newline agar regex `Label : Value` tetap rapi per baris
    text = text.replaceAll(
      RegExp(r'</(?:tr|p|div|li|br|h[1-6])>', caseSensitive: false),
      '\n',
    );
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(
      RegExp(r'</td>\s*<td[^>]*>', caseSensitive: false),
      ': ',
    );
    text = text.replaceAll(RegExp(r'<[^>]+>'), ' ');

    // Entity HTML umum
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");

    // Rapikan spasi berlebih sambil menjaga baris
    final lines = text
        .split(RegExp(r'\r?\n'))
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join('\n');
  }

  static String _decodeMimeBase64Blocks(String raw) {
    final blockRegex = RegExp(
      r'Content-Transfer-Encoding:\s*base64[\r\n]+(?:[^\r\n:]+:[^\r\n]*[\r\n]+)*[\r\n]+([A-Za-z0-9+/=\r\n]+)',
      caseSensitive: false,
    );
    return raw.replaceAllMapped(blockRegex, (m) {
      final b64 = (m.group(1) ?? '').replaceAll(RegExp(r'\s+'), '');
      if (b64.length < 16) return m.group(0) ?? '';
      try {
        return utf8.decode(base64.decode(b64), allowMalformed: true);
      } catch (_) {
        return m.group(0) ?? '';
      }
    });
  }

  /// Parse header Date email (RFC 2822, mis. `Thu, 26 Nov 2026 12:30:00 +0700`).
  static DateTime? parseEmailDate(String rawDate) {
    final regex = RegExp(
      r'(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|UTC|GMT)?',
      caseSensitive: false,
    );
    final m = regex.firstMatch(rawDate);
    if (m == null) return null;

    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    final day = int.parse(m.group(1)!);
    final month = months[m.group(2)!.toLowerCase()] ?? 1;
    final year = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = int.tryParse(m.group(6) ?? '0') ?? 0;
    final tzStr = m.group(7) ?? '+0000';

    var utc = DateTime.utc(year, month, day, hour, minute, second);
    if (tzStr.startsWith('+') || tzStr.startsWith('-')) {
      final sign = tzStr.startsWith('+') ? 1 : -1;
      final tzHours = int.tryParse(tzStr.substring(1, 3)) ?? 0;
      final tzMins = int.tryParse(tzStr.substring(3, 5)) ?? 0;
      utc = utc.subtract(
        Duration(hours: sign * tzHours, minutes: sign * tzMins),
      );
    }
    return utc.toLocal();
  }
}
