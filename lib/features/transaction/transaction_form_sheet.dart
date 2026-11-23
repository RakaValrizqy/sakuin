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
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/transaction/widgets/custom_keypad.dart';
import 'package:sakuin/features/wallet/wallet_form_sheet.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

Future<bool?> showTransactionFormSheet(
  BuildContext context, {
  TransactionDetail? existing,
  TransactionDetail? duplicateFrom,
  ItemMemoryData? prefillItem,
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
    this.initialType = 'expense',
  });

  final TransactionDetail? existing;
  final TransactionDetail? duplicateFrom;
  final ItemMemoryData? prefillItem;
  final String initialType;

  @override
  ConsumerState<TransactionFormSheet> createState() =>
      _TransactionFormSheetState();
}

class _TransactionFormSheetState extends ConsumerState<TransactionFormSheet> {
  late String _type; // 'expense' | 'income' | 'transfer'
  String _rawAmount = '';
  final _itemCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _feeCtrl = TextEditingController();
  final _itemFocus = FocusNode();

  int? _categoryId;
  int? _walletId;
  int? _toWalletId;
  late DateTime _occurredAt;
  bool _showNoteField = false;
  bool _showKeypad = true;
  bool _saving = false;

  List<Category> _orderedCategories = [];
  List<ItemMemoryData> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _occurredAt = DateTime.now();

