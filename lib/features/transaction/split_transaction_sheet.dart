import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/features/category/category_providers.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

/// Buka sheet Pecah Transaksi dari transaksi yang sudah ada (atau grup pecahan yang sudah ada).
Future<bool?> showSplitExistingTransactionSheet(
  BuildContext context, {
  required TransactionDetail detail,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: SplitTransactionSheet(existingDetail: detail),
    ),
  );
}

/// Buka sheet Pecah Transaksi langsung dari antrean QRIS (sebelum disimpan ke transaksi).
Future<bool?> showSplitNewTransactionSheet(
  BuildContext context, {
  required int totalAmount,
  required int walletId,
  required DateTime occurredAt,
  required String merchantName,
  String? externalRef,
  String type = 'expense',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.92,
      child: SplitTransactionSheet(
        newTotalAmount: totalAmount,
        newWalletId: walletId,
        newOccurredAt: occurredAt,
        newMerchantName: merchantName,
        newExternalRef: externalRef,
        newType: type,
      ),
    ),
  );
}

class _SplitRowData {
  _SplitRowData({
    String name = '',
    String amountText = '',
    this.categoryId,
    this.pocketId,
    String note = '',
  }) : nameCtrl = TextEditingController(text: name),
       amountCtrl = TextEditingController(text: amountText),
       noteCtrl = TextEditingController(text: note);

  final TextEditingController nameCtrl;
  final TextEditingController amountCtrl;
  final TextEditingController noteCtrl;
  int? categoryId;
  int? pocketId;

  int get parsedAmount => AmountParser.parse(amountCtrl.text) ?? 0;

  void dispose() {
    nameCtrl.dispose();
    amountCtrl.dispose();
    noteCtrl.dispose();
  }
}

class SplitTransactionSheet extends ConsumerStatefulWidget {
  const SplitTransactionSheet({
    super.key,
    this.existingDetail,
    this.newTotalAmount,
    this.newWalletId,
    this.newOccurredAt,
    this.newMerchantName,
    this.newExternalRef,
    this.newType = 'expense',
  });

  final TransactionDetail? existingDetail;
  final int? newTotalAmount;
  final int? newWalletId;
  final DateTime? newOccurredAt;
  final String? newMerchantName;
  final String? newExternalRef;
  final String newType;

  @override
  ConsumerState<SplitTransactionSheet> createState() =>
      _SplitTransactionSheetState();
}

