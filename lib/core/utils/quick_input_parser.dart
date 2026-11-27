import 'package:sakuin/core/db/app_database.dart';

/// Hasil uraian input cepat 1 baris (100% lokal/offline).
/// Contoh: "kopi susu 18rb @kopi kenangan gopay harian"
class QuickParsedTransaction {
  const QuickParsedTransaction({
    required this.type,
    required this.amount,
    this.itemName,
    this.merchantName,
    this.walletId,
    this.walletName,
    this.pocketId,
    this.pocketName,
    this.categoryId,
    this.note = '',
  });

  final String type; // 'expense' | 'income'
  final int amount;
  final String? itemName;
  final String? merchantName;
  final int? walletId;
  final String? walletName;
  final int? pocketId;
  final String? pocketName;
  final int? categoryId;
  final String note;

  bool get canQuickSave => amount > 0 && walletId != null;
}

class QuickInputParser {
  QuickInputParser._();

  static const List<String> _incomeKeywords = [
    'gaji',
    'sangu',
    'bonus',
    'thr',
    'hadiah',
    'freelance',
    'pemasukan',
    'uang masuk',
    'dana masuk',
    'transfer masuk',
    'terima uang',
    'cashback',
    'reimburse',
    'beasiswa',
    'komisi',
  ];

