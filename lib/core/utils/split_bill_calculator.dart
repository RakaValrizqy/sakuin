import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';

class SplitBillParticipant {
  const SplitBillParticipant({
    required this.id,
    required this.name,
    this.isSelf = false,
  });

  final String id;
  final String name;
  final bool isSelf;
}

class SplitBillItem {
  const SplitBillItem({
    required this.id,
    required this.name,
    required this.amount,
    this.assignedPersonIds = const {},
  });

  final String id;
  final String name;
  final int amount;
  final Set<String> assignedPersonIds;

  SplitBillItem copyWith({
    String? name,
    int? amount,
    Set<String>? assignedPersonIds,
  }) {
    return SplitBillItem(
      id: id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      assignedPersonIds: assignedPersonIds ?? this.assignedPersonIds,
    );
  }
}

class SplitItemShare {
  const SplitItemShare({
    required this.itemName,
    required this.shareAmount,
    required this.sharedByCount,
  });

  final String itemName;
  final int shareAmount;
  final int sharedByCount;
}

class SplitBillPersonResult {
  const SplitBillPersonResult({
    required this.participant,
    required this.itemShares,
    required this.subtotal,
    required this.taxShare,
    required this.serviceShare,
    required this.discountShare,
    required this.total,
  });

  final SplitBillParticipant participant;
  final List<SplitItemShare> itemShares;
  final int subtotal;
  final int taxShare;
  final int serviceShare;
  final int discountShare;
  final int total;
}

class SplitBillResult {
  const SplitBillResult({
    required this.personResults,
    required this.unassignedItems,
    required this.itemsSubtotal,
    required this.tax,
    required this.serviceCharge,
    required this.discount,
    required this.grandTotal,
  });

  final List<SplitBillPersonResult> personResults;
  final List<SplitBillItem> unassignedItems;
  final int itemsSubtotal;
  final int tax;
  final int serviceCharge;
  final int discount;
  final int grandTotal;

  int get allocatedTotal => personResults.fold(0, (s, p) => s + p.total);
  bool get allItemsAssigned => unassignedItems.isEmpty;
}

/// Mesin hitung Split Bill deterministik dengan pembulatan Rupiah akurat (largest-remainder)
/// sehingga jumlah tagihan seluruh peserta selalu 100% cocok dengan total struk.
class SplitBillCalculator {
  static SplitBillResult calculate({
    required List<SplitBillParticipant> participants,
    required List<SplitBillItem> items,
    int tax = 0,
    int serviceCharge = 0,
    int discount = 0,
    bool proportionalExtras = true,
  }) {
    final validIds = participants.map((p) => p.id).toSet();
    final sharesByPerson = <String, List<SplitItemShare>>{
      for (final p in participants) p.id: [],
    };
    final subtotalByPerson = <String, int>{
      for (final p in participants) p.id: 0,
    };
    final unassigned = <SplitBillItem>[];

    var itemsSubtotal = 0;
    for (final item in items) {
      if (item.amount <= 0) continue;
      itemsSubtotal += item.amount;
      final assigned = participants
          .map((p) => p.id)
          .where(
            (id) =>
                item.assignedPersonIds.contains(id) && validIds.contains(id),
          )
          .toList();
      if (assigned.isEmpty) {
        unassigned.add(item);
        continue;
      }

      // Bagi rata harga item ke seluruh orang yang mencentang item tersebut (exact integer split)
      final base = item.amount ~/ assigned.length;
      final rem = item.amount % assigned.length;
      for (var i = 0; i < assigned.length; i++) {
        final pid = assigned[i];
        final share = base + (i < rem ? 1 : 0);
        sharesByPerson[pid]!.add(
          SplitItemShare(
            itemName: item.name,
            shareAmount: share,
            sharedByCount: assigned.length,
          ),
        );
        subtotalByPerson[pid] = subtotalByPerson[pid]! + share;
      }
    }

    // Peserta aktif (yang punya minimal 1 item; jika semua 0, gunakan semua peserta)
    final activeIds = participants
        .where((p) => (subtotalByPerson[p.id] ?? 0) > 0)
        .map((p) => p.id)
        .toList();
    final targetIds = activeIds.isNotEmpty
        ? activeIds
        : participants.map((p) => p.id).toList();

    Map<String, int> weights;
    if (proportionalExtras && activeIds.isNotEmpty) {
      weights = {for (final id in targetIds) id: subtotalByPerson[id]!};
    } else {
      weights = {for (final id in targetIds) id: 1};
    }

    final taxMap = _distributeWeighted(tax, weights);
    final serviceMap = _distributeWeighted(serviceCharge, weights);
    final discountMap = _distributeWeighted(discount, weights);

    final results = <SplitBillPersonResult>[];
    for (final p in participants) {
      final sub = subtotalByPerson[p.id] ?? 0;
      final t = taxMap[p.id] ?? 0;
      final sc = serviceMap[p.id] ?? 0;
      final disc = discountMap[p.id] ?? 0;
      final total = (sub + t + sc - disc).clamp(0, 1 << 60);
      results.add(
        SplitBillPersonResult(
          participant: p,
          itemShares: sharesByPerson[p.id] ?? const [],
          subtotal: sub,
          taxShare: t,
          serviceShare: sc,
          discountShare: disc,
          total: total,
        ),
      );
    }

    final grandTotal = (itemsSubtotal + tax + serviceCharge - discount).clamp(
      0,
      1 << 60,
    );

    return SplitBillResult(
      personResults: results,
      unassignedItems: unassigned,
      itemsSubtotal: itemsSubtotal,
      tax: tax,
      serviceCharge: serviceCharge,
      discount: discount,
      grandTotal: grandTotal,
    );
  }

