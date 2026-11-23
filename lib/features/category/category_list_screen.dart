import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/widgets/category_icon.dart';
import 'package:sakuin/features/category/category_form_sheet.dart';
import 'package:sakuin/features/category/category_providers.dart';

class CategoryListScreen extends ConsumerStatefulWidget {
  const CategoryListScreen({super.key});

  @override
  ConsumerState<CategoryListScreen> createState() => _CategoryListScreenState();
}

class _CategoryListScreenState extends ConsumerState<CategoryListScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allAsync = ref.watch(allCategoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kategori'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Pengeluaran'),
            Tab(text: 'Pemasukan'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final type = _tabController.index == 0 ? 'expense' : 'income';
          showCategoryFormSheet(context, initialType: type);
        },
        icon: const Icon(Icons.add_rounded),
        label: const Text('Kategori'),
      ),
      body: allAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Gagal memuat kategori: $e')),
        data: (all) {
          final expenses = all.where((c) => c.type == 'expense').toList();
          final incomes = all.where((c) => c.type == 'income').toList();
          return TabBarView(
            controller: _tabController,
            children: [
              _CategoryTab(items: expenses),
              _CategoryTab(items: incomes),
            ],
          );
        },
      ),
    );
  }
}

class _CategoryTab extends ConsumerWidget {
  const _CategoryTab({required this.items});

  final List<Category> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (ctx, idx) {
        final cat = items[idx];
        return Card(
          child: ListTile(
            leading: CategoryIconBadge(
              iconKey: cat.icon,
              colorValue: cat.color,
            ),
            title: Text(
              cat.name,
              style: TextStyle(
                decoration: cat.isArchived ? TextDecoration.lineThrough : null,
                color: cat.isArchived ? cs.onSurfaceVariant : null,
              ),
            ),
            subtitle: cat.isArchived ? const Text('Diarsipkan') : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      showCategoryFormSheet(context, existing: cat),
                ),
                IconButton(
                  tooltip: cat.isArchived ? 'Aktifkan' : 'Arsipkan',
                  icon: Icon(
                    cat.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  onPressed: () => ref
                      .read(categoryActionsProvider)
                      .setArchived(cat.id, !cat.isArchived),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
