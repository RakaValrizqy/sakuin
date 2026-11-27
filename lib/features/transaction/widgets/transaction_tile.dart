import 'package:flutter/material.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/core/widgets/category_icon.dart';

class TransactionTile extends StatelessWidget {
  const TransactionTile({
    super.key,
    required this.detail,
    this.onTap,
    this.onLongPress,
    this.onDelete,
    this.onDuplicate,
    this.onPinQuickItem,
    this.isSelected = false,
    this.selectionMode = false,
    this.enableSwipe = true,
  });

  final TransactionDetail detail;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDelete;
  final VoidCallback? onDuplicate;
  final VoidCallback? onPinQuickItem;
  final bool isSelected;
  final bool selectionMode;
  final bool enableSwipe;

  @override
  Widget build(BuildContext context) {
    final tx = detail.transaction;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final time = DateTime.fromMillisecondsSinceEpoch(tx.occurredAt).toLocal();

    final isTransfer = tx.type == 'transfer';
    final fromLabel = detail.pocketName != null
        ? '${detail.wallet.name} (${detail.pocketName})'
        : detail.wallet.name;
    final toLabel = detail.toPocketName != null
        ? '${detail.toWallet?.name ?? "-"} (${detail.toPocketName})'
        : (detail.toWallet?.name ?? '-');
    final title = isTransfer
        ? '$fromLabel → $toLabel'
        : (tx.itemName != null && tx.itemName!.trim().isNotEmpty
              ? tx.itemName!.trim()
              : (detail.category?.name ?? 'Transaksi'));

    final subtitleParts = <String>[];
    if (!isTransfer &&
        tx.merchantName != null &&
        tx.merchantName!.trim().isNotEmpty &&
        tx.merchantName!.trim().toLowerCase() != title.toLowerCase()) {
      subtitleParts.add(tx.merchantName!.trim());
    }
    if (!isTransfer && detail.category != null && tx.itemName != null) {
      subtitleParts.add(detail.category!.name);
    }
    if (!isTransfer) {
      subtitleParts.add(fromLabel);
    }
    if (isTransfer && tx.fee > 0) {
      subtitleParts.add('Admin ${CurrencyFormatter.format(tx.fee)}');
    }
    if (tx.splitGroupId != null) {
      subtitleParts.add('Pecahan');
    }
    if (tx.note.isNotEmpty) {
      subtitleParts.add(tx.note);
    }
    subtitleParts.add(AppDateUtils.formatTime(time));

    final tileContent = Material(
      color: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.45)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              if (selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: isSelected ? cs.primary : cs.onSurfaceVariant,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: CategoryIconBadge(
                    iconKey: isTransfer
                        ? 'admin_fee'
                        : (detail.category?.icon ?? 'other'),
                    colorValue: isTransfer
                        ? AppColors.transfer(context).toARGB32()
                        : (detail.category?.color ?? 0xFF64748B),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AmountText(
                    amount: tx.amount,
                    type: tx.type,
                    signed: !isTransfer,
                    style: tt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (onPinQuickItem != null && !isTransfer && !selectionMode)
                    const SizedBox(height: 2),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (!enableSwipe || selectionMode) return tileContent;

    return Dismissible(
      key: ValueKey('tx_dismiss_${tx.id}'),
      background: Container(
        color: AppColors.transfer(context),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          children: [
            Icon(Icons.copy_rounded, color: Colors.white),
            SizedBox(width: 8),
            Text(
              'Duplikat',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
      secondaryBackground: Container(
        color: AppColors.expense(context),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              'Hapus',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(width: 8),
            Icon(Icons.delete_outline_rounded, color: Colors.white),
          ],
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onDuplicate?.call();
          return false;
        }
        if (direction == DismissDirection.endToStart) {
          onDelete?.call();
          return false;
        }
        return false;
      },
      child: tileContent,
    );
  }
}
