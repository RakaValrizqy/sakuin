import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/features/budget/budget_providers.dart';
import 'package:sakuin/features/category/category_providers.dart';

Future<void> showBudgetFormSheet(BuildContext context, {Budget? existing}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BudgetFormSheet(existing: existing),
  );
}

class BudgetFormSheet extends ConsumerStatefulWidget {
  const BudgetFormSheet({super.key, this.existing});

  final Budget? existing;

  @override
  ConsumerState<BudgetFormSheet> createState() => _BudgetFormSheetState();
}

class _BudgetFormSheetState extends ConsumerState<BudgetFormSheet> {
  final _amountCtrl = TextEditingController();
  int? _categoryId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    _categoryId = b?.categoryId;
    if (b != null) {
      _amountCtrl.text = CurrencyFormatter.format(b.amount, withSymbol: false);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = AmountParser.parse(_amountCtrl.text) ?? 0;
    if (amount <= 0 || _saving) return;
    setState(() => _saving = true);
    await ref
        .read(budgetActionsProvider)
        .saveBudget(
          existingId: widget.existing?.id,
          categoryId: _categoryId,
          amount: amount,
        );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(expenseCategoriesProvider).valueOrNull ?? const [];
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
                  ? 'Atur Anggaran Bulanan'
                  : 'Edit Anggaran',
              style: tt.headlineSmall,
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<int?>(
              initialValue: _categoryId,
              decoration: const InputDecoration(labelText: 'Target anggaran'),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Total Pengeluaran Bulanan'),
                ),
                for (final c in categories)
                  DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
              ],
              onChanged: widget.existing == null
                  ? (v) => setState(() => _categoryId = v)
                  : null,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Batas anggaran per periode',
                prefixText: 'Rp ',
                hintText: '1.500.000',
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Simpan Anggaran'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
