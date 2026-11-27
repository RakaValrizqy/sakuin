import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/utils/quick_input_parser.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/core/widgets/nominal_shortcut_bar.dart';
import 'package:sakuin/features/category/category_form_sheet.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/income_allocation_sheet.dart';
import 'package:sakuin/features/wallet/wallet_form_sheet.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

Future<bool?> showTransactionFormSheet(
  BuildContext context, {
  TransactionDetail? existing,
  TransactionDetail? duplicateFrom,
  ItemMemoryData? prefillItem,
  QuickParsedTransaction? prefillParsed,
  String initialType = 'expense',
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.94,
      child: TransactionFormSheet(
        existing: existing,
        duplicateFrom: duplicateFrom,
        prefillItem: prefillItem,
        prefillParsed: prefillParsed,
        initialType: initialType,
      ),
    ),
  );
}

class TransactionFormSheet extends ConsumerStatefulWidget {
  const TransactionFormSheet({
    super.key,
    this.existing,
    this.duplicateFrom,
    this.prefillItem,
    this.prefillParsed,
    this.initialType = 'expense',
  });

  final TransactionDetail? existing;
  final TransactionDetail? duplicateFrom;
  final ItemMemoryData? prefillItem;
  final QuickParsedTransaction? prefillParsed;
  final String initialType;

  @override
  ConsumerState<TransactionFormSheet> createState() =>
      _TransactionFormSheetState();
}

class _TransactionFormSheetState extends ConsumerState<TransactionFormSheet> {
  late String _type; // 'expense' | 'income' | 'transfer'
  final _amountCtrl = TextEditingController();
  final _itemCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _amountFocus = FocusNode();
  final _itemFocus = FocusNode();
  final _merchantFocus = FocusNode();

  int? _categoryId;
  int? _walletId;
  int? _toWalletId;
  int? _pocketId;
  int? _toPocketId;
  late DateTime _occurredAt;
  bool _showNoteField = false;
  bool _saving = false;

  /// Khusus pemasukan baru di saku yang punya pos budget: langsung buka opsi bagi persentase (%)
  /// setelah simpan, kecuali pengguna memilih 1 pos tertentu atau memilih Belum Dialokasikan.
  bool _splitIncomeByPercent = true;

  List<Category> _orderedCategories = [];
  List<ItemMemoryData> _suggestions = [];
  List<MerchantMemoryData> _merchantSuggestions = [];

