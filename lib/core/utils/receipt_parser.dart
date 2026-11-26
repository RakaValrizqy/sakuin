import 'dart:convert';

class ParsedReceiptItem {
  const ParsedReceiptItem({
    required this.name,
    required this.totalPrice,
    this.quantity = 1,
    this.suggestedCategory,
  });

  final String name;
  final int totalPrice;
  final int quantity;
  final String? suggestedCategory;

  ParsedReceiptItem copyWith({
    String? name,
    int? totalPrice,
    int? quantity,
    String? suggestedCategory,
  }) {
    return ParsedReceiptItem(
      name: name ?? this.name,
      totalPrice: totalPrice ?? this.totalPrice,
      quantity: quantity ?? this.quantity,
      suggestedCategory: suggestedCategory ?? this.suggestedCategory,
    );
  }
}

class ParsedReceipt {
  const ParsedReceipt({
    required this.merchantName,
    required this.items,
    required this.tax,
    required this.serviceCharge,
    required this.discount,
    required this.declaredTotal,
    required this.engineUsed,
    this.occurredAt,
    this.rawText = '',
    this.fallbackNotice,
  });

  final String merchantName;
  final DateTime? occurredAt;
  final List<ParsedReceiptItem> items;
  final int tax;
  final int serviceCharge;
  final int discount;
  final int declaredTotal;
  final String rawText;
  final String engineUsed; // 'gemini' | 'mlkit_offline'
  final String? fallbackNotice;

  int get itemsSubtotal => items.fold(0, (s, item) => s + item.totalPrice);

  int get computedTotal {
    final calc = itemsSubtotal + tax + serviceCharge - discount;
    if (calc > 0) return calc;
    return declaredTotal > 0 ? declaredTotal : 0;
  }
}

/// Parser lokal offline untuk teks hasil Google ML Kit OCR (struk belanja Indonesia & e-receipt)
/// sekaligus parser JSON terstruktur untuk hasil opsional Gemini AI Vision.
class ReceiptParser {
  static final _ignoreLinePatterns = [
    RegExp(
      r'\b(tunai|cash|kembali|kembalian|change|bayar|dibayar)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(qris|debit|kredit|credit|visa|mastercard|flazz|emoney|brizzi|tapcash)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(gopay|ovo|dana|shopeepay|linkaja|bca|mandiri|bri|bni|bsi|seabank|jago)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(terima\s*kasih|thank\s*you|kasir|cashier|npwp|telp|tlp|wa:|ig:|www\.|http)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(no\.?\s*struk|no\.?\s*nota|invoice|receipt|order\s*id|ref\s*no|bill\s*no|meja|table)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'^(jl\.|jalan|ruko|komp\.|kec\.|kel\.|rt\s|rw\s|kota|kab\.)',
      caseSensitive: false,
    ),
    RegExp(
      r'^(qty|item|nama|barang|menu|harga|jumlah|total\s*item|total\s*qty)\b',
      caseSensitive: false,
    ),
  ];

  static final _totalRegex = RegExp(
    r'\b(grand\s*total|total\s*bayar|total\s*belanja|total\s*tagihan|jumlah\s*bayar|total\s*akhir|net\s*total|total\s*due|total)\b',
    caseSensitive: false,
  );
  static final _subtotalRegex = RegExp(
    r'\b(sub\s*-?\s*total|subtotal|harga\s*jual)\b',
    caseSensitive: false,
  );
  static final _taxRegex = RegExp(
    r'\b(ppn|pb\s*1|pajak|tax|vat|pph)\b',
    caseSensitive: false,
  );
  static final _serviceRegex = RegExp(
    r'\b(service(\s*charge)?|biaya\s*layanan|layanan|admin|ongkir|delivery|packaging)\b',
    caseSensitive: false,
  );
  static final _discountRegex = RegExp(
    r'\b(diskon|disc\.?|discount|promo|voucher|potongan|hemat|cashback)\b',
    caseSensitive: false,
  );

