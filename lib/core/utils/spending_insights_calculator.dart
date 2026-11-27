import 'dart:convert';

import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum SafeToSpendMode { auto, budgets, pockets, totalBalance }

class GroupedPocketSummary {
  const GroupedPocketSummary({
    required this.normalizedKey,
    required this.displayName,
    required this.icon,
    required this.color,
    required this.totalBalance,
    required this.pocketIds,
    required this.walletCount,
  });

  final String normalizedKey;
  final String displayName;
  final String icon;
  final int color;
  final int totalBalance;
  final Set<int> pocketIds;
  final int walletCount;
}

class SafeToSpendConfig {
  const SafeToSpendConfig({
    this.mode = SafeToSpendMode.auto,
    this.selectedPocketIds = const {},
    this.selectedPocketNames = const {},
  });

  final SafeToSpendMode mode;
  final Set<int> selectedPocketIds;

  /// Kunci nama pos yang sudah dinormalisasi (mis. 'uangharian', 'tabungan')
  /// agar pos bernama sama di beberapa saku otomatis digabung menjadi 1 pilihan.
  final Set<String> selectedPocketNames;
}

class SafeToSpendResult {
  const SafeToSpendResult({
    required this.dailyAllowance,
    required this.spentToday,
    required this.remainingToday,
    required this.remainingPool,
    required this.daysRemaining,
    required this.sourceLabel,
  });

  final int dailyAllowance;
  final int spentToday;
  final int remainingToday;
  final int remainingPool;
  final int daysRemaining;
  final String sourceLabel;

  double get todayRatio => dailyAllowance <= 0
      ? (spentToday > 0 ? 1.0 : 0.0)
      : spentToday / dailyAllowance;
  bool get isOverDailyLimit => remainingToday < 0;
}

class CategoryDeltaHighlight {
  const CategoryDeltaHighlight({
    required this.categoryName,
    required this.currentTotal,
    required this.previousTotal,
    required this.deltaAmount,
    required this.deltaPercent,
  });

  final String categoryName;
  final int currentTotal;
  final int previousTotal;
  final int deltaAmount;
  final double? deltaPercent;
}

class PeriodInsights {
  const PeriodInsights({
    required this.noSpendDays,
    required this.elapsedDays,
    required this.totalDays,
    required this.projectedExpense,
    this.busiestWeekdayName,
    this.busiestWeekdayAverage = 0,
    this.topItemName,
    this.topItemCount = 0,
    this.topItemTotal = 0,
    this.topRisingCategory,
    this.topFallingCategory,
  });

  final int noSpendDays;
  final int elapsedDays;
  final int totalDays;
  final int projectedExpense;
  final String? busiestWeekdayName;
  final int busiestWeekdayAverage;
  final String? topItemName;
  final int topItemCount;
  final int topItemTotal;
  final CategoryDeltaHighlight? topRisingCategory;
  final CategoryDeltaHighlight? topFallingCategory;
}

class SpendingInsightsCalculator {
  SpendingInsightsCalculator._();

  static const _kModeKey = 'sakuin_sts_mode';
  static const _kPocketsKey = 'sakuin_sts_pockets';
  static const _kPocketNamesKey = 'sakuin_sts_pocket_names';

