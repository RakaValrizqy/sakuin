import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/utils/receipt_parser.dart';
import 'package:sakuin/core/utils/split_bill_calculator.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/features/category/category_providers.dart';
import 'package:sakuin/features/debt/debt_providers.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';
import 'package:share_plus/share_plus.dart';

enum _SplitSaveMode { debtAndTransaction, regularTransaction, checkOnly }

class SplitBillScreen extends ConsumerStatefulWidget {
  const SplitBillScreen({
    super.key,
    required this.merchantName,
    required this.occurredAt,
    required this.initialItems,
    this.tax = 0,
    this.serviceCharge = 0,
    this.discount = 0,
  });

  final String merchantName;
  final DateTime occurredAt;
  final List<ParsedReceiptItem> initialItems;
  final int tax;
  final int serviceCharge;
  final int discount;

  @override
  ConsumerState<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends ConsumerState<SplitBillScreen> {
  static const _selfId = 'self';

  late List<SplitBillParticipant> _participants;
  late List<SplitBillItem> _items;
  String _payerId = _selfId;
  bool _proportionalExtras = true;
  _SplitSaveMode _saveMode = _SplitSaveMode.debtAndTransaction;
  bool _recordSelfExpense = true;
  bool _splitRegularPerItem = false;
  int? _walletId;
  int? _pocketId;
  int? _categoryId;
  bool _saving = false;
  int _nextIdCounter = 1;

  @override
  void initState() {
    super.initState();
    _participants = const [
      SplitBillParticipant(id: _selfId, name: 'Saya', isSelf: true),
    ];
    _items = [
      for (var i = 0; i < widget.initialItems.length; i++)
        SplitBillItem(
          id: 'item_$i',
          name: widget.initialItems[i].name,
          amount: widget.initialItems[i].totalPrice,
          assignedPersonIds: const {_selfId},
        ),
    ];
    _nextIdCounter = widget.initialItems.length + 1;
  }

  SplitBillParticipant get _payer => _participants.firstWhere(
    (p) => p.id == _payerId,
    orElse: () => _participants.first,
  );

  SplitBillResult get _result => SplitBillCalculator.calculate(
    participants: _participants,
    items: _items,
    tax: widget.tax,
    serviceCharge: widget.serviceCharge,
    discount: widget.discount,
    proportionalExtras: _proportionalExtras,
  );

  Future<void> _addParticipantDialog(List<Person> existingPeople) async {
    final ctrl = TextEditingController();
    final existingNames = _participants
        .map((p) => p.name.toLowerCase())
        .toSet();
    final suggestions = existingPeople
        .where((p) => !existingNames.contains(p.name.toLowerCase()))
        .toList();

    final addedName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Orang'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama teman',
                  hintText: 'Contoh: Budi, Ani',
                ),
                onSubmitted: (v) {
                  if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
                },
              ),
              if (suggestions.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Dari daftar kontak Hutang-Piutang:',
                  style: Theme.of(ctx).textTheme.labelMedium,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final person in suggestions.take(10))
                      ActionChip(
                        label: Text(person.name),
                        onPressed: () => Navigator.pop(ctx, person.name),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final v = ctrl.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (addedName == null || addedName.isEmpty) return;
    if (_participants.any(
      (p) => p.name.toLowerCase() == addedName.toLowerCase(),
    )) {
      return;
    }

    setState(() {
      _participants = [
        ..._participants,
        SplitBillParticipant(id: 'p_${_nextIdCounter++}', name: addedName),
      ];
    });
  }

  void _removeParticipant(SplitBillParticipant person) {
    if (person.isSelf) return;
    setState(() {
      _participants = _participants.where((p) => p.id != person.id).toList();
      if (_payerId == person.id) _payerId = _selfId;
      _items = _items
          .map(
            (item) => item.copyWith(
              assignedPersonIds: item.assignedPersonIds
                  .where((id) => id != person.id)
                  .toSet(),
            ),
          )
          .toList();
    });
  }

  void _toggleAssignment(int itemIndex, String personId) {
    final item = _items[itemIndex];
    final next = Set<String>.from(item.assignedPersonIds);
    if (next.contains(personId)) {
      next.remove(personId);
    } else {
      next.add(personId);
    }
    setState(() {
      _items[itemIndex] = item.copyWith(assignedPersonIds: next);
    });
  }

  void _toggleAssignAll(int itemIndex) {
    final item = _items[itemIndex];
    final allIds = _participants.map((p) => p.id).toSet();
    final isAllSelected = allIds.every(item.assignedPersonIds.contains);
    setState(() {
      _items[itemIndex] = item.copyWith(
        assignedPersonIds: isAllSelected ? const {} : allIds,
      );
    });
  }

