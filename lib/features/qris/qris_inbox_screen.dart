import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/core/db/app_database.dart';
import 'package:sakuin/core/services/qris_sync_service.dart';
import 'package:sakuin/core/services/settings_service.dart';
import 'package:sakuin/core/utils/date_utils.dart';
import 'package:sakuin/core/utils/haptics.dart';
import 'package:sakuin/core/widgets/amount_text.dart';
import 'package:sakuin/features/category/category_providers.dart';
import 'package:sakuin/features/transaction/split_transaction_sheet.dart';
import 'package:sakuin/features/wallet/wallet_providers.dart';

class QrisInboxScreen extends ConsumerStatefulWidget {
  const QrisInboxScreen({super.key});

  @override
  ConsumerState<QrisInboxScreen> createState() => _QrisInboxScreenState();
}

class _QrisInboxScreenState extends ConsumerState<QrisInboxScreen> {
  final _emailCtrl = TextEditingController();
  final _appPassCtrl = TextEditingController();

  bool _loadingConfig = true;
  bool _connected = false;
  bool _autoSyncOnOpen = true;
  bool _autoSaveWithoutReview = false;
  int _lookbackDays = 14;
  int? _defaultWalletId;
  int? _ignoreOnOrBeforeDayKey;
  bool _obscurePass = true;
  bool _testingOrSaving = false;
  bool _syncing = false;
  bool _showSetupForm = false;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _appPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    final cfg = await ref.read(qrisSyncServiceProvider).loadConfig();
    if (!mounted) return;
    setState(() {
      _emailCtrl.text = cfg.email;
      _appPassCtrl.text = cfg.appPassword;
      _connected = cfg.isConfigured;
      _autoSyncOnOpen = cfg.autoSyncOnOpen;
      _autoSaveWithoutReview = cfg.autoSaveWithoutReview;
      _lookbackDays = cfg.lookbackDays;
      _defaultWalletId = cfg.defaultWalletId;
      _ignoreOnOrBeforeDayKey = cfg.ignoreOnOrBeforeDayKey;
      _showSetupForm = !cfg.isConfigured;
      _loadingConfig = false;
    });
  }

  Future<void> _connectAndTest() async {
    final email = _emailCtrl.text.trim();
    final pass = _appPassCtrl.text.replaceAll(' ', '').trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan alamat email Gmail yang valid')),
      );
      return;
    }
    if (pass.length < 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Masukkan 16 huruf App Password Google (bukan password utama)',
          ),
        ),
      );
      return;
    }

    setState(() => _testingOrSaving = true);
    final svc = ref.read(qrisSyncServiceProvider);
    try {
      await svc.testConnection(email, pass);
      await svc.saveConfig(
        GmailQrisConfig(
          email: email,
          appPassword: pass,
          enabled: true,
          autoSyncOnOpen: _autoSyncOnOpen,
          autoSaveWithoutReview: _autoSaveWithoutReview,
          lookbackDays: _lookbackDays,
          defaultWalletId: _defaultWalletId,
          ignoreOnOrBeforeDayKey: _ignoreOnOrBeforeDayKey,
        ),
      );
      if (!mounted) return;
      setState(() {
        _connected = true;
        _showSetupForm = false;
        _testingOrSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gmail terhubung! Mulai menyinkronkan email QRIS...'),
        ),
      );
      await _syncNow();
    } catch (e) {
      if (!mounted) return;
      setState(() => _testingOrSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _savePreferencesOnly() async {
    await ref
        .read(qrisSyncServiceProvider)
        .saveConfig(
          GmailQrisConfig(
            email: _emailCtrl.text.trim(),
            appPassword: _appPassCtrl.text.trim(),
            enabled: _connected,
            autoSyncOnOpen: _autoSyncOnOpen,
            autoSaveWithoutReview: _autoSaveWithoutReview,
            lookbackDays: _lookbackDays,
            defaultWalletId: _defaultWalletId,
            ignoreOnOrBeforeDayKey: _ignoreOnOrBeforeDayKey,
          ),
        );
  }

  Future<void> _pickIgnoreCutoffDate() async {
    final now = DateTime.now();
    final initial = _ignoreOnOrBeforeDayKey != null
        ? AppDateUtils.fromDayKey(_ignoreOnOrBeforeDayKey!)
        : now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now) ? now : initial,
      firstDate: DateTime(2020),
      lastDate: now,
      helpText: 'Abaikan transaksi pada & sebelum tanggal ini',
    );
    if (picked == null || !mounted) return;

    final prevCutoff = _ignoreOnOrBeforeDayKey;
    final dayKey = AppDateUtils.toDayKey(picked);
    setState(() => _ignoreOnOrBeforeDayKey = dayKey);
    await _savePreferencesOnly();

    if (!mounted) return;
    final dateLabel = AppDateUtils.formatShortDate(picked);

    // Jika batas tanggal dimundurkan (mis. dari 26 Nov -> 25 Nov), pulihkan draft yang
    // sempat ter-dismiss di rentang setelah batas baru lalu sinkron ulang otomatis.
    if (prevCutoff != null && dayKey < prevCutoff) {
      final restored = await ref
          .read(qrisSyncServiceProvider)
          .restoreDismissedDraftsAfter(dayKey);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              restored > 0
                  ? 'Batas dimundurkan ke $dateLabel • $restored transaksi dipulihkan ke antrean'
                  : 'Batas dimundurkan ke $dateLabel • menyinkronkan ulang email...',
            ),
          ),
        );
      }
      if (_connected) {
        await _syncNow();
      }
      return;
    }

    final pending = ref.read(pendingQrisDraftsProvider).valueOrNull ?? const [];
    final affectedCount = pending.where((d) {
      final dt = DateTime.fromMillisecondsSinceEpoch(d.occurredAt).toLocal();
      return QrisSyncService.shouldIgnoreTransactionDate(dt, dayKey);
    }).length;

    if (affectedCount > 0) {
      final cleanNow = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bersihkan antrean lama?'),
          content: Text(
            'Ada $affectedCount transaksi di antrean review dari tanggal $dateLabel dan sebelumnya. '
            'Hapus dari antrean sekarang?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Biarkan'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Bersihkan'),
            ),
          ],
        ),
      );
      if (cleanNow == true) {
        final removed = await ref
            .read(qrisSyncServiceProvider)
            .dismissPendingDraftsOnOrBefore(dayKey);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Batas diatur ($dateLabel) & $removed antrean lama dibersihkan',
              ),
            ),
          );
        }
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Transaksi pada $dateLabel dan sebelumnya tidak akan diperiksa',
          ),
        ),
      );
    }
  }

  Future<void> _clearIgnoreCutoffDate() async {
    setState(() => _ignoreOnOrBeforeDayKey = null);
    await _savePreferencesOnly();
    final restored = await ref
        .read(qrisSyncServiceProvider)
        .restoreDismissedDraftsAfter(null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            restored > 0
                ? 'Batas tanggal dihapus & $restored transaksi dipulihkan'
                : 'Batas tanggal sinkron dihapus',
          ),
        ),
      );
    }
    if (_connected) {
      await _syncNow();
    }
  }

  Future<void> _restoreDismissedNow() async {
    final restored = await ref
        .read(qrisSyncServiceProvider)
        .restoreDismissedDraftsAfter(_ignoreOnOrBeforeDayKey);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored > 0
              ? '$restored transaksi QRIS dipulihkan ke antrean review'
              : 'Tidak ada transaksi diabaikan yang cocok dengan batas tanggal saat ini',
        ),
      ),
    );
    if (_connected) {
      await _syncNow();
    }
  }

  Future<void> _syncNow() async {
    if (_syncing || !_connected) return;
    setState(() => _syncing = true);
    final res = await ref.read(qrisSyncServiceProvider).syncNow();
    if (!mounted) return;
    setState(() => _syncing = false);

    if (res.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal sinkron Gmail: ${res.error}')),
      );
      return;
    }
    final totalFound = res.newDrafts + res.autoSaved;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          totalFound == 0
              ? 'Tidak ada email QRIS baru ditemukan'
              : (res.autoSaved > 0
                    ? '${res.autoSaved} transaksi QRIS otomatis tersimpan'
                    : '${res.newDrafts} transaksi QRIS baru masuk antrean review'),
        ),
      ),
    );
  }

  Future<void> _confirmSingleDialog(
    ImportedQrisDraft draft,
    List<WalletWithBalance> wallets,
    List<PocketWithBalance> allPockets,
    List<Category> expenseCategories,
  ) async {
    if (wallets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buat minimal 1 dompet terlebih dahulu')),
      );
      return;
    }

    int walletId =
        (draft.suggestedWalletId != null &&
            wallets.any((w) => w.wallet.id == draft.suggestedWalletId))
        ? draft.suggestedWalletId!
        : wallets.first.wallet.id;
    int? pocketId;
    int? categoryId = expenseCategories.isNotEmpty
        ? expenseCategories.first.id
        : null;

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
                  'Simpan Pengeluaran QRIS',
                  style: Theme.of(ctx).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  '${draft.merchantName} • ${draft.bankName}',
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
                const SizedBox(height: 4),
                AmountText(
                  amount: draft.amount,
                  type: 'expense',
                  style: Theme.of(ctx).textTheme.headlineSmall,
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
                    for (final c in expenseCategories)
                      DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => setModalState(() => categoryId = v),
                ),
                const SizedBox(height: 18),
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

    if (confirmed == true) {
      await ref
          .read(qrisSyncServiceProvider)
          .confirmDraftAsSingle(
            draft,
            walletId: walletId,
            categoryId: categoryId,
            pocketId: pocketId,
          );
      AppHaptics.medium(ref.read(settingsProvider).hapticsEnabled);
    }
  }

  Future<void> _splitDraft(
    ImportedQrisDraft draft,
    List<WalletWithBalance> wallets,
  ) async {
    if (wallets.isEmpty) return;
    final walletId =
        (draft.suggestedWalletId != null &&
            wallets.any((w) => w.wallet.id == draft.suggestedWalletId))
        ? draft.suggestedWalletId!
        : wallets.first.wallet.id;

    final saved = await showSplitNewTransactionSheet(
      context,
      totalAmount: draft.amount,
      walletId: walletId,
      occurredAt: DateTime.fromMillisecondsSinceEpoch(draft.occurredAt)
          .toLocal(),
      merchantName: draft.merchantName,
      externalRef: draft.emailUid,
    );
    if (saved == true) {
      await ref.read(qrisSyncServiceProvider).markDraftConfirmed(draft.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draftsAsync = ref.watch(pendingQrisDraftsProvider);
    final wallets =
        ref.watch(walletsWithBalancesProvider).valueOrNull ?? const [];
    final allPockets =
        ref.watch(allActivePocketsProvider).valueOrNull ?? const [];
    final expenseCats =
        ref.watch(expenseCategoriesProvider).valueOrNull ?? const [];

    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Auto QRIS (Gmail)'),
        actions: [
          if (_connected)
            IconButton(
              tooltip: 'Pulihkan antrean yang sempat dibersihkan/diabaikan',
              icon: const Icon(Icons.restore_rounded),
              onPressed: _syncing ? null : _restoreDismissedNow,
            ),
          if (_connected)
            IconButton(
              tooltip: 'Sinkron email sekarang',
              icon: _syncing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync_rounded),
              onPressed: _syncing ? null : _syncNow,
            ),
          if (_connected)
            IconButton(
              tooltip: 'Pengaturan Gmail',
              icon: Icon(
                _showSetupForm
                    ? Icons.expand_less_rounded
                    : Icons.settings_outlined,
              ),
              onPressed: () => setState(() => _showSetupForm = !_showSetupForm),
            ),
        ],
      ),
      body: _loadingConfig
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _syncNow,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                children: [
                  // Status Koneksi Gmail
                  Card(
                    color: _connected
                        ? cs.primaryContainer.withValues(alpha: 0.35)
                        : null,
                    child: ListTile(
                      leading: Icon(
                        _connected
                            ? Icons.mark_email_read_rounded
                            : Icons.mail_outline_rounded,
                        color: _connected ? cs.primary : cs.onSurfaceVariant,
                      ),
                      title: Text(
                        _connected
                            ? 'Gmail Terhubung'
                            : 'Hubungkan Gmail (IMAP + App Password)',
                      ),
                      subtitle: Text(
                        _connected
                            ? '${_emailCtrl.text} • Mode read-only (tidak menandai email terbaca)'
                            : 'Otomatis mendeteksi email transaksi QRIS Mandiri, BCA, BRI, GoPay, DANA, dll.',
                      ),
                      trailing: _connected
                          ? FilledButton.tonal(
                              onPressed: _syncing ? null : _syncNow,
                              child: const Text('Sinkron'),
                            )
                          : null,
                    ),
                  ),

                  // Batas Tanggal Sinkron Email (selalu mudah diakses)
                  const SizedBox(height: 10),
                  Card(
                    child: ListTile(
                      leading: Icon(
                        Icons.event_busy_rounded,
                        color: _ignoreOnOrBeforeDayKey != null
                            ? cs.primary
                            : cs.onSurfaceVariant,
                      ),
                      title: const Text('Batas Tanggal Sinkron'),
                      subtitle: Text(
                        _ignoreOnOrBeforeDayKey != null
                            ? 'Abaikan transaksi pada ${AppDateUtils.formatShortDate(AppDateUtils.fromDayKey(_ignoreOnOrBeforeDayKey!))} & sebelumnya (hanya setelahnya yang diperiksa)'
                            : 'Belum diatur — semua email dalam rentang $_lookbackDays hari terakhir diperiksa',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_ignoreOnOrBeforeDayKey != null)
                            IconButton(
                              tooltip: 'Hapus batas tanggal',
                              icon: const Icon(Icons.close_rounded, size: 20),
                              onPressed: _clearIgnoreCutoffDate,
                            ),
                          TextButton(
                            onPressed: _pickIgnoreCutoffDate,
                            child: Text(
                              _ignoreOnOrBeforeDayKey != null
                                  ? 'Ubah'
                                  : 'Pilih',
                            ),
                          ),
                        ],
                      ),
                      onTap: _pickIgnoreCutoffDate,
                    ),
                  ),

                  // Form Setup & Pengaturan Gmail
                  if (_showSetupForm) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cara Buat App Password Google (1 Menit)',
                              style: tt.titleSmall?.copyWith(color: cs.primary),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '1. Aktifkan Verifikasi 2 Langkah di myaccount.google.com/security\n'
                              '2. Cari menu "Sandi Aplikasi / App Passwords" lalu buat nama "Sakuin"\n'
                              '3. Salin 16 huruf sandi yang muncul dan tempel di bawah (disimpan terenkripsi lokal di HP-mu)',
                              style: tt.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 14),
                            TextField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: 'Alamat Email Gmail',
                                hintText: 'nama@gmail.com',
                                prefixIcon: Icon(Icons.alternate_email_rounded),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _appPassCtrl,
                              obscureText: _obscurePass,
                              decoration: InputDecoration(
                                labelText: 'App Password (16 huruf)',
                                hintText: 'xxxx xxxx xxxx xxxx',
                                prefixIcon: const Icon(Icons.key_rounded),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePass
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                  onPressed: () => setState(
                                    () => _obscurePass = !_obscurePass,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (wallets.isNotEmpty) ...[
                              DropdownButtonFormField<int?>(
                                initialValue:
                                    wallets.any(
                                      (w) => w.wallet.id == _defaultWalletId,
                                    )
                                    ? _defaultWalletId
                                    : null,
                                decoration: const InputDecoration(
                                  labelText: 'Dompet cadangan (jika nama bank tak cocok)',
                                ),
                                items: [
                                  const DropdownMenuItem<int?>(
                                    value: null,
                                    child: Text('Otomatis (dompet pertama)'),
                                  ),
                                  for (final wb in wallets)
                                    DropdownMenuItem<int?>(
                                      value: wb.wallet.id,
                                      child: Text(wb.wallet.name),
                                    ),
                                ],
                                onChanged: (v) {
                                  setState(() => _defaultWalletId = v);
                                  if (_connected) _savePreferencesOnly();
                                },
                              ),
                              const SizedBox(height: 10),
                            ],
                            DropdownButtonFormField<int>(
                              initialValue: _lookbackDays,
                              decoration: const InputDecoration(
                                labelText: 'Rentang scan email',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 7,
                                  child: Text('7 hari terakhir'),
                                ),
                                DropdownMenuItem(
                                  value: 14,
                                  child: Text('14 hari terakhir'),
                                ),
                                DropdownMenuItem(
                                  value: 30,
                                  child: Text('30 hari terakhir'),
                                ),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _lookbackDays = v);
                                  if (_connected) _savePreferencesOnly();
                                }
                              },
                            ),
                            const SizedBox(height: 6),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Sinkron otomatis saat aplikasi dibuka',
                              ),
                              value: _autoSyncOnOpen,
                              onChanged: (v) {
                                setState(() => _autoSyncOnOpen = v);
                                if (_connected) _savePreferencesOnly();
                              },
                            ),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text(
                                'Langsung simpan tanpa antrean review',
                              ),
                              subtitle: const Text(
                                'Jika mati (disarankan), transaksi QRIS masuk antrean Review agar bisa langsung dipecah itemnya',
                              ),
                              value: _autoSaveWithoutReview,
                              onChanged: (v) {
                                setState(() => _autoSaveWithoutReview = v);
                                if (_connected) _savePreferencesOnly();
                              },
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                if (_connected) ...[
                                  OutlinedButton(
                                    onPressed: () async {
                                      await ref
                                          .read(qrisSyncServiceProvider)
                                          .disconnect();
                                      if (!mounted) return;
                                      setState(() {
                                        _connected = false;
                                        _appPassCtrl.clear();
                                      });
                                    },
                                    child: const Text('Putuskan'),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: _testingOrSaving
                                        ? null
                                        : _connectAndTest,
                                    icon: _testingOrSaving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.link_rounded),
                                    label: Text(
                                      _connected
                                          ? 'Simpan & Tes Koneksi'
                                          : 'Tes & Hubungkan Gmail',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  // Daftar Antrean Review QRIS
                  const SizedBox(height: 18),
                  draftsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Gagal memuat antrean: $e'),
                    data: (drafts) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Antrean Review QRIS (${drafts.length})',
                            style: tt.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          if (drafts.isEmpty)
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Center(
                                  child: Text(
                                    _connected
                                        ? 'Semua transaksi QRIS sudah diproses. Tarik ke bawah atau ketuk ikon Sinkron untuk mengecek email terbaru.'
                                        : 'Hubungkan Gmail di atas agar email transaksi QRIS otomatis muncul di sini.',
                                    style: tt.bodyMedium?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            )
                          else
                            for (final draft in drafts)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 3,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: cs.primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                              child: Text(
                                                draft.bankName,
                                                style: tt.labelSmall?.copyWith(
                                                  color: cs.onPrimaryContainer,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                AppDateUtils.formatDayDate(
                                                  DateTime.fromMillisecondsSinceEpoch(
                                                    draft.occurredAt,
                                                  ).toLocal(),
                                                ),
                                                style: tt.bodySmall?.copyWith(
                                                  color: cs.onSurfaceVariant,
                                                ),
                                              ),
                                            ),
                                            AmountText(
                                              amount: draft.amount,
                                              type: 'expense',
                                              style: tt.titleMedium?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          draft.merchantName,
                                          style: tt.titleMedium,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          draft.subject,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: tt.bodySmall?.copyWith(
                                            color: cs.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            TextButton(
                                              onPressed: () => ref
                                                  .read(qrisSyncServiceProvider)
                                                  .dismissDraft(draft.id),
                                              child: const Text('Abaikan'),
                                            ),
                                            const Spacer(),
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  _splitDraft(draft, wallets),
                                              icon: const Icon(
                                                Icons.call_split_rounded,
                                                size: 18,
                                              ),
                                              label: const Text('Pecah Item'),
                                            ),
                                            const SizedBox(width: 8),
                                            FilledButton(
                                              onPressed: () =>
                                                  _confirmSingleDialog(
                                                    draft,
                                                    wallets,
                                                    allPockets,
                                                    expenseCats,
                                                  ),
                                              child: const Text('Simpan'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
    );
  }
}