  void _setAmountValue(int amount) {
    final text = amount > 0
        ? CurrencyFormatter.format(amount, withSymbol: false)
        : '';
    _amountCtrl.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void initState() {
    super.initState();
    _occurredAt = DateTime.now();

    if (widget.existing != null) {
      final tx = widget.existing!.transaction;
      _type = tx.type;
      _setAmountValue(tx.amount);
      _itemCtrl.text = tx.itemName ?? '';
      _merchantCtrl.text = tx.merchantName ?? '';
      _noteCtrl.text = tx.note;
      _feeCtrl.text = tx.fee > 0
          ? CurrencyFormatter.format(tx.fee, withSymbol: false)
          : '';
      _categoryId = tx.categoryId;
      _walletId = tx.walletId;
      _toWalletId = tx.toWalletId;
      _pocketId = tx.pocketId;
      _toPocketId = tx.toPocketId;
      _occurredAt = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt)
          .toLocal();
      _showNoteField = tx.note.isNotEmpty;
    } else if (widget.duplicateFrom != null) {
      final tx = widget.duplicateFrom!.transaction;
      _type = tx.type;
      _setAmountValue(tx.amount);
      _itemCtrl.text = tx.itemName ?? '';
      _merchantCtrl.text = tx.merchantName ?? '';
      _noteCtrl.text = tx.note;
      _feeCtrl.text = tx.fee > 0
          ? CurrencyFormatter.format(tx.fee, withSymbol: false)
          : '';
      _categoryId = tx.categoryId;
      _walletId = tx.walletId;
      _toWalletId = tx.toWalletId;
      _pocketId = tx.pocketId;
      _toPocketId = tx.toPocketId;
      _occurredAt = DateTime.now();
      _showNoteField = tx.note.isNotEmpty;
    } else if (widget.prefillItem != null) {
      final item = widget.prefillItem!;
      _type = item.type;
      _setAmountValue(item.lastAmount);
      _itemCtrl.text = item.displayName;
      _merchantCtrl.text = item.lastMerchantName ?? '';
      _noteCtrl.text = item.lastNote;
      _categoryId = item.lastCategoryId;
      _walletId = item.lastWalletId;
      _pocketId = item.lastPocketId;
      _occurredAt = DateTime.now();
      _showNoteField = item.lastNote.isNotEmpty;
    } else if (widget.prefillParsed != null) {
      final p = widget.prefillParsed!;
      _type = p.type;
      _setAmountValue(p.amount);
      _itemCtrl.text = p.itemName ?? '';
      _merchantCtrl.text = p.merchantName ?? '';
      _noteCtrl.text = p.note;
      _categoryId = p.categoryId;
      _walletId = p.walletId ?? ref.read(settingsProvider).lastWalletId;
      _pocketId = p.pocketId;
      _occurredAt = DateTime.now();
      _showNoteField = p.note.isNotEmpty;
    } else {
      _type = widget.initialType;
      _walletId = ref.read(settingsProvider).lastWalletId;
    }

    _loadCategories();
    _loadSuggestions('');
    _loadMerchantSuggestions('');
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _itemCtrl.dispose();
    _merchantCtrl.dispose();
    _noteCtrl.dispose();
    _feeCtrl.dispose();
    _amountFocus.dispose();
    _itemFocus.dispose();
    _merchantFocus.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    if (_type == 'transfer') {
      if (mounted) setState(() => _orderedCategories = []);
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final cats = await db.getCategoriesByRecentUsage(_type);
    if (!mounted) return;
    setState(() {
      _orderedCategories = cats;
      if (_categoryId == null || !cats.any((c) => c.id == _categoryId)) {
        _categoryId = cats.isNotEmpty ? cats.first.id : null;
      }
    });
  }

  Future<void> _loadSuggestions(String query) async {
    if (_type == 'transfer') {
      if (mounted) setState(() => _suggestions = []);
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final results = await db.searchItemMemory(query, type: _type, limit: 6);
    if (!mounted) return;
    setState(() => _suggestions = results);
  }

  Future<void> _loadMerchantSuggestions(String query) async {
    if (_type == 'transfer') {
      if (mounted) setState(() => _merchantSuggestions = []);
      return;
    }
    final db = ref.read(appDatabaseProvider);
    final results = await db.searchMerchantMemory(query, type: _type, limit: 6);
    if (!mounted) return;
    setState(() => _merchantSuggestions = results);
  }

  void _applyItemSuggestion(ItemMemoryData item) {
    final haptics = ref.read(settingsProvider).hapticsEnabled;
    AppHaptics.selection(haptics);
    FocusScope.of(context).unfocus();
    setState(() {
      _type = item.type;
      _itemCtrl.text = item.displayName;
      if (item.lastMerchantName != null &&
          item.lastMerchantName!.trim().isNotEmpty) {
        _merchantCtrl.text = item.lastMerchantName!.trim();
      }
      _setAmountValue(item.lastAmount);
      if (item.lastCategoryId != null) _categoryId = item.lastCategoryId;
      if (item.lastWalletId != null) _walletId = item.lastWalletId;
      _pocketId = item.lastPocketId;
      _noteCtrl.text = item.lastNote;
      if (item.lastNote.isNotEmpty) _showNoteField = true;
      _suggestions = [];
    });
  }

  void _applyMerchantSuggestion(MerchantMemoryData merchant) {
    final haptics = ref.read(settingsProvider).hapticsEnabled;
    AppHaptics.selection(haptics);
    FocusScope.of(context).unfocus();
    setState(() {
      _type = merchant.type;
      _merchantCtrl.text = merchant.displayMerchant;
      if (merchant.lastItemName != null &&
          merchant.lastItemName!.trim().isNotEmpty) {
        _itemCtrl.text = merchant.lastItemName!.trim();
      }
      if (merchant.lastAmount > 0) {
        _setAmountValue(merchant.lastAmount);
      }
      if (merchant.lastCategoryId != null) {
        _categoryId = merchant.lastCategoryId;
      }
      if (merchant.lastWalletId != null) {
        _walletId = merchant.lastWalletId;
      }
      _pocketId = merchant.lastPocketId;
      _noteCtrl.text = merchant.lastNote;
      if (merchant.lastNote.isNotEmpty) _showNoteField = true;
      _merchantSuggestions = [];
    });
  }

  Future<void> _repeatLastTransaction() async {
    final latest = await ref.read(appDatabaseProvider).getLatestTransaction();
    if (!mounted) return;
    if (latest == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada transaksi sebelumnya')),
      );
      return;
    }
    final tx = latest.transaction;
    AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
    setState(() {
      _type = tx.type;
      _setAmountValue(tx.amount);
      _itemCtrl.text = tx.itemName ?? '';
      _merchantCtrl.text = tx.merchantName ?? '';
      _noteCtrl.text = tx.note;
      _feeCtrl.text = tx.fee > 0
          ? CurrencyFormatter.format(tx.fee, withSymbol: false)
          : '';
      _categoryId = tx.categoryId;
      _walletId = tx.walletId;
      _toWalletId = tx.toWalletId;
      _pocketId = tx.pocketId;
      _toPocketId = tx.toPocketId;
      _occurredAt = DateTime.now();
      _showNoteField = tx.note.isNotEmpty;
    });
    await _loadCategories();
  }

  int get _parsedAmount => AmountParser.parse(_amountCtrl.text) ?? 0;

  Future<void> _createCategory() async {
    FocusScope.of(context).unfocus();
    final newId = await showCategoryFormSheet(
      context,
      initialType: _type == 'income' ? 'income' : 'expense',
    );
    if (newId == null || !mounted) return;
    await _loadCategories();
    if (!mounted) return;
    if (_orderedCategories.any((c) => c.id == newId)) {
      AppHaptics.selection(ref.read(settingsProvider).hapticsEnabled);
      setState(() => _categoryId = newId);
    }
  }

  Future<void> _pickAllCategories() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Pilih Kategori',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: () => Navigator.pop(ctx, -1),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Tambah'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final cat in _orderedCategories)
                ChoiceChip(
                  avatar: Icon(
                    AppIcons.fromKey(cat.icon),
                    size: 18,
                    color: Color(cat.color),
                  ),
                  label: Text(cat.name),
                  selected: _categoryId == cat.id,
                  onSelected: (_) => Navigator.pop(ctx, cat.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
    if (selected == -1) {
      await _createCategory();
    } else if (selected != null) {
      setState(() => _categoryId = selected);
    }
  }

  Future<void> _save(List<WalletWithBalance> wallets) async {
    if (_saving) return;
    final amount = _parsedAmount;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nominal lebih dari Rp 0')),
      );
      return;
    }
    if (wallets.isEmpty || _walletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Buat minimal satu dompet terlebih dahulu'),
        ),
      );
      return;
    }
    if (_type == 'transfer') {
      if (_toWalletId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pilih dompet tujuan untuk transfer')),
        );
        return;
      }
      if (_toWalletId == _walletId) {
        if (widget.existing != null || _pocketId == _toPocketId) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Pilih dompet tujuan berbeda, atau pilih pos budget asal & tujuan yang berbeda di saku yang sama',
              ),
            ),
          );
          return;
        }
        setState(() => _saving = true);
        await ref
            .read(walletActionsProvider)
            .allocateOrMovePocket(
              walletId: _walletId!,
              fromPocketId: _pocketId,
              toPocketId: _toPocketId,
              amount: amount,
              note: _noteCtrl.text.trim(),
            );
        AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
    }

    setState(() => _saving = true);
    final fee = _type == 'transfer' && _feeCtrl.text.trim().isNotEmpty
        ? (AmountParser.parse(_feeCtrl.text) ?? 0)
        : 0;

    await ref
        .read(transactionActionsProvider)
        .saveTransaction(
          existingId: widget.existing?.transaction.id,
          type: _type,
          amount: amount,
          walletId: _walletId!,
          categoryId: _type == 'transfer' ? null : _categoryId,
          toWalletId: _type == 'transfer' ? _toWalletId : null,
          pocketId: _pocketId,
          toPocketId: _type == 'transfer' ? _toPocketId : null,
          fee: fee,
          note: _noteCtrl.text.trim(),
          itemName: _type == 'transfer' ? null : _itemCtrl.text.trim(),
          merchantName: _type == 'transfer' ? null : _merchantCtrl.text.trim(),
          occurredAt: _occurredAt,
        );

    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);

    // Jika pemasukan baru di saku yang memiliki pos budget dan mode Bagi Persentase aktif,
    // langsung tampilkan sheet pembagian persentase ke tiap pos + kategori Belum Dialokasikan.
    if (mounted &&
        _type == 'income' &&
        widget.existing == null &&
        _pocketId == null &&
        _splitIncomeByPercent) {
      final walletPockets =
          ref
              .read(allActivePocketsProvider)
              .valueOrNull
              ?.where((p) => p.pocket.walletId == _walletId)
              .toList() ??
          const [];
      if (walletPockets.isNotEmpty) {
        final walletName =
            wallets
                .where((w) => w.wallet.id == _walletId)
                .firstOrNull
                ?.wallet
                .name ??
            'Saku';
        await showIncomePercentageAllocationSheet(
          context,
          walletId: _walletId!,
          walletName: walletName,
          incomeAmount: amount,
          pockets: walletPockets,
          incomeTitle: _itemCtrl.text.trim(),
        );
      }
    }

    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final allPockets =
        ref.watch(allActivePocketsProvider).valueOrNull ?? const [];
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticsEnabled));

    if (_walletId == null && wallets.isNotEmpty) {
      _walletId = wallets.first.wallet.id;
    } else if (_walletId != null &&
        wallets.isNotEmpty &&
        !wallets.any((w) => w.wallet.id == _walletId)) {
      _walletId = wallets.first.wallet.id;
    }
    if (_type == 'transfer' && wallets.isNotEmpty) {
      _toWalletId ??= wallets.length >= 2
          ? wallets
                .firstWhere(
                  (w) => w.wallet.id != _walletId,
                  orElse: () => wallets.last,
                )
                .wallet
                .id
          : wallets.first.wallet.id;
    }

    final walletPockets = allPockets
        .where((p) => p.pocket.walletId == _walletId)
        .toList();
    final toWalletPockets = allPockets
        .where((p) => p.pocket.walletId == _toWalletId)
        .toList();
    if (_pocketId != null &&
        !walletPockets.any((p) => p.pocket.id == _pocketId)) {
      _pocketId = null;
    }
    if (_toPocketId != null &&
        !toWalletPockets.any((p) => p.pocket.id == _toPocketId)) {
      _toPocketId = null;
    }

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final accentColor = _type == 'expense'
        ? AppColors.expense(context)
        : (_type == 'income'
              ? AppColors.income(context)
              : AppColors.transfer(context));

    final isEdit = widget.existing != null;
    final top5Categories = _orderedCategories.take(5).toList();
    // Jika kategori terpilih tidak ada di top 5, tampilkan juga di baris chip
    if (_categoryId != null &&
        !top5Categories.any((c) => c.id == _categoryId)) {
      final selectedCat = _orderedCategories
          .where((c) => c.id == _categoryId)
          .firstOrNull;
      if (selectedCat != null) {
        top5Categories.add(selectedCat);
      }
    }

    final today = DateTime.now();
    final todayKey = AppDateUtils.toDayKey(today);
    final yesterday = today.subtract(const Duration(days: 1));
    final yesterdayKey = AppDateUtils.toDayKey(yesterday);
    final selectedKey = AppDateUtils.toDayKey(_occurredAt);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header bar
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
                  child: Text(
                    isEdit ? 'Edit Transaksi' : 'Catat Transaksi',
                    style: tt.titleLarge,
                  ),
                ),
                if (!isEdit)
                  TextButton.icon(
                    onPressed: _repeatLastTransaction,
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: const Text('Ulangi terakhir'),
                  ),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                // 1. Tipe Transaksi (Segmented)
                SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(
                      value: 'expense',
                      label: Text(
                        'Pengeluaran',
                        style: TextStyle(
                          color: _type == 'expense'
                              ? AppColors.expense(context)
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ButtonSegment(
                      value: 'income',
                      label: Text(
                        'Pemasukan',
                        style: TextStyle(
                          color: _type == 'income'
                              ? AppColors.income(context)
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    ButtonSegment(
                      value: 'transfer',
                      label: Text(
                        'Transfer',
                        style: TextStyle(
                          color: _type == 'transfer'
                              ? AppColors.transfer(context)
                              : null,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  selected: {_type},
                  onSelectionChanged: (set) {
                    AppHaptics.selection(haptics);
                    setState(() => _type = set.first);
                    _loadCategories();
                    _loadSuggestions(_itemCtrl.text);
                    _loadMerchantSuggestions(_merchantCtrl.text);
                  },
                ),
                const SizedBox(height: 12),

                // 2. Input Nominal langsung memakai Numpad bawaan HP + Bar Shortcut (rb / jt / +10 rb)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: accentColor.withValues(alpha: 0.45),
                      width: 1.4,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Nominal',
                        style: tt.labelMedium?.copyWith(color: accentColor),
                      ),
                      TextField(
                        controller: _amountCtrl,
                        focusNode: _amountFocus,
                        autofocus:
                            !isEdit &&
                            widget.duplicateFrom == null &&
                            widget.prefillItem == null &&
                            widget.prefillParsed == null,
                        keyboardType: TextInputType.number,
                        inputFormatters: [ThousandsSeparatorInputFormatter()],
                        textAlign: TextAlign.right,
                        style: tt.headlineMedium?.copyWith(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          color: accentColor,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                        decoration: InputDecoration(
                          prefixText: 'Rp ',
                          prefixStyle: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: accentColor.withValues(alpha: 0.8),
                          ),
                          hintText: '0',
                          hintStyle: tt.headlineMedium?.copyWith(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: accentColor.withValues(alpha: 0.35),
                          ),
                          border: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 8),
                      NominalShortcutBar(
                        controller: _amountCtrl,
                        hapticsEnabled: haptics,
                        onChanged: () => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 3. Nama Item + Autocomplete Item Memory (untuk Pengeluaran / Pemasukan)
                if (_type != 'transfer') ...[
                  TextField(
                    controller: _itemCtrl,
                    focusNode: _itemFocus,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: _loadSuggestions,
                    decoration: InputDecoration(
                      labelText: 'Nama item (opsional, diingat otomatis)',
                      hintText: 'Contoh: Ayam goreng, Kopi susu, Bensin',
                      prefixIcon: const Icon(Icons.bolt_rounded),
                      suffixIcon: _itemCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _itemCtrl.clear();
                                _loadSuggestions('');
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, idx) {
                          final item = _suggestions[idx];
                          return ActionChip(
                            avatar: Icon(
                              item.isPinned
                                  ? Icons.push_pin_rounded
                                  : Icons.auto_awesome_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                            label: Text(
                              item.lastMerchantName != null &&
                                      item.lastMerchantName!.trim().isNotEmpty
                                  ? '${item.displayName} • ${item.lastMerchantName} • ${CurrencyFormatter.formatCompact(item.lastAmount)}'
                                  : '${item.displayName} • ${CurrencyFormatter.formatCompact(item.lastAmount)}',
                            ),
                            onPressed: () => _applyItemSuggestion(item),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // 3b. Nama Merchant / Toko + Autocomplete Pasangan Otomatis
                  TextField(
                    controller: _merchantCtrl,
                    focusNode: _merchantFocus,
                    textCapitalization: TextCapitalization.words,
                    onChanged: _loadMerchantSuggestions,
                    decoration: InputDecoration(
                      labelText: _type == 'expense'
                          ? 'Nama merchant / toko (opsional)'
                          : 'Sumber / pengirim (opsional)',
                      hintText: _type == 'expense'
                          ? 'Contoh: Indomaret, Kopi Kenangan, Gojek'
                          : 'Contoh: Kantor, Orang tua, Klien',
                      prefixIcon: const Icon(Icons.storefront_rounded),
                      suffixIcon: _merchantCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _merchantCtrl.clear();
                                _loadMerchantSuggestions('');
                                setState(() {});
                              },
                            )
                          : null,
                    ),
                  ),
                  if (_merchantSuggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 44,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _merchantSuggestions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, idx) {
                          final m = _merchantSuggestions[idx];
                          final parts = <String>[m.displayMerchant];
                          if (m.lastItemName != null &&
                              m.lastItemName!.trim().isNotEmpty) {
                            parts.add(m.lastItemName!.trim());
                          }
                          if (m.lastAmount > 0) {
                            parts.add(
                              CurrencyFormatter.formatCompact(m.lastAmount),
                            );
                          }
                          return ActionChip(
                            avatar: Icon(
                              Icons.storefront_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                            label: Text(parts.join(' • ')),
                            onPressed: () => _applyMerchantSuggestion(m),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),

                  // 4. Kategori (Top 5 terpakai terbaru + Lainnya...)
                  Text('Kategori', style: tt.labelMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final cat in top5Categories)
                        ChoiceChip(
                          avatar: Icon(
                            AppIcons.fromKey(cat.icon),
                            size: 18,
                            color: Color(cat.color),
                          ),
                          label: Text(cat.name),
                          selected: _categoryId == cat.id,
                          onSelected: (_) {
                            AppHaptics.selection(haptics);
                            setState(() => _categoryId = cat.id);
                          },
                        ),
                      if (_orderedCategories.length > 5)
                        ActionChip(
                          avatar: const Icon(Icons.apps_rounded, size: 18),
                          label: const Text('Lainnya...'),
                          onPressed: _pickAllCategories,
                        ),
                      ActionChip(
                        avatar: Icon(
                          Icons.add_rounded,
                          size: 18,
                          color: cs.primary,
                        ),
                        label: const Text('Tambah Kategori'),
                        onPressed: _createCategory,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                // 5. Dompet (chip) — atau Dari/Ke Dompet + Biaya Admin untuk Transfer
                if (wallets.isEmpty)
                  Card(
                    child: ListTile(
                      leading: const Icon(
                        Icons.account_balance_wallet_outlined,
                      ),
                      title: const Text('Belum ada dompet'),
                      trailing: FilledButton.tonal(
                        onPressed: () => showWalletFormSheet(context),
                        child: const Text('Buat'),
                      ),
                    ),
                  )
                else if (_type != 'transfer') ...[
                  Text('Dompet / Saku', style: tt.labelMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final wb in wallets)
                        ChoiceChip(
                          avatar: CategoryIconBadge(
                            iconKey: wb.wallet.icon,
                            colorValue: wb.wallet.color,
                            size: 24,
                            iconSize: 14,
                          ),
                          label: Text(wb.wallet.name),
                          selected: _walletId == wb.wallet.id,
                          onSelected: (_) {
                            AppHaptics.selection(haptics);
                            setState(() {
                              _walletId = wb.wallet.id;
                              _pocketId = null;
                            });
                          },
                        ),
                    ],
                  ),
                  if (walletPockets.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      _type == 'income' && !isEdit
                          ? 'Alokasi Pos Budget Saku'
                          : 'Pos Budget Saku (opsional)',
                      style: tt.labelMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (_type == 'income' && !isEdit)
                          ChoiceChip(
                            avatar: Icon(
                              Icons.pie_chart_rounded,
                              size: 16,
                              color: cs.primary,
                            ),
                            label: const Text('Bagi per Persentase (%)'),
                            selected:
                                _pocketId == null && _splitIncomeByPercent,
                            onSelected: (_) {
                              AppHaptics.selection(haptics);
                              setState(() {
                                _pocketId = null;
                                _splitIncomeByPercent = true;
                              });
                            },
                          ),
                        ChoiceChip(
                          label: Text(
                            _type == 'income' && !isEdit
                                ? 'Belum Dialokasikan'
                                : 'Saldo Bebas',
                          ),
                          selected:
                              _pocketId == null &&
                              !(_type == 'income' &&
                                  !isEdit &&
                                  _splitIncomeByPercent),
                          onSelected: (_) {
                            AppHaptics.selection(haptics);
                            setState(() {
                              _pocketId = null;
                              _splitIncomeByPercent = false;
                            });
                          },
                        ),
                        for (final p in walletPockets)
                          ChoiceChip(
                            avatar: Icon(
                              AppIcons.fromKey(p.pocket.icon),
                              size: 16,
                              color: Color(p.pocket.color),
                            ),
                            label: Text(
                              '${p.pocket.name} (${CurrencyFormatter.formatCompact(p.balance)})',
                            ),
                            selected: _pocketId == p.pocket.id,
                            onSelected: (_) {
                              AppHaptics.selection(haptics);
                              setState(() {
                                _pocketId = p.pocket.id;
                                _splitIncomeByPercent = false;
                              });
                            },
                          ),
                      ],
                    ),
                    if (_type == 'income' && isEdit && _parsedAmount > 0) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final walletName =
                              wallets
                                  .where((w) => w.wallet.id == _walletId)
                                  .firstOrNull
                                  ?.wallet
                                  .name ??
                              'Saku';
                          await showIncomePercentageAllocationSheet(
                            context,
                            walletId: _walletId!,
                            walletName: walletName,
                            incomeAmount: _parsedAmount,
                            pockets: walletPockets,
                            incomeTitle: _itemCtrl.text.trim(),
                          );
                        },
                        icon: const Icon(Icons.pie_chart_rounded, size: 18),
                        label: const Text(
                          'Bagi Pemasukan Ini per Persentase (%)',
                        ),
                      ),
                    ],
                  ],
                ] else ...[
                  Text('Dari Dompet', style: tt.labelMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final wb in wallets)
                        ChoiceChip(
                          label: Text(wb.wallet.name),
                          selected: _walletId == wb.wallet.id,
                          onSelected: (_) {
                            AppHaptics.selection(haptics);
                            setState(() {
                              _walletId = wb.wallet.id;
                              _pocketId = null;
                            });
                          },
                        ),
                    ],
                  ),
                  if (walletPockets.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Dari Pos Budget', style: tt.labelSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('Saldo Bebas'),
                          selected: _pocketId == null,
                          onSelected: (_) => setState(() => _pocketId = null),
                        ),
                        for (final p in walletPockets)
                          ChoiceChip(
                            label: Text(p.pocket.name),
                            selected: _pocketId == p.pocket.id,
                            onSelected: (_) =>
                                setState(() => _pocketId = p.pocket.id),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text('Ke Dompet', style: tt.labelMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final wb in wallets)
                        ChoiceChip(
                          label: Text(wb.wallet.name),
                          selected: _toWalletId == wb.wallet.id,
                          onSelected: (_) {
                            AppHaptics.selection(haptics);
                            setState(() {
                              _toWalletId = wb.wallet.id;
                              _toPocketId = null;
                            });
                          },
                        ),
                    ],
                  ),
                  if (toWalletPockets.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Ke Pos Budget', style: tt.labelSmall),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        ChoiceChip(
                          label: const Text('Saldo Bebas'),
                          selected: _toPocketId == null,
                          onSelected: (_) => setState(() => _toPocketId = null),
                        ),
                        for (final p in toWalletPockets)
                          ChoiceChip(
                            label: Text(p.pocket.name),
                            selected: _toPocketId == p.pocket.id,
                            onSelected: (_) =>
                                setState(() => _toPocketId = p.pocket.id),
                          ),
                      ],
                    ),
                  ],
                  if (_toWalletId != _walletId) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _feeCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [ThousandsSeparatorInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Biaya admin transfer (opsional)',
                        prefixText: 'Rp ',
                        hintText: '2.500',
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: 14),

                // 6. Tanggal (Hari ini / Kemarin / Pilih)
                Text('Tanggal', style: tt.labelMedium),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Hari ini'),
                      selected: selectedKey == todayKey,
                      onSelected: (_) {
                        AppHaptics.selection(haptics);
                        setState(() => _occurredAt = DateTime.now());
                      },
                    ),
                    ChoiceChip(
                      label: const Text('Kemarin'),
                      selected: selectedKey == yesterdayKey,
                      onSelected: (_) {
                        AppHaptics.selection(haptics);
                        final y = DateTime.now().subtract(
                          const Duration(days: 1),
                        );
                        setState(() => _occurredAt = y);
                      },
                    ),
                    ActionChip(
                      avatar: const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                      ),
                      label: Text(
                        selectedKey != todayKey && selectedKey != yesterdayKey
                            ? AppDateUtils.formatShortDate(_occurredAt)
                            : 'Pilih tanggal',
                      ),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _occurredAt,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() {
                            _occurredAt = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              _occurredAt.hour,
                              _occurredAt.minute,
                            );
                          });
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // 7. Catatan (tersembunyi sampai diketuk)
                if (!_showNoteField)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => setState(() {
                        _showNoteField = true;
                      }),
                      icon: const Icon(Icons.notes_rounded, size: 18),
                      label: const Text('Tambah catatan'),
                    ),
                  )
                else
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Catatan (opsional)',
                      hintText: 'Tambahkan keterangan singkat',
                    ),
                  ),
              ],
            ),
          ),

          // 8. Sticky Save Button (selalu terlihat)
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
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _saving ? null : () => _save(wallets),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(
                    isEdit
                        ? 'Simpan Perubahan'
                        : 'Simpan • ${CurrencyFormatter.format(_parsedAmount)}',
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