  Future<void> _addExtraItemDialog() async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final added = await showDialog<SplitBillItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tambah Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nama item'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Harga',
                prefixText: 'Rp ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              final n = nameCtrl.text.trim();
              final a = AmountParser.parse(priceCtrl.text) ?? 0;
              if (n.isEmpty || a <= 0) return;
              Navigator.pop(
                ctx,
                SplitBillItem(
                  id: 'item_${_nextIdCounter++}',
                  name: n,
                  amount: a,
                  assignedPersonIds: const {_selfId},
                ),
              );
            },
            child: const Text('Tambah'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    priceCtrl.dispose();
    if (added != null) {
      setState(() => _items = [..._items, added]);
    }
  }

  Future<void> _copySummary() async {
    final text = SplitBillCalculator.formatShareText(
      merchantName: widget.merchantName,
      occurredAt: widget.occurredAt,
      payer: _payer,
      result: _result,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rincian Split Bill disalin ke clipboard')),
    );
  }

  Future<void> _shareSummary() async {
    final text = SplitBillCalculator.formatShareText(
      merchantName: widget.merchantName,
      occurredAt: widget.occurredAt,
      payer: _payer,
      result: _result,
    );
    await SharePlus.instance.share(
      ShareParams(text: text, subject: 'Split Bill ${widget.merchantName}'),
    );
  }

  Future<void> _executeAction(
    List<WalletWithBalance> wallets,
    List<Category> categories,
  ) async {
    if (_saveMode == _SplitSaveMode.checkOnly) {
      Navigator.of(context).pop(true);
      return;
    }

    final res = _result;
    if (!res.allItemsAssigned) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Masih ada ${res.unassignedItems.length} item yang belum dipilih pembelinya',
          ),
        ),
      );
      return;
    }
    if (res.grandTotal <= 0) return;

    final effectiveWalletId =
        _walletId ?? (wallets.isNotEmpty ? wallets.first.wallet.id : null);
    final effectiveCategoryId =
        _categoryId ?? (categories.isNotEmpty ? categories.first.id : null);

    setState(() => _saving = true);
    try {
      final txActions = ref.read(transactionActionsProvider);
      final debtActions = ref.read(debtActionsProvider);

      if (_saveMode == _SplitSaveMode.regularTransaction) {
        if (effectiveWalletId == null) {
          throw Exception('Buat minimal 1 dompet terlebih dahulu');
        }
        if (_splitRegularPerItem && _items.length > 1) {
          final extras = widget.tax + widget.serviceCharge - widget.discount;
          final comps = <SplitComponentInput>[];
          for (var i = 0; i < _items.length; i++) {
            final item = _items[i];
            var amt = item.amount;
            if (i == _items.length - 1 && extras != 0 && amt + extras > 0) {
              amt += extras;
            }
            comps.add(
              SplitComponentInput(
                itemName: item.name,
                amount: amt,
                categoryId: effectiveCategoryId,
                pocketId: _pocketId,
                note: 'Split Bill ${widget.merchantName}',
              ),
            );
          }
          await txActions.saveSplitTransactions(
            type: 'expense',
            walletId: effectiveWalletId,
            occurredAt: widget.occurredAt,
            components: comps,
          );
        } else {
          await txActions.saveTransaction(
            type: 'expense',
            amount: res.grandTotal,
            walletId: effectiveWalletId,
            pocketId: _pocketId,
            categoryId: effectiveCategoryId,
            itemName: widget.merchantName,
            note: 'Split Bill (${_items.length} item)',
            occurredAt: widget.occurredAt,
          );
        }

        if (!mounted) return;
        AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tersimpan sebagai transaksi biasa (${CurrencyFormatter.format(res.grandTotal)})',
            ),
          ),
        );
        Navigator.of(context).pop(true);
        return;
      }

      // Mode: Simpan Transaksi + Piutang / Hutang
      final selfResult = res.personResults.firstWhere(
        (p) => p.participant.isSelf,
      );

      if (_payer.isSelf) {
        if (effectiveWalletId == null) {
          throw Exception('Buat minimal 1 dompet terlebih dahulu');
        }

        // 1. Porsi Saya -> transaksi pengeluaran biasa (opsional, default aktif)
        if (_recordSelfExpense && selfResult.total > 0) {
          final selfItemsDesc = selfResult.itemShares
              .map((s) => s.itemName)
              .take(4)
              .join(', ');
          await txActions.saveTransaction(
            type: 'expense',
            amount: selfResult.total,
            walletId: effectiveWalletId,
            pocketId: _pocketId,
            categoryId: effectiveCategoryId,
            itemName: widget.merchantName,
            note: selfItemsDesc.isNotEmpty
                ? 'Split Bill (porsi saya): $selfItemsDesc'
                : 'Split Bill ${widget.merchantName} (porsi saya)',
            occurredAt: widget.occurredAt,
          );
        }

        // 2. Porsi tiap teman -> otomatis masuk Piutang (they_owe) dgn walletId dompet pembayar
        //    agar saldo dompet berkurang pas sejumlah talangan dan kembali otomatis saat dilunasi!
        var createdDebts = 0;
        for (final pr in res.personResults) {
          if (pr.participant.isSelf || pr.total <= 0) continue;
          final itemsDesc = pr.itemShares
              .map((s) => s.itemName)
              .take(5)
              .join(', ');
          await debtActions.saveDebt(
            personName: pr.participant.name,
            direction: 'they_owe',
            principal: pr.total,
            note: itemsDesc.isNotEmpty
                ? 'Split Bill ${widget.merchantName}: $itemsDesc'
                : 'Split Bill ${widget.merchantName}',
            createdAt: widget.occurredAt,
            walletId: effectiveWalletId,
          );
          createdDebts++;
        }

        if (!mounted) return;
        AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              createdDebts > 0
                  ? 'Tersimpan! $createdDebts catatan piutang masuk menu Hutang-Piutang'
                  : 'Pengeluaran porsi saya tersimpan',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      } else {
        // Teman yang bayar -> porsi Saya masuk Hutang (i_owe) ke pembayar
        if (selfResult.total <= 0) {
          throw Exception(
            'Porsi Saya Rp 0 — tidak ada hutang yang perlu dicatat',
          );
        }
        final selfItemsDesc = selfResult.itemShares
            .map((s) => s.itemName)
            .take(5)
            .join(', ');
        await debtActions.saveDebt(
          personName: _payer.name,
          direction: 'i_owe',
          principal: selfResult.total,
          note: selfItemsDesc.isNotEmpty
              ? 'Split Bill ${widget.merchantName}: $selfItemsDesc'
              : 'Split Bill ${widget.merchantName}',
          createdAt: widget.occurredAt,
          walletId: null,
        );

        if (!mounted) return;
        AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hutang ${CurrencyFormatter.format(selfResult.total)} ke ${_payer.name} masuk menu Hutang-Piutang',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final allPockets =
        ref.watch(allActivePocketsProvider).valueOrNull ?? const [];
    final categories =
        ref.watch(expenseCategoriesProvider).valueOrNull ?? const [];

    _walletId ??= wallets.isNotEmpty ? wallets.first.wallet.id : null;
    if (_categoryId == null && categories.isNotEmpty) {
      final food = categories
          .where((c) => c.name.toLowerCase().contains('makanan'))
          .firstOrNull;
      _categoryId = food?.id ?? categories.first.id;
    }

    final walletPockets = allPockets
        .where((p) => p.pocket.walletId == _walletId)
        .toList();
    if (_pocketId != null &&
        !walletPockets.any((p) => p.pocket.id == _pocketId)) {
      _pocketId = null;
    }

    final res = _result;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final hasExtras =
        widget.tax > 0 || widget.serviceCharge > 0 || widget.discount > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text('Split Bill • ${widget.merchantName}'),
        actions: [
          IconButton(
            tooltip: 'Salin rincian',
            icon: const Icon(Icons.copy_rounded),
            onPressed: _copySummary,
          ),
          IconButton(
            tooltip: 'Bagikan rincian',
            icon: const Icon(Icons.share_rounded),
            onPressed: _shareSummary,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          // 1. Daftar Peserta & Pembayar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Peserta (${_participants.length})', style: tt.titleMedium),
              FilledButton.tonalIcon(
                onPressed: () => _addParticipantDialog(people),
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Tambah Orang'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final p in _participants)
                InputChip(
                  avatar: Icon(
                    p.isSelf
                        ? Icons.person_rounded
                        : Icons.person_outline_rounded,
                    size: 18,
                  ),
                  label: Text(p.isSelf ? '${p.name} (Kamu)' : p.name),
                  onDeleted: p.isSelf ? null : () => _removeParticipant(p),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: DropdownButtonFormField<String>(
                initialValue: _payerId,
                decoration: const InputDecoration(
                  labelText: 'Siapa yang membayar struk ini?',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
                items: [
                  for (final p in _participants)
                    DropdownMenuItem(
                      value: p.id,
                      child: Text(
                        p.isSelf ? 'Saya (masuk Piutang teman)' : p.name,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _payerId = v);
                },
              ),
            ),
          ),

          // 2. Pilih Pembeli Tiap Item
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pilih Item Tiap Orang', style: tt.titleMedium),
              TextButton.icon(
                onPressed: _addExtraItemDialog,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Item'),
              ),
            ],
          ),
          if (!res.allItemsAssigned)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '${res.unassignedItems.length} item belum dipilih pembelinya.',
                style: tt.bodySmall?.copyWith(color: cs.error),
              ),
            ),
          for (var i = 0; i < _items.length; i++) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _items[i].name,
                            style: tt.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          CurrencyFormatter.format(_items[i].amount),
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => _toggleAssignAll(i),
                          child: const Text('Semua'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final p in _participants)
                          FilterChip(
                            label: Text(p.name),
                            selected: _items[i].assignedPersonIds.contains(
                              p.id,
                            ),
                            onSelected: (_) => _toggleAssignment(i, p.id),
                          ),
                      ],
                    ),
                    if (_items[i].assignedPersonIds.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Patungan ${_items[i].assignedPersonIds.length} orang • ~${CurrencyFormatter.format(_items[i].amount ~/ _items[i].assignedPersonIds.length)}/orang',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      )
                    else if (_items[i].assignedPersonIds.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Pilih minimal 1 orang untuk item ini',
                          style: tt.bodySmall?.copyWith(color: cs.error),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],

          if (hasExtras) ...[
            const SizedBox(height: 6),
            Card(
              child: SwitchListTile(
                title: const Text(
                  'Bagi pajak/service/diskon secara proporsional',
                ),
                subtitle: Text(
                  _proportionalExtras
                      ? 'Sesuai porsi pesanan tiap orang'
                      : 'Dibagi rata ke semua peserta aktif',
                ),
                value: _proportionalExtras,
                onChanged: (v) => setState(() => _proportionalExtras = v),
              ),
            ),
          ],

          // 3. Ringkasan Pembagian Per Orang
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Pembagian Per Orang', style: tt.titleMedium),
              Text(
                'Total ${CurrencyFormatter.format(res.grandTotal)}',
                style: tt.labelLarge?.copyWith(color: cs.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final pr in res.personResults) ...[
            Card(
              margin: const EdgeInsets.only(bottom: 10),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          backgroundColor: pr.participant.id == _payer.id
                              ? cs.primaryContainer
                              : cs.surfaceContainerHighest,
                          child: Text(
                            pr.participant.name[0].toUpperCase(),
                            style: tt.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  pr.participant.name,
                                  style: tt.titleMedium,
                                ),
                              ),
                              if (pr.participant.id == _payer.id) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Pembayar',
                                    style: tt.labelSmall?.copyWith(
                                      color: cs.onPrimaryContainer,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        AmountText(
                          amount: pr.total,
                          style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    if (pr.itemShares.isNotEmpty) ...[
                      const Divider(height: 16),
                      for (final share in pr.itemShares)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  share.sharedByCount > 1
                                      ? '• ${share.itemName} (÷${share.sharedByCount})'
                                      : '• ${share.itemName}',
                                  style: tt.bodySmall,
                                ),
                              ),
                              Text(
                                CurrencyFormatter.format(share.shareAmount),
                                style: tt.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      if (pr.taxShare > 0) _ExtraRow('Pajak', pr.taxShare),
                      if (pr.serviceShare > 0)
                        _ExtraRow('Service / Layanan', pr.serviceShare),
                      if (pr.discountShare > 0)
                        _ExtraRow('Diskon', -pr.discountShare),
                    ] else
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Belum ada item dipilih',
                          style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],

          // 4. Opsi Penyimpanan (3 pilihan eksplisit)
          const SizedBox(height: 16),
          Text('Opsi Penyimpanan', style: tt.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _SaveModeOption(
                  selected: _saveMode == _SplitSaveMode.debtAndTransaction,
                  icon: Icons.handshake_rounded,
                  title: _payer.isSelf
                      ? 'Simpan ke Riwayat Transaksi & Piutang'
                      : 'Simpan sebagai Hutang ke ${_payer.name}',
                  subtitle: _payer.isSelf
                      ? 'Porsi Saya masuk pengeluaran, porsi teman otomatis jadi Piutang di menu Hutang-Piutang'
                      : 'Porsi Saya otomatis tercatat sebagai Hutang ke ${_payer.name} di menu Hutang-Piutang',
                  onTap: () => setState(
                    () => _saveMode = _SplitSaveMode.debtAndTransaction,
                  ),
                ),
                const Divider(height: 1),
                _SaveModeOption(
                  selected: _saveMode == _SplitSaveMode.regularTransaction,
                  icon: Icons.receipt_long_rounded,
                  title: 'Simpan ke Transaksi Biasa saja',
                  subtitle: 'Catat total struk ke riwayat pengeluaran biasa tanpa membuat catatan hutang/piutang',
                  onTap: () => setState(
                    () => _saveMode = _SplitSaveMode.regularTransaction,
                  ),
                ),
                const Divider(height: 1),
                _SaveModeOption(
                  selected: _saveMode == _SplitSaveMode.checkOnly,
                  icon: Icons.calculate_outlined,
                  title: 'Tidak Disimpan (Hanya Cek Pembagian)',
                  subtitle: 'Hanya melihat & membagikan rincian per orang tanpa mengubah saldo/riwayat',
                  onTap: () =>
                      setState(() => _saveMode = _SplitSaveMode.checkOnly),
                ),
              ],
            ),
          ),

          // Pengaturan Dompet & Kategori jika mode membutuhkan simpan
          if (_saveMode == _SplitSaveMode.regularTransaction ||
              (_saveMode == _SplitSaveMode.debtAndTransaction &&
                  _payer.isSelf)) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    if (wallets.isNotEmpty)
                      DropdownButtonFormField<int>(
                        initialValue: _walletId,
                        decoration: const InputDecoration(
                          labelText: 'Dompet / Saku Pembayar',
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
                          _pocketId = null;
                        }),
                      ),
                    if (walletPockets.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int?>(
                        initialValue: _pocketId,
                        decoration: const InputDecoration(
                          labelText: 'Pos Budget Saku (opsional)',
                        ),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Saldo Bebas'),
                          ),
                          for (final p in walletPockets)
                            DropdownMenuItem<int?>(
                              value: p.pocket.id,
                              child: Text(p.pocket.name),
                            ),
                        ],
                        onChanged: (v) => setState(() => _pocketId = v),
                      ),
                    ],
                    if (categories.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int?>(
                        initialValue: _categoryId,
                        decoration: const InputDecoration(
                          labelText: 'Kategori Pengeluaran',
                        ),
                        items: [
                          for (final c in categories)
                            DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                        ],
                        onChanged: (v) => setState(() => _categoryId = v),
                      ),
                    ],
                    if (_saveMode == _SplitSaveMode.debtAndTransaction &&
                        _payer.isSelf) ...[
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Catat porsi Saya ke pengeluaran'),
                        subtitle: const Text(
                          'Matikan jika hanya ingin mencatat piutang teman saja',
                        ),
                        value: _recordSelfExpense,
                        onChanged: (v) =>
                            setState(() => _recordSelfExpense = v),
                      ),
                    ],
                    if (_saveMode == _SplitSaveMode.regularTransaction &&
                        _items.length > 1) ...[
                      const SizedBox(height: 6),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Pecah per item di riwayat'),
                        value: _splitRegularPerItem,
                        onChanged: (v) =>
                            setState(() => _splitRegularPerItem = v),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant)),
          ),
          child: Row(
            children: [
              OutlinedButton.icon(
                onPressed: _shareSummary,
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Bagikan'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saving
                      ? null
                      : () => _executeAction(wallets, categories),
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _saveMode == _SplitSaveMode.checkOnly
                              ? Icons.check_circle_outline_rounded
                              : Icons.save_rounded,
                        ),
                  label: Text(switch (_saveMode) {
                    _SplitSaveMode.debtAndTransaction =>
                      _payer.isSelf
                          ? 'Simpan Transaksi & Piutang'
                          : 'Simpan ke Hutang',
                    _SplitSaveMode.regularTransaction =>
                      'Simpan Transaksi Biasa',
                    _SplitSaveMode.checkOnly => 'Selesai (Tanpa Simpan)',
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExtraRow extends StatelessWidget {
  const _ExtraRow(this.label, this.amount);

  final String label;
  final int amount;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final formatted = amount < 0
        ? '-${CurrencyFormatter.format(amount.abs())}'
        : CurrencyFormatter.format(amount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '  + $label',
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Text(
            formatted,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _SaveModeOption extends StatelessWidget {
  const _SaveModeOption({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(
        selected
            ? Icons.radio_button_checked_rounded
            : Icons.radio_button_off_rounded,
        color: selected ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
      subtitle: Text(subtitle),
      trailing: Icon(icon, size: 20, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }
}