  // Harga di akhir baris (mis. "25.000", "Rp 25.000", "25,000", "-5.000", "(5.000)")
  static final _trailingAmountRegex = RegExp(
    r'([-+]?\s*\(?Rp\.?\s*[\d.,]+\)?|[-+]?\s*\(?\d{1,3}(?:[.,]\d{3})+\)?|[-+]?\s*\(?\d{3,8}\)?)\s*$',
    caseSensitive: false,
  );

  // Baris kuantitas gaya POS Indonesia (mis. "2 x 15.000   30.000" atau "2 PCS @15.000 30.000")
  static final _qtyPriceLineRegex = RegExp(
    r'^(\d{1,3})\s*(?:x|\*|pcs|pc|btl|box|pack|porsi|cup|gl[as]*)?\s*[@x*]?\s*(?:Rp\.?\s*)?([\d.,]+)\s+(?:Rp\.?\s*)?([\d.,]+)\s*$',
    caseSensitive: false,
  );

  static ParsedReceipt parseOcrText(
    String rawText, {
    String engineUsed = 'mlkit_offline',
    String? fallbackNotice,
  }) {
    final lines = rawText
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim().replaceAll(RegExp(r'\s{2,}'), '  '))
        .where((l) => l.isNotEmpty)
        .toList();

    final merchant = _extractMerchantName(lines);
    final occurredAt = _extractDate(rawText);

    final items = <ParsedReceiptItem>[];
    var tax = 0;
    var serviceCharge = 0;
    var discount = 0;
    var declaredTotal = 0;
    String? pendingItemName;

    for (final line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.length < 2) continue;

      // Cek baris summary lebih dulu (subtotal, diskon, pajak, service, grand total)
      if (_subtotalRegex.hasMatch(cleanLine)) {
        pendingItemName = null;
        continue;
      }
      if (_discountRegex.hasMatch(cleanLine)) {
        final amt = _extractLastAmount(cleanLine);
        if (amt != null && amt > 0) discount += amt;
        pendingItemName = null;
        continue;
      }
      if (_taxRegex.hasMatch(cleanLine)) {
        final amt = _extractLastAmount(cleanLine);
        if (amt != null && amt > 0) tax += amt;
        pendingItemName = null;
        continue;
      }
      if (_serviceRegex.hasMatch(cleanLine)) {
        final amt = _extractLastAmount(cleanLine);
        if (amt != null && amt > 0) serviceCharge += amt;
        pendingItemName = null;
        continue;
      }
      if (_totalRegex.hasMatch(cleanLine) &&
          !RegExp(
            r'total\s*(item|qty|pcs)',
            caseSensitive: false,
          ).hasMatch(cleanLine)) {
        final amt = _extractLastAmount(cleanLine);
        if (amt != null && amt > 0) {
          if (amt >= declaredTotal) declaredTotal = amt;
        }
        pendingItemName = null;
        continue;
      }

      // Lewati baris pembayaran, header alamat, kasir, dll.
      if (_shouldIgnoreLine(cleanLine)) {
        pendingItemName = null;
        continue;
      }

      // Format 2 baris POS Indonesia: baris 1 = nama item, baris 2 = "2 x 15.000  30.000"
      final qtyMatch = _qtyPriceLineRegex.firstMatch(cleanLine);
      if (qtyMatch != null && pendingItemName != null) {
        final qty = int.tryParse(qtyMatch.group(1) ?? '1') ?? 1;
        final total = _parseRupiahToken(qtyMatch.group(3) ?? '');
        if (total != null && total >= 100 && total <= 500000000) {
          items.add(
            ParsedReceiptItem(
              name: _cleanItemName(pendingItemName),
              quantity: qty.clamp(1, 999),
              totalPrice: total,
            ),
          );
          pendingItemName = null;
          continue;
        }
      }

