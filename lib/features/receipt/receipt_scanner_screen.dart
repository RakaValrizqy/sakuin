import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/receipt_scanner_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/utils/receipt_parser.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';
import 'package:sakuin/features/category/category_providers.dart';
import 'package:sakuin/features/receipt/split_bill_screen.dart';
import 'package:sakuin/features/transaction/transaction_providers.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class ReceiptScannerScreen extends ConsumerStatefulWidget {
  const ReceiptScannerScreen({
    super.key,
    this.initialImagePath,
    this.startManualSplit = false,
  });

  final String? initialImagePath;
  final bool startManualSplit;

  @override
  ConsumerState<ReceiptScannerScreen> createState() =>
      _ReceiptScannerScreenState();
}

class _ReceiptScannerScreenState extends ConsumerState<ReceiptScannerScreen> {
  final _merchantCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _serviceCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();

  String? _imagePath;
  bool _scanning = false;
  bool _hasScannedOrManual = false;
  DateTime _occurredAt = DateTime.now();
  String _engineUsed = 'mlkit_offline';
  String? _fallbackNotice;
  String _rawOcrText = '';
  List<ParsedReceiptItem> _items = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialImagePath != null &&
        widget.initialImagePath!.isNotEmpty) {
      _imagePath = widget.initialImagePath;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runScan(widget.initialImagePath!);
      });
    } else if (widget.startManualSplit) {
      _hasScannedOrManual = true;
      _merchantCtrl.text = 'Patungan';
    }
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    _taxCtrl.dispose();
    _serviceCtrl.dispose();
    _discountCtrl.dispose();
    // Hapus file cache sementara foto struk agar penyimpanan tetap bersih & ringan
    ref.read(receiptScannerServiceProvider).cleanupReceiptCache();
    super.dispose();
  }

  int get _tax => AmountParser.parse(_taxCtrl.text) ?? 0;
  int get _service => AmountParser.parse(_serviceCtrl.text) ?? 0;
  int get _discount => AmountParser.parse(_discountCtrl.text) ?? 0;
  int get _itemsSubtotal => _items.fold(0, (s, e) => s + e.totalPrice);
  int get _grandTotal =>
      (_itemsSubtotal + _tax + _service - _discount).clamp(0, 1 << 60);

  Future<void> _captureFromCamera() async {
    try {
      final path = await ref
          .read(receiptScannerServiceProvider)
          .captureReceiptPhoto();
      if (path != null && mounted) {
        await _runScan(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal membuka kamera: $e')));
      }
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final path = await ref
          .read(receiptScannerServiceProvider)
          .pickReceiptImage();
      if (path != null && mounted) {
        await _runScan(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal memilih gambar: $e')));
      }
    }
  }

  Future<void> _runScan(String path, {bool forceOffline = false}) async {
    setState(() {
      _imagePath = path;
      _scanning = true;
      _fallbackNotice = null;
    });

    try {
      final parsed = await ref
          .read(receiptScannerServiceProvider)
          .scanReceipt(path, forceOffline: forceOffline);
      if (!mounted) return;
      setState(() {
        _scanning = false;
        _hasScannedOrManual = true;
        _merchantCtrl.text = parsed.merchantName;
        _occurredAt = parsed.occurredAt ?? DateTime.now();
        _items = List<ParsedReceiptItem>.from(parsed.items);
        _taxCtrl.text = parsed.tax > 0
            ? CurrencyFormatter.format(parsed.tax, withSymbol: false)
            : '';
        _serviceCtrl.text = parsed.serviceCharge > 0
            ? CurrencyFormatter.format(parsed.serviceCharge, withSymbol: false)
            : '';
        _discountCtrl.text = parsed.discount > 0
            ? CurrencyFormatter.format(parsed.discount, withSymbol: false)
            : '';
        _engineUsed = parsed.engineUsed;
        _fallbackNotice = parsed.fallbackNotice;
        _rawOcrText = parsed.rawText;
      });
      AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _scanning = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal memindai struk: $e')));
    }
  }

  Future<void> _addOrEditItem({int? index}) async {
    final existing = index != null ? _items[index] : null;
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final priceCtrl = TextEditingController(
      text: existing != null
          ? CurrencyFormatter.format(existing.totalPrice, withSymbol: false)
          : '',
    );

    final result = await showDialog<ParsedReceiptItem>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Tambah Item Struk' : 'Edit Item'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nama item / menu',
                hintText: 'Contoh: Nasi Ayam Geprek',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [ThousandsSeparatorInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Total harga item',
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
              final name = nameCtrl.text.trim();
              final price = AmountParser.parse(priceCtrl.text) ?? 0;
              if (name.isEmpty || price <= 0) return;
              Navigator.pop(
                ctx,
                ParsedReceiptItem(
                  name: name,
                  totalPrice: price,
                  suggestedCategory: existing?.suggestedCategory,
                ),
              );
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    priceCtrl.dispose();

    if (result != null) {
      setState(() {
        if (index != null) {
          _items[index] = result;
        } else {
          _items.add(result);
        }
      });
    }
  }

  Future<void> _saveAsRegularTransaction() async {
    final wallets =
        ref.read(walletsWithBalancesProvider).valueOrNull ?? const [];
    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buat minimal 1 dompet terlebih dahulu')),
      );
      return;
    }
    if (_grandTotal <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tambahkan minimal 1 item berharga > 0')),
      );
      return;
    }

    final allPockets =
        ref.read(allActivePocketsProvider).valueOrNull ?? const [];
    final categories =
        ref.read(expenseCategoriesProvider).valueOrNull ?? const [];

    int walletId = wallets.first.wallet.id;
    int? pocketId;
    int? categoryId = _guessDefaultCategoryId(categories);
    bool saveSplitItems = _items.length > 1;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final walletPockets = allPockets
              .where((p) => p.pocket.walletId == walletId)
              .toList();
          if (pocketId != null &&
              !walletPockets.any((p) => p.pocket.id == pocketId)) {
            pocketId = null;
          }

          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Simpan ke Transaksi Biasa',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '${_merchantCtrl.text.trim().isEmpty ? "Struk Belanja" : _merchantCtrl.text.trim()} • ${CurrencyFormatter.format(_grandTotal)}',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: walletId,
                  decoration: const InputDecoration(labelText: 'Dompet / Saku'),
                  items: [
                    for (final wb in wallets)
                      DropdownMenuItem(
                        value: wb.wallet.id,
                        child: Text(wb.wallet.name),
                      ),
                  ],
                  onChanged: (v) => setModalState(() {
                    if (v != null) {
                      walletId = v;
                      pocketId = null;
                    }
                  }),
                ),
                if (walletPockets.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int?>(
                    initialValue: pocketId,
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
                    onChanged: (v) => setModalState(() => pocketId = v),
                  ),
                ],
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: categoryId,
                  decoration: const InputDecoration(labelText: 'Kategori'),
                  items: [
                    for (final c in categories)
                      DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setModalState(() => categoryId = v),
                ),
                if (_items.length > 1) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Pecah per item di riwayat transaksi'),
                    subtitle: Text(
                      'Simpan ${_items.length} komponen item (termasuk pajak/service/diskon jika ada)',
                    ),
                    value: saveSplitItems,
                    onChanged: (v) => setModalState(() => saveSplitItems = v),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.pop(ctx, true),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Simpan Pengeluaran'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (confirmed != true || !mounted) return;
    final merchant = _merchantCtrl.text.trim().isEmpty
        ? 'Struk Belanja'
        : _merchantCtrl.text.trim();
    final actions = ref.read(transactionActionsProvider);

    if (saveSplitItems && _items.length > 1) {
      final components = <SplitComponentInput>[];
      final extras = _tax + _service - _discount;
      for (var i = 0; i < _items.length; i++) {
        final item = _items[i];
        var amt = item.totalPrice;
        // Jika ada selisih pajak/service/diskon, gabungkan ke item tambahan atau distribusikan ke item terakhir
        if (i == _items.length - 1 && extras != 0 && amt + extras > 0) {
          amt += extras;
        }
        final itemCatId =
            _matchCategoryByName(categories, item.suggestedCategory) ??
            categoryId;
        components.add(
          SplitComponentInput(
            itemName: item.name,
            amount: amt,
            categoryId: itemCatId,
            pocketId: pocketId,
            note: 'Struk $merchant',
          ),
        );
      }
      await actions.saveSplitTransactions(
        type: 'expense',
        walletId: walletId,
        occurredAt: _occurredAt,
        components: components,
      );
    } else {
      final itemSummary = _items.map((e) => e.name).take(3).join(', ');
      await actions.saveTransaction(
        type: 'expense',
        amount: _grandTotal,
        walletId: walletId,
        pocketId: pocketId,
        categoryId: categoryId,
        itemName: merchant,
        note: itemSummary.isNotEmpty ? 'Struk: $itemSummary' : 'Scan struk',
        occurredAt: _occurredAt,
      );
    }

    if (!mounted) return;
    AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Pengeluaran $merchant (${CurrencyFormatter.format(_grandTotal)}) tersimpan',
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  int? _guessDefaultCategoryId(List<Category> categories) {
    for (final item in _items) {
      final matched = _matchCategoryByName(categories, item.suggestedCategory);
      if (matched != null) return matched;
    }
    final food = _matchCategoryByName(categories, 'Makanan & Minuman');
    if (food != null) return food;
    return categories.isNotEmpty ? categories.first.id : null;
  }

  int? _matchCategoryByName(List<Category> categories, String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final target = name.trim().toLowerCase();
    for (final c in categories) {
      if (c.name.toLowerCase() == target) return c.id;
    }
    return null;
  }

  Future<void> _openSplitBill() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tambahkan minimal 1 item untuk dibagi di Split Bill'),
        ),
      );
      return;
    }
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SplitBillScreen(
          merchantName: _merchantCtrl.text.trim().isEmpty
              ? 'Struk Belanja'
              : _merchantCtrl.text.trim(),
          occurredAt: _occurredAt,
          initialItems: List<ParsedReceiptItem>.from(_items),
          tax: _tax,
          serviceCharge: _service,
          discount: _discount,
        ),
      ),
    );
    if (done == true && mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasGemini = ref.watch(hasGeminiApiKeyProvider).valueOrNull ?? false;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Struk & Split Bill'),
        actions: [
          if (_hasScannedOrManual && _rawOcrText.isNotEmpty)
            IconButton(
              tooltip: 'Lihat teks mentah OCR',
              icon: const Icon(Icons.article_outlined),
              onPressed: () {
                showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Teks Hasil OCR'),
                    content: SingleChildScrollView(
                      child: SelectableText(_rawOcrText),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('Tutup'),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
      body: _scanning
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      hasGemini
                          ? 'Memindai struk dengan AI Vision (otomatis fallback offline)...'
                          : 'Membaca teks struk secara offline (ML Kit)...',
                      textAlign: TextAlign.center,
                      style: tt.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Mendeteksi nama toko, daftar item, pajak, diskon, dan total.',
                      textAlign: TextAlign.center,
                      style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          : !_hasScannedOrManual
          ? _buildLandingView(context, hasGemini)
          : _buildReviewView(context, hasGemini),
      bottomNavigationBar: _hasScannedOrManual && !_scanning
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total Struk', style: tt.labelLarge),
                        Text(
                          CurrencyFormatter.format(_grandTotal),
                          style: tt.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saveAsRegularTransaction,
                            icon: const Icon(Icons.save_alt_rounded, size: 18),
                            label: const Text('Transaksi Biasa'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _openSplitBill,
                            icon: const Icon(Icons.groups_rounded, size: 18),
                            label: const Text('Split Bill'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildLandingView(BuildContext context, bool hasGemini) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Card(
          color: cs.primaryContainer.withValues(alpha: 0.35),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.document_scanner_rounded,
                      size: 28,
                      color: cs.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Scan Struk Hybrid & Split Bill',
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  hasGemini
                      ? 'Mode Aktif: AI Vision Gemini (otomatis fallback ke OCR Offline ML Kit jika tidak ada internet).'
                      : 'Mode Aktif: OCR Lokal 100% Offline (Google ML Kit). Opsional: tambahkan API Key Gemini gratis di Pengaturan untuk deteksi struk panjang yang lebih akurat.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _captureFromCamera,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.camera_alt_rounded),
          label: const Text('Foto Struk dengan Kamera'),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: _pickFromGallery,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          icon: const Icon(Icons.photo_library_outlined),
          label: const Text('Pilih Foto / Screenshot dari Galeri'),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () {
            setState(() {
              _hasScannedOrManual = true;
              if (_merchantCtrl.text.isEmpty) {
                _merchantCtrl.text = 'Patungan';
              }
            });
          },
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 15),
          ),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('Input Item Manual (Langsung Split Bill)'),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.share_rounded, size: 20, color: cs.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tips Cepat: Kamu juga bisa langsung menekan Bagikan (Share) pada foto struk atau screenshot di Galeri / WhatsApp lalu pilih Sakuin!',
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReviewView(BuildContext context, bool hasGemini) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // Preview gambar & engine badge
        if (_imagePath != null && File(_imagePath!).existsSync()) ...[
          Card(
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.file(
                      File(_imagePath!),
                      width: 64,
                      height: 82,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: _engineUsed == 'gemini'
                                ? cs.primaryContainer
                                : cs.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            _engineUsed == 'gemini'
                                ? 'AI Vision (Gemini)'
                                : 'OCR Offline (ML Kit)',
                            style: tt.labelSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: _captureFromCamera,
                              icon: const Icon(
                                Icons.camera_alt_outlined,
                                size: 16,
                              ),
                              label: const Text('Foto Ulang'),
                            ),
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                              ),
                              onPressed: _pickFromGallery,
                              icon: const Icon(Icons.photo_outlined, size: 16),
                              label: const Text('Galeri'),
                            ),
                            if (hasGemini)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                ),
                                onPressed: () => _runScan(
                                  _imagePath!,
                                  forceOffline: _engineUsed == 'gemini',
                                ),
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  size: 16,
                                ),
                                label: Text(
                                  _engineUsed == 'gemini'
                                      ? 'Coba Offline'
                                      : 'Coba AI Vision',
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        if (_fallbackNotice != null) ...[
          Card(
            color: cs.tertiaryContainer.withValues(alpha: 0.45),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: cs.tertiary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_fallbackNotice!, style: tt.bodySmall)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // Info Toko & Tanggal
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextField(
                  controller: _merchantCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: 'Nama toko / resto / acara',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _occurredAt,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setState(() => _occurredAt = picked);
                    }
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Tanggal transaksi',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                    child: Text(AppDateUtils.formatShortDate(_occurredAt)),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // Daftar Item Terdeteksi
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Item Belanja (${_items.length})', style: tt.titleMedium),
            TextButton.icon(
              onPressed: () => _addOrEditItem(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah Item'),
            ),
          ],
        ),
        if (_items.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text(
                  'Belum ada item. Ketuk "+ Tambah Item" untuk memasukkan item belanja.',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < _items.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    title: Text(_items[i].name),
                    subtitle: _items[i].quantity > 1
                        ? Text('Qty ${_items[i].quantity}')
                        : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          CurrencyFormatter.format(_items[i].totalPrice),
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Hapus item',
                          icon: const Icon(
                            Icons.delete_outline_rounded,
                            size: 20,
                          ),
                          onPressed: () => setState(() => _items.removeAt(i)),
                        ),
                      ],
                    ),
                    onTap: () => _addOrEditItem(index: i),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 14),

        // Pajak, Service, Diskon
        Text('Pajak, Service & Diskon (Opsional)', style: tt.titleMedium),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                TextField(
                  controller: _taxCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Pajak (PPN / PB1)',
                    prefixText: 'Rp ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _serviceCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Service / Biaya Layanan / Ongkir',
                    prefixText: 'Rp ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _discountCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [ThousandsSeparatorInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Diskon / Promo / Voucher',
                    prefixText: '- Rp ',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