  /// Distribusi jumlah bulat berdasarkan bobot memakai metode Largest Remainder
  /// agar total seluruh porsi == [totalAmount] tanpa selisih 1 rupiah pun.
  static Map<String, int> _distributeWeighted(
    int totalAmount,
    Map<String, int> weights,
  ) {
    if (totalAmount <= 0 || weights.isEmpty) return const {};
    final totalWeight = weights.values.fold<int>(0, (s, w) => s + w);
    if (totalWeight <= 0) return const {};

    final keys = weights.keys.toList();
    final floors = <String, int>{};
    final remainders = <String, double>{};
    var floorSum = 0;

    for (final k in keys) {
      final exact = totalAmount * weights[k]! / totalWeight;
      final fl = exact.floor();
      floors[k] = fl;
      remainders[k] = exact - fl;
      floorSum += fl;
    }

    var leftover = totalAmount - floorSum;
    final sortedByRem = List<String>.from(keys)
      ..sort((a, b) => remainders[b]!.compareTo(remainders[a]!));

    for (var i = 0; i < leftover && i < sortedByRem.length; i++) {
      final k = sortedByRem[i];
      floors[k] = floors[k]! + 1;
    }

    return floors;
  }

  /// Format ringkasan Split Bill siap kirim ke WhatsApp / disalin ke clipboard.
  static String formatShareText({
    required String merchantName,
    required DateTime occurredAt,
    required SplitBillParticipant payer,
    required SplitBillResult result,
  }) {
    final buf = StringBuffer();
    buf.writeln('🧾 Split Bill — $merchantName');
    buf.writeln('📅 ${AppDateUtils.formatShortDate(occurredAt)}');
    buf.writeln('💳 Dibayar oleh: ${payer.name}');
    buf.writeln('Total Struk: ${CurrencyFormatter.format(result.grandTotal)}');
    buf.writeln('');

    for (final pr in result.personResults) {
      if (pr.total <= 0 && pr.itemShares.isEmpty) continue;
      final tag = pr.participant.id == payer.id ? ' (Pembayar)' : '';
      buf.writeln(
        '• ${pr.participant.name}$tag: ${CurrencyFormatter.format(pr.total)}',
      );
      for (final share in pr.itemShares) {
        final splitTag = share.sharedByCount > 1
            ? ' (patungan ${share.sharedByCount} org)'
            : '';
        buf.writeln(
          '   - ${share.itemName}$splitTag: ${CurrencyFormatter.format(share.shareAmount)}',
        );
      }
      if (pr.taxShare > 0) {
        buf.writeln('   - Pajak: ${CurrencyFormatter.format(pr.taxShare)}');
      }
      if (pr.serviceShare > 0) {
        buf.writeln(
          '   - Service: ${CurrencyFormatter.format(pr.serviceShare)}',
        );
      }
      if (pr.discountShare > 0) {
        buf.writeln(
          '   - Diskon: -${CurrencyFormatter.format(pr.discountShare)}',
        );
      }
    }

    return buf.toString().trim();
  }
}