  /// Urai 1 baris teks natural menjadi transaksi terstruktur secara offline.
  static QuickParsedTransaction parse({
    required String rawInput,
    required List<WalletWithBalance> wallets,
    required List<PocketWithBalance> pockets,
    List<ItemMemoryData> itemMemories = const [],
    List<MerchantMemoryData> merchantMemories = const [],
    int? defaultWalletId,
  }) {
    var working = rawInput.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (working.isEmpty) {
      return const QuickParsedTransaction(type: 'expense', amount: 0);
    }

    // 1. Deteksi tipe transaksi (pemasukan vs pengeluaran)
    final lowerAll = working.toLowerCase();
    var type = _incomeKeywords.any((kw) => _containsPhrase(lowerAll, kw))
        ? 'income'
        : 'expense';

    // 2. Ekstrak nominal (dukungan: 18rb, 18k, 1,5jt, 25.000, Rp 20000)
    int amount = 0;
    final amountResult = _extractAmount(working);
    if (amountResult != null) {
      amount = amountResult.amount;
      working = amountResult.remaining;
    }

    // 3. Ekstrak merchant eksplisit via "@Nama Merchant" atau "di Nama Merchant"
    String? merchantName;
    final atMatch = RegExp(
      r'@(?:"([^"]+)"|([A-Za-z0-9][A-Za-z0-9._\-]*(?:\s+[A-Za-z0-9._\-]+){0,2}))',
    ).firstMatch(working);
    if (atMatch != null) {
      merchantName = (atMatch.group(1) ?? atMatch.group(2))?.trim();
      working =
          '${working.substring(0, atMatch.start)} ${working.substring(atMatch.end)}'
              .trim()
              .replaceAll(RegExp(r'\s+'), ' ');
    }

    // 4. Cocokkan nama Dompet / Saku aktif (prioritas nama terpanjang dulu)
    int? matchedWalletId;
    String? matchedWalletName;
    final sortedWallets = [...wallets]
      ..sort((a, b) => b.wallet.name.length.compareTo(a.wallet.name.length));
    for (final wb in sortedWallets) {
      final wName = wb.wallet.name.trim();
      if (wName.isEmpty) continue;
      final removed = _removePhraseToken(working, wName);
      if (removed != null) {
        matchedWalletId = wb.wallet.id;
        matchedWalletName = wName;
        working = removed;
        break;
      }
    }

    // 5. Cocokkan nama Pos Budget (prioritas di dompet yang cocok jika ada)
    int? matchedPocketId;
    String? matchedPocketName;
    final candidatePockets = matchedWalletId != null
        ? [
            ...pockets.where((p) => p.pocket.walletId == matchedWalletId),
            ...pockets.where((p) => p.pocket.walletId != matchedWalletId),
          ]
        : [...pockets];
    candidatePockets.sort(
      (a, b) => b.pocket.name.length.compareTo(a.pocket.name.length),
    );

    for (final p in candidatePockets) {
      final pName = p.pocket.name.trim();
      if (pName.isEmpty) continue;
      final aliases = _pocketAliases(pName);
      for (final alias in aliases) {
        final removed = _removePhraseToken(working, alias);
        if (removed != null) {
          matchedPocketId = p.pocket.id;
          matchedPocketName = pName;
          matchedWalletId ??= p.pocket.walletId;
          working = removed;
          break;
        }
      }
      if (matchedPocketId != null) break;
    }

    // Pastikan jika dompet terpilih dan pos terpilih berbeda dompet, cari pos bernama sama di dompet terpilih
    if (matchedWalletId != null && matchedPocketId != null) {
      final currentPocket = pockets
          .where((p) => p.pocket.id == matchedPocketId)
          .firstOrNull;
      if (currentPocket != null &&
          currentPocket.pocket.walletId != matchedWalletId) {
        final sameNameInWallet = pockets
            .where(
              (p) =>
                  p.pocket.walletId == matchedWalletId &&
                  p.pocket.name.trim().toLowerCase() ==
                      currentPocket.pocket.name.trim().toLowerCase(),
            )
            .firstOrNull;
        if (sameNameInWallet != null) {
          matchedPocketId = sameNameInWallet.pocket.id;
          matchedPocketName = sameNameInWallet.pocket.name;
        }
      }
    }

    // 6. Bersihkan sisa teks sebagai Nama Item
    var cleanText = working
        .replaceAll(RegExp(r'^[\s\-•,;:]+|[\s\-•,;:]+$'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    // Hapus kata sambung penutup tersisa ("di", "ke", "pakai", "pake", "dari")
    cleanText = cleanText
        .replaceFirst(
          RegExp(
            r'\s+(?:di|ke|pakai|pake|dari|via|untuk|buat)$',
            caseSensitive: false,
          ),
          '',
        )
        .trim();

    String? itemName = cleanText.isEmpty ? null : _capitalizeFirst(cleanText);
    int? categoryId;
    String note = '';

    // 7. Lengkapi otomatis dari ItemMemory & MerchantMemory jika ada pasangan yang dikenal
    if (itemName != null) {
      final normItem = AppDatabase.normalizeItemName(itemName);
      final exactItem = itemMemories
          .where((m) => m.nameNormalized == normItem)
          .firstOrNull;
      final fuzzyItem =
          exactItem ??
          itemMemories
              .where(
                (m) =>
                    m.nameNormalized.length >= 3 &&
                    (normItem.contains(m.nameNormalized) ||
                        m.nameNormalized.contains(normItem)),
              )
              .firstOrNull;
      if (fuzzyItem != null) {
        if (amount <= 0) amount = fuzzyItem.lastAmount;
        merchantName ??= fuzzyItem.lastMerchantName;
        categoryId ??= fuzzyItem.lastCategoryId;
        matchedWalletId ??= fuzzyItem.lastWalletId;
        matchedPocketId ??= fuzzyItem.lastPocketId;
        note = fuzzyItem.lastNote;
        type = fuzzyItem.type;
      }
    }

    // Cek MerchantMemory (baik dari @merchant maupun teks yang cocok dengan merchant)
    final merchantLookupKey = merchantName ?? itemName;
    if (merchantLookupKey != null) {
      final normMerch = AppDatabase.normalizeItemName(merchantLookupKey);
      final matchMerch = merchantMemories
          .where(
            (m) =>
                m.merchantNormalized == normMerch ||
                (m.merchantNormalized.length >= 3 &&
                    (normMerch.contains(m.merchantNormalized) ||
                        m.merchantNormalized.contains(normMerch))),
          )
          .firstOrNull;
      if (matchMerch != null) {
        merchantName ??= matchMerch.displayMerchant;
        // Jika pengguna hanya mengetik nama merchant (mis. "kopi kenangan 22rb"),
        // isi otomatis nama item terakhir dari merchant itu
        if (itemName == null ||
            AppDatabase.normalizeItemName(itemName) ==
                matchMerch.merchantNormalized) {
          itemName = matchMerch.lastItemName ?? itemName;
        }
        if (amount <= 0) amount = matchMerch.lastAmount;
        categoryId ??= matchMerch.lastCategoryId;
        matchedWalletId ??= matchMerch.lastWalletId;
        matchedPocketId ??= matchMerch.lastPocketId;
        if (note.isEmpty) note = matchMerch.lastNote;
      }
    }

    // 8. Fallback dompet default jika belum disebut & pastikan nama dompet/pos terisi
    if (matchedWalletId == null ||
        !wallets.any((w) => w.wallet.id == matchedWalletId)) {
      if (defaultWalletId != null &&
          wallets.any((w) => w.wallet.id == defaultWalletId)) {
        matchedWalletId = defaultWalletId;
      } else if (wallets.isNotEmpty) {
        matchedWalletId = wallets.first.wallet.id;
      }
    }
    if (matchedWalletId != null) {
      matchedWalletName = wallets
          .where((w) => w.wallet.id == matchedWalletId)
          .firstOrNull
          ?.wallet
          .name;
    }
    if (matchedPocketId != null) {
      final pObj = pockets
          .where(
            (p) =>
                p.pocket.id == matchedPocketId &&
                p.pocket.walletId == matchedWalletId,
          )
          .firstOrNull;
      if (pObj != null) {
        matchedPocketName = pObj.pocket.name;
      } else {
        matchedPocketId = null;
        matchedPocketName = null;
      }
    }

    return QuickParsedTransaction(
      type: type,
      amount: amount,
      itemName: itemName,
      merchantName: merchantName,
      walletId: matchedWalletId,
      walletName: matchedWalletName,
      pocketId: matchedPocketId,
      pocketName: matchedPocketName,
      categoryId: categoryId,
      note: note,
    );
  }

  static List<String> _pocketAliases(String pocketName) {
    final lower = pocketName.trim().toLowerCase();
    final aliases = <String>[pocketName.trim()];
    // Shorthand pintar untuk nama pos umum di Indonesia
    if (lower == 'uang harian') aliases.add('harian');
    if (lower == 'dana darurat') aliases.add('darurat');
    if (lower == 'life style') aliases.add('lifestyle');
    if (lower == 'lifestyle') aliases.add('life style');
    return aliases;
  }

  static bool _containsPhrase(String lowerText, String phrase) {
    final escaped = RegExp.escape(phrase.toLowerCase());
    return RegExp('(?:^|\\s)$escaped(?:\\s|\$)').hasMatch(lowerText);
  }

  static String? _removePhraseToken(String input, String phrase) {
    final escaped = RegExp.escape(phrase.trim());
    final re = RegExp(
      '(?:^|\\s)(?:(?:pakai|pake|dari|via|di|ke)\\s+)?$escaped(?=\$|\\s|[.,;])',
      caseSensitive: false,
    );
    final match = re.firstMatch(input);
    if (match == null) return null;
    final next =
        '${input.substring(0, match.start)} ${input.substring(match.end)}'
            .trim()
            .replaceAll(RegExp(r'\s+'), ' ');
    return next;
  }

  static ({int amount, String remaining})? _extractAmount(String input) {
    // 1. Pola dengan satuan (rb / ribu / k / jt / juta)
    final unitRe = RegExp(
      r'(?:^|\s)(?:rp\.?\s*)?(\d+(?:[.,]\d+)?)\s*(jt|juta|rb|ribu|k)(?=$|\s|[.,;])',
      caseSensitive: false,
    );
    final unitMatch = unitRe.firstMatch(input);
    if (unitMatch != null) {
      final numStr = unitMatch.group(1)!.replaceAll(',', '.');
      final unit = unitMatch.group(2)!.toLowerCase();
      final val = double.tryParse(numStr);
      if (val != null && val > 0) {
        final mult = (unit == 'jt' || unit == 'juta') ? 1000000 : 1000;
        final amount = (val * mult).round();
        final rem =
            '${input.substring(0, unitMatch.start)} ${input.substring(unitMatch.end)}'
                .trim()
                .replaceAll(RegExp(r'\s+'), ' ');
        return (amount: amount, remaining: rem);
      }
    }

    // 2. Pola nominal polos bertitik (25.000) atau >= 3 digit dengan/tanpa Rp
    final plainRe = RegExp(
      r'(?:^|\s)(?:rp\.?\s*)?(\d{1,3}(?:\.\d{3})+|\d{3,})(?=$|\s|[.,;])',
      caseSensitive: false,
    );
    final plainMatch = plainRe.firstMatch(input);
    if (plainMatch != null) {
      final digits = plainMatch.group(1)!.replaceAll('.', '');
      final amount = int.tryParse(digits);
      if (amount != null && amount > 0) {
        final rem =
            '${input.substring(0, plainMatch.start)} ${input.substring(plainMatch.end)}'
                .trim()
                .replaceAll(RegExp(r'\s+'), ' ');
        return (amount: amount, remaining: rem);
      }
    }

    return null;
  }

  static String _capitalizeFirst(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }
}
