import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class IncomeAllocationResult {
  const IncomeAllocationResult({
    required this.incomeAmount,
    required this.amountByPocketId,
    required this.percentByPocketId,
    required this.unallocatedAmount,
    required this.unallocatedPercent,
  });

  final int incomeAmount;
  final Map<int, int> amountByPocketId;
  final Map<int, int> percentByPocketId;
  final int unallocatedAmount;
  final int unallocatedPercent;

  int get allocatedTotal =>
      amountByPocketId.values.fold<int>(0, (sum, v) => sum + v);

  int get allocatedPercent =>
      percentByPocketId.values.fold<int>(0, (sum, v) => sum + v);
}

/// Mesin hitung pembagian pemasukan ke berbagai pos budget berdasarkan persentase
/// beserta kategori otomatis "Belum Dialokasikan" (unallocated) untuk sisa persentase.
/// Memakai metode Largest Remainder agar total pembagian == [incomeAmount] pas 100%.
class IncomeAllocationCalculator {
  IncomeAllocationCalculator._();

  static String _prefsKey(int walletId) =>
      'sakuin_income_split_pct_wallet_$walletId';

  static IncomeAllocationResult calculate({
    required int incomeAmount,
    required List<int> pocketIds,
    required Map<int, int> rawPercentByPocketId,
  }) {
    final safeAmount = incomeAmount < 0 ? 0 : incomeAmount;
    final cleanPercents = <int, int>{};
    var usedPct = 0;

    for (final pid in pocketIds) {
      final requested = (rawPercentByPocketId[pid] ?? 0).clamp(0, 100);
      final allowed = (100 - usedPct).clamp(0, 100);
      final clamped = requested > allowed ? allowed : requested;
      cleanPercents[pid] = clamped;
      usedPct += clamped;
    }

    final unallocatedPct = (100 - usedPct).clamp(0, 100);

    // Kunci khusus -1 mewakili porsi "Belum Dialokasikan" agar pembulatan Largest Remainder
    // membagi sisa rupiah secara adil di seluruh pos + unallocated hingga total == safeAmount.
    const unallocatedKey = -1;
    final weights = <int, int>{
      for (final pid in pocketIds)
        if ((cleanPercents[pid] ?? 0) > 0) pid: cleanPercents[pid]!,
      if (unallocatedPct > 0) unallocatedKey: unallocatedPct,
    };

    final distributed = _distributeByPercent(safeAmount, weights);
    final amountByPocket = <int, int>{
      for (final pid in pocketIds) pid: distributed[pid] ?? 0,
    };
    final unallocatedAmt = distributed[unallocatedKey] ?? 0;

    return IncomeAllocationResult(
      incomeAmount: safeAmount,
      amountByPocketId: amountByPocket,
      percentByPocketId: cleanPercents,
      unallocatedAmount: unallocatedAmt,
      unallocatedPercent: unallocatedPct,
    );
  }

  static Map<int, int> _distributeByPercent(
    int totalAmount,
    Map<int, int> percentWeights,
  ) {
    if (totalAmount <= 0 || percentWeights.isEmpty) return const {};
    final totalWeight = percentWeights.values.fold<int>(0, (s, w) => s + w);
    if (totalWeight <= 0) return const {};

    final keys = percentWeights.keys.toList();
    final floors = <int, int>{};
    final remainders = <int, double>{};
    var floorSum = 0;

    for (final k in keys) {
      final exact = totalAmount * percentWeights[k]! / totalWeight;
      final fl = exact.floor();
      floors[k] = fl;
      remainders[k] = exact - fl;
      floorSum += fl;
    }

    final leftover = totalAmount - floorSum;
    final sorted = List<int>.from(keys)
      ..sort((a, b) => remainders[b]!.compareTo(remainders[a]!));

    for (var i = 0; i < leftover && i < sorted.length; i++) {
      final k = sorted[i];
      floors[k] = floors[k]! + 1;
    }

    return floors;
  }

  /// Muat template persentase terakhir yang disimpan pengguna untuk saku tertentu.
  static Future<Map<int, int>> loadSavedPercentages(int walletId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey(walletId));
      if (raw == null || raw.isEmpty) return const {};
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      final result = <int, int>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse(entry.key.toString());
        final pct = entry.value is num ? (entry.value as num).round() : null;
        if (id != null && pct != null && pct >= 0 && pct <= 100) {
          result[id] = pct;
        }
      }
      return result;
    } catch (_) {
      return const {};
    }
  }

  /// Simpan template persentase untuk dipakai otomatis pada pemasukan berikutnya di saku ini.
  static Future<void> savePercentages(
    int walletId,
    Map<int, int> percentByPocketId,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in percentByPocketId.entries)
          entry.key.toString(): entry.value.clamp(0, 100),
      });
      await prefs.setString(_prefsKey(walletId), encoded);
    } catch (_) {}
  }
}
