import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/features/category/category_providers.dart';
import 'package:sakuin/features/recurring/recurring_service.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

Future<int?> showRecurringFormSheet(
  BuildContext context, {
  RecurringRule? existing,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => RecurringFormSheet(existing: existing),
  );
}

class RecurringFormSheet extends ConsumerStatefulWidget {
  const RecurringFormSheet({super.key, this.existing});

  final RecurringRule? existing;

  @override
  ConsumerState<RecurringFormSheet> createState() => _RecurringFormSheetState();
}

class _RecurringFormSheetState extends ConsumerState<RecurringFormSheet> {
  final _titleCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late String _type;
  late String _frequency;
  int? _categoryId;
  int? _walletId;
  late DateTime _nextDue;
  late bool _autoCreate;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final r = widget.existing;
    _titleCtrl.text = r?.title ?? '';
    _amountCtrl.text = r != null
        ? CurrencyFormatter.format(r.amount, withSymbol: false)
        : '';
    _noteCtrl.text = r?.note ?? '';
    _type = r?.type ?? 'expense';
    _frequency = r?.frequency ?? 'monthly';
    _categoryId = r?.categoryId;
    _walletId = r?.walletId;
    _nextDue = r != null
        ? AppDateUtils.fromDayKey(r.nextDue)
        : DateTime.now().add(const Duration(days: 1));
    _autoCreate = r?.autoCreate ?? true;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = AmountParser.parse(_amountCtrl.text) ?? 0;
    if (_titleCtrl.text.trim().isEmpty || amount <= 0 || _walletId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lengkapi judul, nominal, dan dompet terlebih dahulu'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    final id = await ref
        .read(recurringServiceProvider)
        .saveRule(
          id: widget.existing?.id,
          title: _titleCtrl.text.trim(),
          type: _type,
          amount: amount,
          categoryId: _categoryId,
          walletId: _walletId!,
          note: _noteCtrl.text.trim(),
          frequency: _frequency,
          dayOfWeek: _frequency == 'weekly' ? _nextDue.weekday : null,
          dayOfMonth: _frequency == 'monthly'
              ? _nextDue.day.clamp(1, 28)
              : null,
          nextDue: AppDateUtils.toDayKey(_nextDue),
          autoCreate: _autoCreate,
          isActive: widget.existing?.isActive ?? true,
        );
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final categories =
        (_type == 'expense'
            ? ref.watch(expenseCategoriesProvider).valueOrNull
            : ref.watch(incomeCategoriesProvider).valueOrNull) ??
        const [];

    if (_walletId == null && wallets.isNotEmpty) {
      _walletId = wallets.first.wallet.id;
    }
    if ((_categoryId == null || !categories.any((c) => c.id == _categoryId)) &&
        categories.isNotEmpty) {
      _categoryId = categories.first.id;
    }

    final tt = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null
                  ? 'Tambah Transaksi Berulang'
                  : 'Edit Transaksi Berulang',
              style: tt.headlineSmall,
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'expense', label: Text('Pengeluaran')),
                ButtonSegment(value: 'income', label: Text('Pemasukan')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() {
                _type = s.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _titleCtrl,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Nama transaksi rutin',
                hintText: 'Contoh: Gaji Bulanan, Internet, Cicilan Motor',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Nominal',
                prefixText: 'Rp ',
                hintText: '350.000',
              ),
            ),
            const SizedBox(height: 12),
            Text('Frekuensi', style: tt.labelMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'daily', label: Text('Harian')),
                ButtonSegment(value: 'weekly', label: Text('Mingguan')),
                ButtonSegment(value: 'monthly', label: Text('Bulanan')),
              ],
              selected: {_frequency},
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Kategori'),
              items: [
                for (final c in categories)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => setState(() => _categoryId = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              initialValue: _walletId,
              decoration: const InputDecoration(labelText: 'Dompet'),
              items: [
                for (final wb in wallets)
                  DropdownMenuItem(
                    value: wb.wallet.id,
                    child: Text(wb.wallet.name),
                  ),
              ],
              onChanged: (v) => setState(() => _walletId = v),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_repeat_rounded),
              title: const Text('Jatuh tempo berikutnya'),
              trailing: Text(
                AppDateUtils.formatShortDate(_nextDue),
                style: tt.titleSmall,
              ),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _nextDue,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                );
                if (picked != null) setState(() => _nextDue = picked);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Catat otomatis saat jatuh tempo'),
              subtitle: const Text(
                'Jika mati, aplikasi akan meminta konfirmasi sebelum mencatat',
              ),
              value: _autoCreate,
              onChanged: (v) => setState(() => _autoCreate = v),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Simpan Aturan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