      // Format 1 baris: "2x Es Teh Manis  10.000" atau "Nasi Goreng  25.000"
      final amountMatch = _trailingAmountRegex.firstMatch(cleanLine);
      if (amountMatch != null) {
        final rawAmtToken = amountMatch.group(1) ?? '';
        final isNegative =
            rawAmtToken.contains('-') ||
            (rawAmtToken.contains('(') && rawAmtToken.contains(')'));
        final parsedAmt = _parseRupiahToken(rawAmtToken);
        final leftPart = cleanLine.substring(0, amountMatch.start).trim();

        if (parsedAmt != null && parsedAmt >= 100 && parsedAmt <= 500000000) {
          if (isNegative) {
            discount += parsedAmt;
            pendingItemName = null;
            continue;
          }
          if (leftPart.isNotEmpty && _looksLikeItemName(leftPart)) {
            final parsedLeft = _extractQtyAndName(leftPart);
            if (parsedLeft.name.isNotEmpty) {
              items.add(
                ParsedReceiptItem(
                  name: parsedLeft.name,
                  quantity: parsedLeft.qty,
                  totalPrice: parsedAmt,
                ),
              );
              pendingItemName = null;
              continue;
            }
          } else if (pendingItemName != null &&
              RegExp(
                r'^\d{1,3}\s*(?:x|\*|pcs)?$',
                caseSensitive: false,
              ).hasMatch(leftPart)) {
            final qty =
                int.tryParse(leftPart.replaceAll(RegExp(r'[^0-9]'), '')) ?? 1;
            items.add(
              ParsedReceiptItem(
                name: _cleanItemName(pendingItemName),
                quantity: qty.clamp(1, 999),
                totalPrice: parsedAmt,
              ),
            );
            pendingItemName = null;
            continue;
          }
        }
      }