  /// Normalisasi nama pos budget agar nama sama (termasuk beda huruf besar/spasi,
  /// mis. "Life Style" & "Lifestyle" atau "Uang Harian" di beberapa saku) tergabung rapi.
  static String normalizePocketGroupKey(String rawName) {
    return rawName.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '');
  }

  /// Gabungkan pos budget dengan nama sama di berbagai saku menjadi satu ringkasan gabungan.
  static List<GroupedPocketSummary> groupPocketsByName(
    List<PocketWithBalance> pockets,
  ) {
    final map = <String, _MutablePocketGroup>{};
    for (final p in pockets) {
      final key = normalizePocketGroupKey(p.pocket.name);
      if (key.isEmpty) continue;
      final existing = map[key];
      if (existing == null) {
        map[key] = _MutablePocketGroup(
          normalizedKey: key,
          displayName: p.pocket.name.trim(),
          icon: p.pocket.icon,
          color: p.pocket.color,
          totalBalance: p.balance,
          pocketIds: {p.pocket.id},
          walletIds: {p.pocket.walletId},
        );
      } else {
        existing.totalBalance += p.balance;
        existing.pocketIds.add(p.pocket.id);
        existing.walletIds.add(p.pocket.walletId);
      }
    }
    return map.values
        .map(
          (g) => GroupedPocketSummary(
            normalizedKey: g.normalizedKey,
            displayName: g.displayName,
            icon: g.icon,
            color: g.color,
            totalBalance: g.totalBalance,
            pocketIds: Set<int>.unmodifiable(g.pocketIds),
            walletCount: g.walletIds.length,
          ),
        )
        .toList();
  }

  static Future<SafeToSpendConfig> loadSafeToSpendConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modeStr = prefs.getString(_kModeKey) ?? 'auto';
      final mode = SafeToSpendMode.values.firstWhere(
        (m) => m.name == modeStr,
        orElse: () => SafeToSpendMode.auto,
      );
      final rawIds = prefs.getString(_kPocketsKey);
      final ids = <int>{};
      if (rawIds != null && rawIds.isNotEmpty) {
        final decoded = jsonDecode(rawIds);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is int) ids.add(item);
          }
        }
      }
      final rawNames = prefs.getString(_kPocketNamesKey);
      final names = <String>{};
      if (rawNames != null && rawNames.isNotEmpty) {
        final decoded = jsonDecode(rawNames);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is String && item.isNotEmpty) names.add(item);
          }
        }
      }
      return SafeToSpendConfig(
        mode: mode,
        selectedPocketIds: ids,
        selectedPocketNames: names,
      );
    } catch (_) {
      return const SafeToSpendConfig();
    }
  }

  static Future<void> saveSafeToSpendConfig(SafeToSpendConfig config) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kModeKey, config.mode.name);
      await prefs.setString(
        _kPocketsKey,
        jsonEncode(config.selectedPocketIds.toList()),
      );
      await prefs.setString(
        _kPocketNamesKey,
        jsonEncode(config.selectedPocketNames.toList()),
      );
    } catch (_) {}
  }

  /// Hitung batas aman belanja harian berdasarkan sisa dana periode berjalan
  /// dan jumlah hari tersisa (termasuk hari ini).
  static SafeToSpendResult calculateSafeToSpend({
    required DateTime now,
    required DatePeriod period,
    required int remainingPool,
    required int spentToday,
    required String sourceLabel,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final periodEnd = DateTime(
      period.end.year,
      period.end.month,
      period.end.day,
    );
    final rawDays = periodEnd.difference(today).inDays + 1;
    final daysRemaining = rawDays < 1 ? 1 : rawDays;

    // Jatah hari ini dihitung dari saldo awal hari ini (remainingPool + spentToday)
    // dibagi hari tersisa agar angka batas harian tidak terus bergeser saat belanja hari ini.
    final startOfDayPool = remainingPool + spentToday;
    final dailyAllowance = startOfDayPool <= 0
        ? 0
        : startOfDayPool ~/ daysRemaining;
    final remainingToday = dailyAllowance - spentToday;

    return SafeToSpendResult(
      dailyAllowance: dailyAllowance,
      spentToday: spentToday,
      remainingToday: remainingToday,
      remainingPool: remainingPool,
      daysRemaining: daysRemaining,
      sourceLabel: sourceLabel,
    );
  }

  /// Hitung total pengeluaran hari ini yang benar-benar berasal dari sumber dana
  /// Safe-to-Spend yang dipilih (mis. hanya transaksi dari Pos Uang Harian jika sumbernya
  /// Pos Uang Harian — transaksi dari pos lain seperti Date / Tabungan tidak mengurangi jatah).
  static int computeSpentToday({
    required List<Transaction> todayTransactions,
    required SafeToSpendMode effectiveMode,
    Set<int>? chosenPocketIds,
    Set<int>? budgetedCategoryIds,
    bool hasGlobalBudget = false,
    Set<int>? includedWalletIds,
  }) {
    var total = 0;
    for (final tx in todayTransactions) {
      final isExpense = tx.type == 'expense';
      final isTransferWithFee = tx.type == 'transfer' && tx.fee > 0;
      if (!isExpense && !isTransferWithFee) continue;

      switch (effectiveMode) {
        case SafeToSpendMode.pockets:
          if (chosenPocketIds == null || chosenPocketIds.isEmpty) continue;
          if (tx.pocketId == null || !chosenPocketIds.contains(tx.pocketId)) {
            continue;
          }
          total += isExpense ? tx.amount : tx.fee;
        case SafeToSpendMode.budgets:
          if (hasGlobalBudget) {
            total += isExpense ? tx.amount : tx.fee;
          } else if (isExpense &&
              budgetedCategoryIds != null &&
              tx.categoryId != null &&
              budgetedCategoryIds.contains(tx.categoryId)) {
            total += tx.amount;
          }
        case SafeToSpendMode.totalBalance:
        case SafeToSpendMode.auto:
          if (includedWalletIds != null &&
              !includedWalletIds.contains(tx.walletId)) {
            continue;
          }
          total += isExpense ? tx.amount : tx.fee;
      }
    }
    return total;
  }

  /// Hitung insight periode: jumlah No-Spend Day, hari paling boros, item tersering,
  /// proyeksi akhir periode, serta kategori paling naik & paling turun dibanding periode lalu.
  static PeriodInsights computePeriodInsights({
    required DateTime now,
    required DatePeriod period,
    required List<DailyTrendPoint> trend,
    required List<TransactionDetail> currentTransactions,
    required List<CategoryAggregate> currentExpenseCategories,
    required List<CategoryAggregate> previousExpenseCategories,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final start = DateTime(
      period.start.year,
      period.start.month,
      period.start.day,
    );
    final end = DateTime(period.end.year, period.end.month, period.end.day);
    final effectiveEnd = today.isBefore(end) ? today : end;

    final elapsedDays = effectiveEnd.isBefore(start)
        ? 0
        : effectiveEnd.difference(start).inDays + 1;
    final totalDays = period.totalDays <= 0 ? 1 : period.totalDays;

    final expenseByDayKey = <int, int>{};
    var totalExpense = 0;
    for (final pt in trend) {
      expenseByDayKey[pt.dayKey] = pt.expense;
      totalExpense += pt.expense;
    }

    var noSpendDays = 0;
    final weekdaySums = <int, int>{};
    final weekdayCounts = <int, int>{};
    for (var i = 0; i < elapsedDays; i++) {
      final d = start.add(Duration(days: i));
      final dk = AppDateUtils.toDayKey(d);
      final exp = expenseByDayKey[dk] ?? 0;
      if (exp == 0) {
        noSpendDays++;
      } else {
        weekdaySums[d.weekday] = (weekdaySums[d.weekday] ?? 0) + exp;
        weekdayCounts[d.weekday] = (weekdayCounts[d.weekday] ?? 0) + 1;
      }
    }

    const weekdayNames = {
      DateTime.monday: 'Senin',
      DateTime.tuesday: 'Selasa',
      DateTime.wednesday: 'Rabu',
      DateTime.thursday: 'Kamis',
      DateTime.friday: 'Jumat',
      DateTime.saturday: 'Sabtu',
      DateTime.sunday: 'Minggu',
    };

    String? busiestWeekday;
    var busiestAvg = 0;
    for (final entry in weekdaySums.entries) {
      final count = weekdayCounts[entry.key] ?? 1;
      final avg = entry.value ~/ count;
      if (avg > busiestAvg) {
        busiestAvg = avg;
        busiestWeekday = weekdayNames[entry.key];
      }
    }

    // Item / merchant paling sering dibeli
    final itemCounts = <String, int>{};
    final itemTotals = <String, int>{};
    final itemDisplay = <String, String>{};
    for (final detail in currentTransactions) {
      if (detail.transaction.type != 'expense') continue;
      final rawName = (detail.transaction.itemName ?? '').trim();
      if (rawName.isEmpty) continue;
      final key = rawName.toLowerCase();
      itemDisplay[key] = rawName;
      itemCounts[key] = (itemCounts[key] ?? 0) + 1;
      itemTotals[key] = (itemTotals[key] ?? 0) + detail.transaction.amount;
    }

    String? topItem;
    var topCount = 0;
    var topTotal = 0;
    for (final entry in itemCounts.entries) {
      final count = entry.value;
      final tot = itemTotals[entry.key] ?? 0;
      if (count > topCount || (count == topCount && tot > topTotal)) {
        topCount = count;
        topTotal = tot;
        topItem = itemDisplay[entry.key];
      }
    }

    // Kategori paling naik & paling turun dibanding periode lalu
    final prevMap = {
      for (final c in previousExpenseCategories) c.categoryName: c.total,
    };
    final curMap = {
      for (final c in currentExpenseCategories) c.categoryName: c.total,
    };
    final allNames = {...prevMap.keys, ...curMap.keys};

    CategoryDeltaHighlight? topRising;
    CategoryDeltaHighlight? topFalling;
    for (final name in allNames) {
      final cur = curMap[name] ?? 0;
      final prev = prevMap[name] ?? 0;
      final delta = cur - prev;
      if (delta == 0) continue;
      final pct = prev > 0 ? (delta / prev) * 100 : null;
      final item = CategoryDeltaHighlight(
        categoryName: name,
        currentTotal: cur,
        previousTotal: prev,
        deltaAmount: delta,
        deltaPercent: pct,
      );
      if (delta > 0 && (topRising == null || delta > topRising.deltaAmount)) {
        topRising = item;
      }
      if (delta < 0 && (topFalling == null || delta < topFalling.deltaAmount)) {
        topFalling = item;
      }
    }

    final projected = elapsedDays > 0
        ? ((totalExpense / elapsedDays) * totalDays).round()
        : totalExpense;

    return PeriodInsights(
      noSpendDays: noSpendDays,
      elapsedDays: elapsedDays,
      totalDays: totalDays,
      projectedExpense: projected,
      busiestWeekdayName: busiestWeekday,
      busiestWeekdayAverage: busiestAvg,
      topItemName: topItem,
      topItemCount: topCount,
      topItemTotal: topTotal,
      topRisingCategory: topRising,
      topFallingCategory: topFalling,
    );
  }

  /// Tentukan level intensitas warna heatmap (0 = No-Spend, 1 = Ringan, 2 = Sedang, 3 = Tinggi).
  static int heatmapLevel(int dayExpense, int averageActiveDayExpense) {
    if (dayExpense <= 0) return 0;
    if (averageActiveDayExpense <= 0) return 1;
    final ratio = dayExpense / averageActiveDayExpense;
    if (ratio < 0.75) return 1;
    if (ratio <= 1.35) return 2;
    return 3;
  }
}

class _MutablePocketGroup {
  _MutablePocketGroup({
    required this.normalizedKey,
    required this.displayName,
    required this.icon,
    required this.color,
    required this.totalBalance,
    required this.pocketIds,
    required this.walletIds,
  });

  final String normalizedKey;
  final String displayName;
  final String icon;
  final int color;
  int totalBalance;
  final Set<int> pocketIds;
  final Set<int> walletIds;
}