class _SplitTransactionSheetState extends ConsumerState<SplitTransactionSheet> {
  final List<_SplitRowData> _rows = [];
  late String _type;
  late int _targetTotal;
  int? _walletId;
  late DateTime _occurredAt;
  String? _merchantNote;
  String? _existingSplitGroupId;
  int? _replaceSingleTxId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _initData();
  }

  Future<void> _initData() async {
    final detail = widget.existingDetail;
    if (detail != null) {
      final tx = detail.transaction;
      _type = tx.type == 'income' ? 'income' : 'expense';
      _walletId = tx.walletId;
      _occurredAt = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt)
          .toLocal();
      _merchantNote = tx.note.isNotEmpty
          ? tx.note
          : (tx.itemName ?? detail.category?.name ?? '');

      if (tx.splitGroupId != null) {
        _existingSplitGroupId = tx.splitGroupId;
        final siblings = await ref
            .read(appDatabaseProvider)
            .getTransactionsBySplitGroup(tx.splitGroupId!);
        var sum = 0;
        for (final s in siblings) {
          sum += s.amount;
          _rows.add(
            _SplitRowData(
              name: s.itemName ?? '',
              amountText: CurrencyFormatter.format(s.amount, withSymbol: false),
              categoryId: s.categoryId,
              pocketId: s.pocketId,
              note: s.note,
            ),
          );
        }
        _targetTotal = sum;
      } else {
        _replaceSingleTxId = tx.id;
        _targetTotal = tx.amount;
        _rows.add(
          _SplitRowData(
            name: '',
            amountText: '',
            categoryId: tx.categoryId,
            pocketId: tx.pocketId,
            note: tx.note.isNotEmpty
                ? tx.note
                : (tx.itemName != null ? 'Dari: ${tx.itemName}' : ''),
          ),
        );
        _rows.add(
          _SplitRowData(
            name: '',
            amountText: '',
            categoryId: tx.categoryId,
            pocketId: tx.pocketId,
            note: tx.note.isNotEmpty
                ? tx.note
                : (tx.itemName != null ? 'Dari: ${tx.itemName}' : ''),
          ),
        );
      }
    } else {
      _type = widget.newType;
      _targetTotal = widget.newTotalAmount ?? 0;
      _walletId = widget.newWalletId;
      _occurredAt = widget.newOccurredAt ?? DateTime.now();
      _merchantNote = widget.newMerchantName;
      final defaultCatId = await ref
          .read(appDatabaseProvider)
          .findCategoryIdByName('Makanan & Minuman', _type);
      final noteStr = (widget.newMerchantName ?? '').isNotEmpty
          ? 'QRIS • ${widget.newMerchantName}'
          : '';
      _rows.add(_SplitRowData(categoryId: defaultCatId, note: noteStr));
      _rows.add(_SplitRowData(categoryId: defaultCatId, note: noteStr));
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  int get _allocatedSum {
    var s = 0;
    for (final r in _rows) {
      s += r.parsedAmount;
    }
    return s;
  }

  int get _remaining => _targetTotal - _allocatedSum;

  void _addRow() {
    final last = _rows.isNotEmpty ? _rows.last : null;
    setState(() {
      _rows.add(
        _SplitRowData(
          categoryId: last?.categoryId,
          pocketId: last?.pocketId,
          note: last?.noteCtrl.text ?? '',
        ),
      );
    });
  }

  void _fillRemaining(_SplitRowData row) {
    final othersSum = _allocatedSum - row.parsedAmount;
    final rem = _targetTotal - othersSum;
    if (rem <= 0) return;
    AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
    setState(() {
      row.amountCtrl.text = CurrencyFormatter.format(rem, withSymbol: false);
    });
  }

  void _splitEqually() {
    if (_rows.isEmpty || _targetTotal <= 0) return;
    AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
    final base = _targetTotal ~/ _rows.length;
    final remainder = _targetTotal - (base * _rows.length);
    setState(() {
      for (var i = 0; i < _rows.length; i++) {
        final val = base + (i == 0 ? remainder : 0);
        _rows[i].amountCtrl.text = CurrencyFormatter.format(
          val,
          withSymbol: false,
        );
      }
    });
  }

  Future<void> _save() async {
    if (_saving || _walletId == null) return;
    final validComponents = <SplitComponentInput>[];
    for (var i = 0; i < _rows.length; i++) {
      final r = _rows[i];
      final amt = r.parsedAmount;
      if (amt <= 0) continue;
      final name = r.nameCtrl.text.trim().isEmpty
          ? 'Item ${i + 1}'
          : r.nameCtrl.text.trim();
      validComponents.add(
        SplitComponentInput(
          itemName: name,
          amount: amt,
          categoryId: r.categoryId,
          pocketId: r.pocketId,
          note: r.noteCtrl.text.trim(),
        ),
      );
    }

    if (validComponents.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi minimal 2 komponen dengan nominal lebih dari 0'),
        ),
      );
      return;
    }

    if (_remaining != 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Total Pecahan Berbeda'),
          content: Text(
            'Total komponen (${CurrencyFormatter.format(_allocatedSum)}) berbeda dengan nominal awal (${CurrencyFormatter.format(_targetTotal)}). Tetap simpan dengan total baru?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Perbaiki'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Tetap Simpan'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _saving = true);
    await ref
        .read(transactionActionsProvider)
        .saveSplitTransactions(
          type: _type,
          walletId: _walletId!,
          occurredAt: _occurredAt,
          components: validComponents,
          replaceSingleTransactionId: _replaceSingleTxId,
          existingSplitGroupId: _existingSplitGroupId,
          externalRef: widget.newExternalRef,
        );
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final allPockets =
        ref.watch(allActivePocketsProvider).valueOrNull ?? const [];
    final categories =
        (_type == 'income'
            ? ref.watch(incomeCategoriesProvider).valueOrNull
            : ref.watch(expenseCategoriesProvider).valueOrNull) ??
        const [];

    if (_walletId == null && wallets.isNotEmpty) {
      _walletId = wallets.first.wallet.id;
    }
    final walletPockets = allPockets
        .where((p) => p.pocket.walletId == _walletId)
        .toList();

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final rem = _remaining;
    final statusColor = rem == 0
        ? AppColors.income(context)
        : (rem > 0 ? AppColors.warning(context) : AppColors.expense(context));

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Tutup',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _existingSplitGroupId != null
                                  ? 'Edit Pecahan Transaksi'
                                  : 'Pecah Transaksi',
                              style: tt.titleLarge,
                            ),
                            if (_merchantNote != null &&
                                _merchantNote!.isNotEmpty)
                              Text(
                                '$_merchantNote • ${AppDateUtils.formatShortDate(_occurredAt)}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _splitEqually,
                        child: const Text('Bagi rata'),
                      ),
                    ],
                  ),
                ),

                // Ringkasan Total vs Sisa
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Total Target', style: tt.labelSmall),
                            Text(
                              CurrencyFormatter.format(_targetTotal),
                              style: tt.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              rem == 0
                                  ? 'Status'
                                  : (rem > 0
                                        ? 'Sisa belum dibagi'
                                        : 'Melebihi'),
                              style: tt.labelSmall?.copyWith(
                                color: statusColor,
                              ),
                            ),
                            Text(
                              rem == 0
                                  ? 'Pas 100%!'
                                  : CurrencyFormatter.format(rem.abs()),
                              style: tt.titleMedium?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                if (widget.existingDetail == null && wallets.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: DropdownButtonFormField<int>(
                      initialValue: _walletId,
                      decoration: const InputDecoration(
                        labelText: 'Dompet / Saku',
                        isDense: true,
                      ),
                      items: [
                        for (final wb in wallets)
                          DropdownMenuItem(
                            value: wb.wallet.id,
                            child: Text(wb.wallet.name),
                          ),
                      ],
                      onChanged: (v) => setState(() {
                        _walletId = v;
                        for (final r in _rows) {
                          r.pocketId = null;
                        }
                      }),
                    ),
                  ),

                // Daftar Komponen Pecahan
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    itemCount: _rows.length + 1,
                    itemBuilder: (ctx, idx) {
                      if (idx == _rows.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: OutlinedButton.icon(
                            onPressed: _addRow,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Tambah Komponen Item'),
                          ),
                        );
                      }

                      final row = _rows[idx];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Komponen #${idx + 1}',
                                      style: tt.labelLarge?.copyWith(
                                        color: cs.primary,
                                      ),
                                    ),
                                    if (_rows.length > 2)
                                      IconButton(
                                        tooltip: 'Hapus komponen',
                                        visualDensity: VisualDensity.compact,
                                        icon: const Icon(
                                          Icons.close_rounded,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            final removed = _rows.removeAt(idx);
                                            removed.dispose();
                                          });
                                        },
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: row.nameCtrl,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  decoration: InputDecoration(
                                    labelText: 'Nama item / produk',
                                    hintText: idx == 0
                                        ? 'Contoh: Es Teh'
                                        : 'Contoh: Nasi Ayam Geprek',
                                    isDense: true,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextField(
                                        controller: row.amountCtrl,
                                        onChanged: (_) => setState(() {}),
                                        decoration: const InputDecoration(
                                          labelText: 'Nominal',
                                          prefixText: 'Rp ',
                                          hintText: '5k / 15000',
                                          isDense: true,
                                        ),
                                      ),
                                    ),
                                    if (rem > 0) ...[
                                      const SizedBox(width: 8),
                                      FilledButton.tonal(
                                        onPressed: () => _fillRemaining(row),
                                        child: const Text('Isi sisa'),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: DropdownButtonFormField<int?>(
                                        initialValue:
                                            categories.any(
                                              (c) => c.id == row.categoryId,
                                            )
                                            ? row.categoryId
                                            : (categories.isNotEmpty
                                                  ? categories.first.id
                                                  : null),
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText: 'Kategori',
                                          isDense: true,
                                        ),
                                        items: [
                                          for (final c in categories)
                                            DropdownMenuItem<int?>(
                                              value: c.id,
                                              child: Text(
                                                c.name,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                        ],
                                        onChanged: (v) =>
                                            setState(() => row.categoryId = v),
                                      ),
                                    ),
                                    if (walletPockets.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: DropdownButtonFormField<int?>(
                                          initialValue:
                                              walletPockets.any(
                                                (p) =>
                                                    p.pocket.id == row.pocketId,
                                              )
                                              ? row.pocketId
                                              : null,
                                          isExpanded: true,
                                          decoration: const InputDecoration(
                                            labelText: 'Pos Budget',
                                            isDense: true,
                                          ),
                                          items: [
                                            const DropdownMenuItem<int?>(
                                              value: null,
                                              child: Text('Saldo Bebas'),
                                            ),
                                            for (final p in walletPockets)
                                              DropdownMenuItem<int?>(
                                                value: p.pocket.id,
                                                child: Text(
                                                  p.pocket.name,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                          ],
                                          onChanged: (v) =>
                                              setState(() => row.pocketId = v),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Sticky Simpan Button
                SafeArea(
                  top: false,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      border: Border(
                        top: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.call_split_rounded),
                        label: Text(
                          'Simpan Pecahan (${CurrencyFormatter.format(_allocatedSum)})',
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
