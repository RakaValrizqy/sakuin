import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/constants/app_colors.dart';
import 'package:sakuin/core/constants/app_icons.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/features/category/category_providers.dart';

Future<int?> showCategoryFormSheet(
  BuildContext context, {
  Category? existing,
  String initialType = 'expense',
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        CategoryFormSheet(existing: existing, initialType: initialType),
  );
}

class CategoryFormSheet extends ConsumerStatefulWidget {
  const CategoryFormSheet({
    super.key,
    this.existing,
    this.initialType = 'expense',
  });

  final Category? existing;
  final String initialType;

  @override
  ConsumerState<CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends ConsumerState<CategoryFormSheet> {
  final _nameCtrl = TextEditingController();
  late String _type;
  late String _icon;
  late int _color;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final c = widget.existing;
    _nameCtrl.text = c?.name ?? '';
    _type = c?.type ?? widget.initialType;
    _icon = c?.icon ?? (_type == 'income' ? 'salary' : 'food');
    _color = c?.color ?? AppColors.pickerPalette.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _saving) return;
    setState(() => _saving = true);
    final id = await ref
        .read(categoryActionsProvider)
        .saveCategory(
          id: widget.existing?.id,
          name: _nameCtrl.text.trim(),
          type: _type,
          icon: _icon,
          color: _color,
        );
    if (mounted) Navigator.of(context).pop(id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEdit ? 'Edit Kategori' : 'Tambah Kategori',
              style: tt.headlineSmall,
            ),
            const SizedBox(height: 14),
            if (!isEdit) ...[
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'expense', label: Text('Pengeluaran')),
                  ButtonSegment(value: 'income', label: Text('Pemasukan')),
                ],
                selected: {_type},
                onSelectionChanged: (s) => setState(() => _type = s.first),
              ),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama kategori',
                hintText: 'Contoh: Kopi, Parkir, Freelance',
              ),
            ),
            const SizedBox(height: 14),
            Text('Warna', style: tt.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in AppColors.pickerPalette)
                  InkWell(
                    onTap: () => setState(() => _color = c),
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: _color == c
                            ? Border.all(color: cs.onSurface, width: 3)
                            : null,
                      ),
                      child: _color == c
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text('Ikon', style: tt.labelMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in AppIcons.categoryIconKeys)
                  InkWell(
                    onTap: () => setState(() => _icon = key),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _icon == key
                            ? Color(_color).withValues(alpha: 0.2)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: _icon == key
                              ? Color(_color)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        AppIcons.fromKey(key),
                        color: _icon == key
                            ? Color(_color)
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(isEdit ? 'Simpan Perubahan' : 'Simpan Kategori'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
