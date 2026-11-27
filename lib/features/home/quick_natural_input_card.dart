import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/db_provider.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/utils/quick_input_parser.dart';
import 'package:sakuin/features/transaction/transaction_form_sheet.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

/// Kartu input cepat 1 baris di Beranda (100% offline).
/// Contoh: "kopi susu 18rb @kopi kenangan gopay harian"
class QuickNaturalInputCard extends ConsumerStatefulWidget {
  const QuickNaturalInputCard({super.key});

  @override
  ConsumerState<QuickNaturalInputCard> createState() =>
      _QuickNaturalInputCardState();
}

class _QuickNaturalInputCardState extends ConsumerState<QuickNaturalInputCard> {
  final _ctrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _quickSave(QuickParsedTransaction parsed) async {
    if (!parsed.canQuickSave || _saving) return;
    setState(() => _saving = true);
    try {
      final db = ref.read(appDatabaseProvider);
      final haptics = ref.read(settingsProvider).hapticsEnabled;
      final actions = ref.read(transactionActionsProvider);

      int? categoryId = parsed.categoryId;
      if (categoryId == null) {
        final cats = await db.getCategoriesByRecentUsage(parsed.type);
        if (cats.isNotEmpty) categoryId = cats.first.id;
      }

      final id = await actions.saveTransaction(
        type: parsed.type,
        amount: parsed.amount,
        walletId: parsed.walletId!,
        categoryId: categoryId,
        pocketId: parsed.pocketId,
        itemName: parsed.itemName,
        merchantName: parsed.merchantName,
        note: parsed.note,
        occurredAt: DateTime.now(),
      );
      final savedTx = await (db.select(
        db.transactions,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      AppHaptics.medium(haptics);
      _ctrl.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        final label =
            parsed.itemName ?? parsed.merchantName ?? 'Transaksi Cepat';
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                'Tersimpan: $label (${CurrencyFormatter.format(parsed.amount)})',
              ),
              action: savedTx == null
                  ? null
                  : SnackBarAction(
                      label: 'Urungkan',
                      onPressed: () => actions.deleteTransaction(savedTx),
                    ),
            ),
          );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openInForm(QuickParsedTransaction parsed) async {
    FocusScope.of(context).unfocus();
    final saved = await showTransactionFormSheet(
      context,
      prefillParsed: parsed,
    );
    if (saved == true && mounted) {
      _ctrl.clear();
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final pockets = ref.watch(allActivePocketsProvider).valueOrNull ?? const [];
    final itemMemories = ref.watch(quickItemsProvider).valueOrNull ?? const [];
    final merchantMemories =
        ref.watch(merchantMemoryListProvider).valueOrNull ?? const [];
    final lastWalletId = ref.watch(
      settingsProvider.select((s) => s.lastWalletId),
    );

    final raw = _ctrl.text.trim();
    final parsed = raw.isEmpty
        ? null
        : QuickInputParser.parse(
            rawInput: raw,
            wallets: wallets,
            pockets: pockets,
            itemMemories: itemMemories,
            merchantMemories: merchantMemories,
            defaultWalletId: lastWalletId,
          );

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (parsed != null && parsed.canQuickSave) {
                  _quickSave(parsed);
                }
              },
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                filled: false,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                prefixIcon: Icon(
                  Icons.bolt_rounded,
                  color: cs.primary,
                  size: 22,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
                hintText: 'Catat cepat: "kopi 18rb gopay harian"',
                hintStyle: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                suffixIcon: raw.isNotEmpty
                    ? IconButton(
                        tooltip: 'Bersihkan',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () {
                          _ctrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
              ),
            ),
            if (parsed != null) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _PreviewPill(
                    icon: parsed.type == 'income'
                        ? Icons.south_west_rounded
                        : Icons.north_east_rounded,
                    color: parsed.type == 'income'
                        ? AppColors.income(context)
                        : AppColors.expense(context),
                    label: parsed.amount > 0
                        ? CurrencyFormatter.format(parsed.amount)
                        : 'Nominal belum terdeteksi',
                  ),
                  if (parsed.itemName != null)
                    _PreviewPill(
                      icon: Icons.label_outline_rounded,
                      color: cs.primary,
                      label: parsed.itemName!,
                    ),
                  if (parsed.merchantName != null)
                    _PreviewPill(
                      icon: Icons.storefront_rounded,
                      color: cs.secondary,
                      label: parsed.merchantName!,
                    ),
                  if (parsed.walletName != null)
                    _PreviewPill(
                      icon: Icons.account_balance_wallet_outlined,
                      color: cs.tertiary,
                      label: parsed.pocketName != null
                          ? '${parsed.walletName} (${parsed.pocketName})'
                          : parsed.walletName!,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _openInForm(parsed),
                      icon: const Icon(Icons.tune_rounded, size: 16),
                      label: const Text('Edit Form'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: parsed.canQuickSave && !_saving
                          ? () => _quickSave(parsed)
                          : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Simpan'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({
    required this.icon,
    required this.color,
    required this.label,
  });

  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: color, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