      // Simpan sebagai kandidat nama barang untuk baris kuantitas/harga berikutnya
      if (_looksLikeItemName(cleanLine) &&
          !_looksLikeDateOrHeader(cleanLine) &&
          cleanLine != merchant) {
        pendingItemName = cleanLine;
      } else {
        pendingItemName = null;
      }
    }

    // Jika tidak ada item terdeteksi tapi total ada (mis. screenshot QRIS), buat 1 item ringkasan
    if (items.isEmpty && declaredTotal > 0) {
      items.add(
        ParsedReceiptItem(
          name: merchant.isNotEmpty ? merchant : 'Belanja Struk',
          totalPrice: declaredTotal,
        ),
      );
    }

    // Jika total tidak tercetak/terbaca tapi item berhasil terbaca, hitung dari subtotal
    if (declaredTotal <= 0 && items.isNotEmpty) {
      final sum =
          items.fold<int>(0, (s, e) => s + e.totalPrice) +
          tax +
          serviceCharge -
          discount;
      if (sum > 0) declaredTotal = sum;
    }

    return ParsedReceipt(
      merchantName: merchant.isEmpty ? 'Struk Belanja' : merchant,
      occurredAt: occurredAt,
      items: items,
      tax: tax,
      serviceCharge: serviceCharge,
      discount: discount,
      declaredTotal: declaredTotal,
      rawText: rawText,
      engineUsed: engineUsed,
      fallbackNotice: fallbackNotice,
    );
  }

  /// Parse JSON terstruktur yang dikembalikan oleh Gemini AI Vision.
  static ParsedReceipt? parseGeminiJson(
    String responseText, {
    String rawFallbackText = '',
  }) {
    var cleaned = responseText.trim();
    // Buang code fence ```json ... ``` jika ada
    final fenceMatch = RegExp(
      r'```(?:json)?\s*([\s\S]*?)\s*```',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (fenceMatch != null) {
      cleaned = fenceMatch.group(1)?.trim() ?? cleaned;
    }
    final firstBrace = cleaned.indexOf('{');
    final lastBrace = cleaned.lastIndexOf('}');
    if (firstBrace < 0 || lastBrace <= firstBrace) return null;
    cleaned = cleaned.substring(firstBrace, lastBrace + 1);

    final decoded = jsonDecode(cleaned);
    if (decoded is! Map<String, dynamic>) return null;

    final merchant =
        (decoded['merchantName'] as String?)?.trim().isNotEmpty == true
        ? (decoded['merchantName'] as String).trim()
        : 'Struk Belanja';

    DateTime? occurredAt;
    final dateStr = (decoded['date'] as String?)?.trim();
    if (dateStr != null && dateStr.isNotEmpty) {
      occurredAt =
          DateTime.tryParse(dateStr)?.toLocal() ?? _extractDate(dateStr);
    }

    final rawItems = (decoded['items'] as List?) ?? const [];
    final items = <ParsedReceiptItem>[];
    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final name = (raw['name'] as String?)?.trim() ?? '';
      final totalPrice = _asInt(raw['totalPrice']) ?? _asInt(raw['price']) ?? 0;
      final qty = (_asInt(raw['quantity']) ?? 1).clamp(1, 999);
      final category = (raw['category'] as String?)?.trim();
      if (name.isNotEmpty && totalPrice > 0) {
        items.add(
          ParsedReceiptItem(
            name: name,
            quantity: qty,
            totalPrice: totalPrice,
            suggestedCategory: (category != null && category.isNotEmpty)
                ? category
                : null,
          ),
        );
      }
    }

    final tax = (_asInt(decoded['tax']) ?? 0).abs();
    final serviceCharge = (_asInt(decoded['serviceCharge']) ?? 0).abs();
    final discount = (_asInt(decoded['discount']) ?? 0).abs();
    var declaredTotal = (_asInt(decoded['total']) ?? 0).abs();

    if (items.isEmpty && declaredTotal > 0) {
      items.add(ParsedReceiptItem(name: merchant, totalPrice: declaredTotal));
    }
    if (declaredTotal <= 0 && items.isNotEmpty) {
      final sum =
          items.fold<int>(0, (s, e) => s + e.totalPrice) +
          tax +
          serviceCharge -
          discount;
      if (sum > 0) declaredTotal = sum;
    }

    if (items.isEmpty && declaredTotal <= 0) return null;

    return ParsedReceipt(
      merchantName: merchant,
      occurredAt: occurredAt,
      items: items,
      tax: tax,
      serviceCharge: serviceCharge,
      discount: discount,
      declaredTotal: declaredTotal,
      rawText: rawFallbackText,
      engineUsed: 'gemini',
    );
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return _parseRupiahToken(value);
    return null;
  }

  static bool _shouldIgnoreLine(String line) {
    for (final p in _ignoreLinePatterns) {
      if (p.hasMatch(line)) return true;
    }
    return false;
  }

  static bool _looksLikeDateOrHeader(String line) {
    if (RegExp(r'\d{1,2}[/\-.]\d{1,2}[/\-.]\d{2,4}').hasMatch(line)) {
      return true;
    }
    if (RegExp(r'^[-=*_.\s]{3,}$').hasMatch(line)) return true;
    return false;
  }

  static bool _looksLikeItemName(String text) {
    final letters = RegExp(r'[A-Za-z]').allMatches(text).length;
    if (letters < 2) return false;
    if (text.length > 64) return false;
    if (_shouldIgnoreLine(text)) return false;
    return true;
  }

  static String _extractMerchantName(List<String> lines) {
    for (final line in lines.take(6)) {
      if (line.length < 3 || line.length > 48) continue;
      if (_looksLikeDateOrHeader(line)) continue;
      if (_shouldIgnoreLine(line)) continue;
      if (_trailingAmountRegex.hasMatch(line) &&
          (_extractLastAmount(line) ?? 0) >= 1000) {
        continue;
      }
      final letters = RegExp(r'[A-Za-z]').allMatches(line).length;
      if (letters >= 3) {
        return line.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    }
    return 'Struk Belanja';
  }

  static DateTime? _extractDate(String text) {
    // 1. YYYY-MM-DD
    final iso = RegExp(r'\b(20\d{2})[-/](\d{1,2})[-/](\d{1,2})\b')
        .firstMatch(text);
    if (iso != null) {
      final y = int.parse(iso.group(1)!);
      final m = int.parse(iso.group(2)!);
      final d = int.parse(iso.group(3)!);
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
        return DateTime(y, m, d);
      }
    }
    // 2. DD/MM/YYYY atau DD-MM-YY
    final dmy = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b')
        .firstMatch(text);
    if (dmy != null) {
      final d = int.parse(dmy.group(1)!);
      final m = int.parse(dmy.group(2)!);
      var y = int.parse(dmy.group(3)!);
      if (y < 100) y += 2000;
      if (m >= 1 && m <= 12 && d >= 1 && d <= 31 && y >= 2020 && y <= 2100) {
        return DateTime(y, m, d);
      }
    }
    // 3. DD MMM YYYY (Indonesia / Inggris)
    final named = RegExp(
      r'\b(\d{1,2})\s+(jan|feb|mar|apr|mei|may|jun|jul|agu|aug|sep|okt|oct|nov|des|dec)[a-z]*\s+(20\d{2})\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (named != null) {
      final d = int.parse(named.group(1)!);
      final monKey = named.group(2)!.toLowerCase();
      final y = int.parse(named.group(3)!);
      const monMap = {
        'jan': 1,
        'feb': 2,
        'mar': 3,
        'apr': 4,
        'mei': 5,
        'may': 5,
        'jun': 6,
        'jul': 7,
        'agu': 8,
        'aug': 8,
        'sep': 9,
        'okt': 10,
        'oct': 10,
        'nov': 11,
        'des': 12,
        'dec': 12,
      };
      final m = monMap[monKey];
      if (m != null && d >= 1 && d <= 31) {
        return DateTime(y, m, d);
      }
    }
    return null;
  }

  static int? _extractLastAmount(String line) {
    final m = _trailingAmountRegex.firstMatch(line);
    if (m == null) return null;
    return _parseRupiahToken(m.group(1) ?? '');
  }

  static int? _parseRupiahToken(String raw) {
    var clean = raw
        .replaceAll(RegExp(r'[Rp\s()+-]', caseSensitive: false), '')
        .trim();
    if (clean.isEmpty) return null;

    // Hapus sen ",00" atau ".00" di akhir jika ada (mis. "25.000,00" atau "25,000.00")
    if (RegExp(r'[.,]\d{2}$').hasMatch(clean) && clean.length > 3) {
      final sep = clean[clean.length - 3];
      final beforeSep = clean.substring(0, clean.length - 3);
      if (beforeSep.contains(sep == ',' ? '.' : ',') || beforeSep.length <= 3) {
        clean = beforeSep;
      }
    }

    final digits = clean.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    return int.tryParse(digits);
  }

  static ({int qty, String name}) _extractQtyAndName(String left) {
    var cleaned = left.trim();
    var qty = 1;

    // Prefix qty: "2x Nasi Goreng", "2 x Es Teh", "2 Nasi Goreng"
    final prefix = RegExp(
      r'^(\d{1,3})\s*(?:x|\*)?\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (prefix != null) {
      final parsedQty = int.tryParse(prefix.group(1) ?? '1') ?? 1;
      if (parsedQty >= 1 && parsedQty <= 99) {
        qty = parsedQty;
        cleaned = prefix.group(2)!.trim();
      }
    }

    // Hapus harga satuan di belakang nama item (mis. "Indomie Goreng  2  3.500")
    cleaned = cleaned.replaceAll(
      RegExp(r'\s+\d{1,3}\s*(?:x|\*|@)?\s*[\d.,]+$', caseSensitive: false),
      '',
    );
    cleaned = cleaned.replaceAll(
      RegExp(r'\s+@\s*[\d.,]+$', caseSensitive: false),
      '',
    );

    return (qty: qty, name: _cleanItemName(cleaned));
  }

  static String _cleanItemName(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
