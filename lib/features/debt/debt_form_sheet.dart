import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/features/debt/debt_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

Future<int?> showDebtFormSheet(
  BuildContext context, {
  DebtWithSummary? existing,
  String initialDirection = 'they_owe',
  String? prefillPersonName,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DebtFormSheet(
      existing: existing,
      initialDirection: initialDirection,
      prefillPersonName: prefillPersonName,
    ),
  );
}

class DebtFormSheet extends ConsumerStatefulWidget {
  const DebtFormSheet({
    super.key,
    this.existing,
    this.initialDirection = 'they_owe',
    this.prefillPersonName,
  });

  final DebtWithSummary? existing;
  final String initialDirection;
  final String? prefillPersonName;

  @override
  ConsumerState<DebtFormSheet> createState() => _DebtFormSheetState();
}

class _DebtFormSheetState extends ConsumerState<DebtFormSheet> {
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  late String _direction;
  late DateTime _createdAt;
  DateTime? _dueDate;
  late bool _affectWallet;
  int? _walletId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.person.name;
      _phoneCtrl.text = e.person.phone ?? '';
      _amountCtrl.text = CurrencyFormatter.format(
        e.debt.principal,
        withSymbol: false,
      );
      _noteCtrl.text = e.debt.note;
      _direction = e.debt.direction;
      _createdAt = DateTime.fromMillisecondsSinceEpoch(e.debt.createdAt)
          .toLocal();
      _dueDate = e.debt.dueDate != null
          ? DateTime.fromMillisecondsSinceEpoch(e.debt.dueDate!).toLocal()
          : null;
      _affectWallet = e.debt.walletId != null;
      _walletId = e.debt.walletId;
    } else {
      _nameCtrl.text = widget.prefillPersonName ?? '';
      _direction = widget.initialDirection;
      _createdAt = DateTime.now();
      _affectWallet = false;
      _walletId = ref.read(settingsProvider).lastWalletId;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final amount = AmountParser.parse(_amountCtrl.text) ?? 0;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nama teman / kontak')),
      );
      return;
    }
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan nominal lebih dari Rp 0')),
      );
      return;
    }

    setState(() => _saving = true);
    final id = await ref
        .read(debtActionsProvider)
        .saveDebt(
          existingId: widget.existing?.debt.id,
          personName: name,
          personPhone: _phoneCtrl.text.trim(),
          direction: _direction,
          principal: amount,
          note: _noteCtrl.text.trim(),
          createdAt: _createdAt,
          dueDate: _dueDate,
          walletId: _affectWallet ? _walletId : null,
        );
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    if (_walletId == null && wallets.isNotEmpty) {
      _walletId = wallets.first.wallet.id;
    }

    final query = _nameCtrl.text.trim().toLowerCase();
    final matchingPeople = people
        .where((p) => query.isEmpty || p.name.toLowerCase().contains(query))
        .take(6)
        .toList();

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

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
                  ? 'Catat Hutang / Piutang'
                  : 'Edit Hutang / Piutang',
              style: tt.headlineSmall,
            ),
            const SizedBox(height: 14),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'they_owe',
                  label: Text('Mereka Berutang'),
                ),
                ButtonSegment(value: 'i_owe', label: Text('Saya Berutang')),
              ],
              selected: {_direction},
              onSelectionChanged: (s) => setState(() => _direction = s.first),
            ),
            const SizedBox(height: 14),

            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nama teman',
                hintText: 'Ketik nama baru atau pilih kontak di bawah',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
            ),
            if (matchingPeople.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final p in matchingPeople)
                    ActionChip(
                      label: Text(p.name),
                      onPressed: () {
                        setState(() {
                          _nameCtrl.text = p.name;
                          if (p.phone != null) _phoneCtrl.text = p.phone!;
                        });
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 12),

            TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Nomor HP (opsional)',
                prefixIcon: Icon(Icons.phone_outlined),
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
                hintText: '150.000',
              ),
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _createdAt,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _createdAt = picked);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(AppDateUtils.formatShortDate(_createdAt)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate:
                            _dueDate ??
                            DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setState(() => _dueDate = picked);
                    },
                    icon: const Icon(Icons.alarm_rounded, size: 18),
                    label: Text(
                      _dueDate == null
                          ? 'Jatuh tempo'
                          : AppDateUtils.formatShortDate(_dueDate!),
                    ),
                  ),
                ),
              ],
            ),
            if (_dueDate != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _dueDate = null),
                  child: const Text('Hapus jatuh tempo'),
                ),
              ),
            const SizedBox(height: 6),

            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Catat ke dompet'),
              subtitle: Text(
                _direction == 'i_owe'
                    ? 'Saldo dompet bertambah saat pinjam & berkurang saat bayar (bukan pemasukan)'
                    : 'Saldo dompet berkurang saat meminjamkan & bertambah saat dibayar (bukan pengeluaran)',
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              value: _affectWallet,
              onChanged: wallets.isEmpty
                  ? null
                  : (v) => setState(() => _affectWallet = v),
            ),
            if (_affectWallet && wallets.isNotEmpty) ...[
              DropdownButtonFormField<int>(
                initialValue: _walletId,
                decoration: const InputDecoration(labelText: 'Dompet terkait'),
                items: [
                  for (final wb in wallets)
                    DropdownMenuItem(
                      value: wb.wallet.id,
                      child: Text(wb.wallet.name),
                    ),
                ],
                onChanged: (v) => setState(() => _walletId = v),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                hintText: 'Contoh: Talangan makan siang',
              ),
            ),
            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Simpan Catatan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