    if (widget.existing != null) {
      final tx = widget.existing!.transaction;
      _type = tx.type;
      _rawAmount = tx.amount.toString();
      _itemCtrl.text = tx.itemName ?? '';
      _noteCtrl.text = tx.note;
      _feeCtrl.text = tx.fee > 0 ? tx.fee.toString() : '';
      _categoryId = tx.categoryId;
      _walletId = tx.walletId;
      _toWalletId = tx.toWalletId;
      _occurredAt = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt)
          .toLocal();
      _showNoteField = tx.note.isNotEmpty;
      _showKeypad = false;
    } else if (widget.duplicateFrom != null) {
      final tx = widget.duplicateFrom!.transaction;
      _type = tx.type;
      _rawAmount = tx.amount.toString();
      _itemCtrl.text = tx.itemName ?? '';
      _noteCtrl.text = tx.note;
      _feeCtrl.text = tx.fee > 0 ? tx.fee.toString() : '';
      _categoryId = tx.categoryId;
      _walletId = tx.walletId;
      _toWalletId = tx.toWalletId;
      _occurredAt = DateTime.now();
      _showNoteField = tx.note.isNotEmpty;
      _showKeypad = false;
    } else if (widget.prefillItem != null) {
      final item = widget.prefillItem!;
      _type = item.type;
      _rawAmount = item.lastAmount.toString();
      _itemCtrl.text = item.displayName;
      _noteCtrl.text = item.lastNote;
      _categoryId = item.lastCategoryId;
      _walletId = item.lastWalletId;
      _occurredAt = DateTime.now();
      _showNoteField = item.lastNote.isNotEmpty;
      _showKeypad = false;
    } else {
      _type = widget.initialType;
      _walletId = ref.read(settingsProvider).lastWalletId;
    }

    _itemFocus.addListener(() {
      if (_itemFocus.hasFocus && _showKeypad) {
        setState(() => _showKeypad = false);
      }
    });

    _loadCategories();
    _loadSuggestions('');
  }

  @override
  void dispose() {
    _itemCtrl.dispose();
    _noteCtrl.dispose();
    _feeCtrl.dispose();
    _itemFocus.dispose();
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

  void _applyItemSuggestion(ItemMemoryData item) {
    final haptics = ref.read(settingsProvider).hapticsEnabled;
    AppHaptics.selection(haptics);
    FocusScope.of(context).unfocus();
    setState(() {
      _type = item.type;
      _itemCtrl.text = item.displayName;
      _rawAmount = item.lastAmount.toString();
      if (item.lastCategoryId != null) _categoryId = item.lastCategoryId;
      if (item.lastWalletId != null) _walletId = item.lastWalletId;
      _noteCtrl.text = item.lastNote;
      if (item.lastNote.isNotEmpty) _showNoteField = true;
      _suggestions = [];
      _showKeypad = false;
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
      _rawAmount = tx.amount.toString();
      _itemCtrl.text = tx.itemName ?? '';
      _noteCtrl.text = tx.note;
      _feeCtrl.text = tx.fee > 0 ? tx.fee.toString() : '';
      _categoryId = tx.categoryId;
      _walletId = tx.walletId;
      _toWalletId = tx.toWalletId;
      _occurredAt = DateTime.now();
      _showNoteField = tx.note.isNotEmpty;
      _showKeypad = false;
    });
    await _loadCategories();
  }

  int get _parsedAmount => AmountParser.parse(_rawAmount) ?? 0;

  void _onKeypadInput(String token) {
    setState(() {
      if (_rawAmount.length > 24) return;
      // Cegah dua operator berurutan
      const ops = ['+', '−', '×', '÷'];
      if (ops.contains(token)) {
        if (_rawAmount.isEmpty) return;
        final last = _rawAmount[_rawAmount.length - 1];
        if (ops.contains(last)) {
          _rawAmount = _rawAmount.substring(0, _rawAmount.length - 1) + token;
          return;
        }
      }
      _rawAmount += token;
    });
  }

  void _onKeypadBackspace() {
    if (_rawAmount.isEmpty) return;
    setState(() {
      if (_rawAmount.endsWith('jt')) {
        _rawAmount = _rawAmount.substring(0, _rawAmount.length - 2);
      } else {
        _rawAmount = _rawAmount.substring(0, _rawAmount.length - 1);
      }
    });
  }

  void _onKeypadEvaluate() {
    final val = AmountParser.parse(_rawAmount);
    if (val != null) {
      setState(() => _rawAmount = val.toString());
    }
  }

  Future<void> _pickAllCategories() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      builder: (ctx) => ListView(
        padding: const EdgeInsets.all(16),
        shrinkWrap: true,
        children: [
          Text('Pilih Kategori', style: Theme.of(ctx).textTheme.titleLarge),
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
    if (selected != null) {
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
      if (_toWalletId == null || _toWalletId == _walletId) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pilih dompet tujuan yang berbeda untuk transfer'),
          ),
        );
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
          fee: fee,
          note: _noteCtrl.text.trim(),
          itemName: _type == 'transfer' ? null : _itemCtrl.text.trim(),
          occurredAt: _occurredAt,
        );

    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final haptics = ref.watch(settingsProvider.select((s) => s.hapticsEnabled));

    if (_walletId == null && wallets.isNotEmpty) {
      _walletId = wallets.first.wallet.id;
    } else if (_walletId != null &&
        wallets.isNotEmpty &&
        !wallets.any((w) => w.wallet.id == _walletId)) {
      _walletId = wallets.first.wallet.id;
    }
    if (_type == 'transfer' && wallets.length >= 2) {
      if (_toWalletId == null || _toWalletId == _walletId) {
        _toWalletId = wallets
            .firstWhere(
              (w) => w.wallet.id != _walletId,
              orElse: () => wallets.last,
            )
            .wallet
            .id;
      }
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
                  },
                ),
                const SizedBox(height: 12),

                // 2. Display Nominal Pintar (ketuk untuk buka/tutup keypad kustom)
                InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _showKeypad = !_showKeypad);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: accentColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: _showKeypad
                            ? accentColor
                            : accentColor.withValues(alpha: 0.35),
                        width: _showKeypad ? 2 : 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Nominal',
                              style: tt.labelMedium?.copyWith(
                                color: accentColor,
                              ),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showKeypad
                                      ? Icons.keyboard_hide_rounded
                                      : Icons.dialpad_rounded,
                                  size: 18,
                                  color: accentColor,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _showKeypad ? 'Sembunyikan' : 'Keypad',
                                  style: tt.labelSmall?.copyWith(
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            CurrencyFormatter.format(_parsedAmount),
                            style: tt.headlineMedium?.copyWith(
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              color: accentColor,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                        if (_rawAmount.isNotEmpty &&
                            (AmountParser.hasExpression(_rawAmount) ||
                                _rawAmount.contains('k') ||
                                _rawAmount.contains('jt')))
                          Text(
                            _rawAmount,
                            style: tt.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                if (_showKeypad) ...[
                  const SizedBox(height: 10),
                  CustomAmountKeypad(
                    onInput: _onKeypadInput,
                    onBackspace: _onKeypadBackspace,
                    onClear: () => setState(() => _rawAmount = ''),
                    onEvaluate: _onKeypadEvaluate,
                    hapticsEnabled: haptics,
                    showEvaluate: AmountParser.hasExpression(_rawAmount),
                  ),
                ],
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
                              '${item.displayName} • ${CurrencyFormatter.formatCompact(item.lastAmount)}',
                            ),
                            onPressed: () => _applyItemSuggestion(item),
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
                            setState(() => _walletId = wb.wallet.id);
                          },
                        ),
                    ],
                  ),
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
                            setState(() => _walletId = wb.wallet.id);
                          },
                        ),
                    ],
                  ),
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
                          onSelected: wb.wallet.id == _walletId
                              ? null
                              : (_) {
                                  AppHaptics.selection(haptics);
                                  setState(() => _toWalletId = wb.wallet.id);
                                },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _feeCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Biaya admin transfer (opsional)',
                      prefixText: 'Rp ',
                      hintText: '0 (mis. 2500 atau 6,5k)',
                    ),
                  ),
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
                        _showKeypad = false;
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
