/// Data kategori bawaan dan pintasan nama dompet (ikon generik + warna, tanpa logo merek).
class DefaultCategorySeed {
  const DefaultCategorySeed({
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.sortOrder,
  });

  final String name;
  final String type; // 'expense' | 'income'
  final String icon;
  final int color;
  final int sortOrder;
}

class WalletPreset {
  const WalletPreset({
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
  });

  final String name;
  final String type; // 'cash' | 'bank' | 'ewallet' | 'other'
  final String icon;
  final int color;
}

class DefaultSeeds {
  DefaultSeeds._();

  static const String adminFeeCategoryName = 'Biaya Admin';

  static const List<DefaultCategorySeed> categories = [
    // Pengeluaran (sesuai spesifikasi 7.2)
    DefaultCategorySeed(
      name: 'Makanan & Minuman',
      type: 'expense',
      icon: 'food',
      color: 0xFFEA580C,
      sortOrder: 0,
    ),
    DefaultCategorySeed(
      name: 'Transportasi',
      type: 'expense',
      icon: 'transport',
      color: 0xFF0284C7,
      sortOrder: 1,
    ),
    DefaultCategorySeed(
      name: 'Belanja',
      type: 'expense',
      icon: 'shopping',
      color: 0xFFDB2777,
      sortOrder: 2,
    ),
    DefaultCategorySeed(
      name: 'Tagihan & Utilitas',
      type: 'expense',
      icon: 'bills',
      color: 0xFFD97706,
      sortOrder: 3,
    ),
    DefaultCategorySeed(
      name: 'Pulsa & Internet',
      type: 'expense',
      icon: 'phone',
      color: 0xFF4F46E5,
      sortOrder: 4,
    ),
    DefaultCategorySeed(
      name: 'Kesehatan',
      type: 'expense',
      icon: 'health',
      color: 0xFFDC2626,
      sortOrder: 5,
    ),
    DefaultCategorySeed(
      name: 'Pendidikan',
      type: 'expense',
      icon: 'education',
      color: 0xFF1D4ED8,
      sortOrder: 6,
    ),
    DefaultCategorySeed(
      name: 'Hiburan',
      type: 'expense',
      icon: 'entertainment',
      color: 0xFF7C3AED,
      sortOrder: 7,
    ),
    DefaultCategorySeed(
      name: 'Rumah',
      type: 'expense',
      icon: 'home',
      color: 0xFF0F766E,
      sortOrder: 8,
    ),
    DefaultCategorySeed(
      name: 'Hadiah & Sosial',
      type: 'expense',
      icon: 'gift',
      color: 0xFF65A30D,
      sortOrder: 9,
    ),
    DefaultCategorySeed(
      name: adminFeeCategoryName,
      type: 'expense',
      icon: 'admin_fee',
      color: 0xFF475569,
      sortOrder: 10,
    ),
    DefaultCategorySeed(
      name: 'Lainnya',
      type: 'expense',
      icon: 'other',
      color: 0xFF64748B,
      sortOrder: 11,
    ),

    // Pemasukan (sesuai spesifikasi 7.2)
    DefaultCategorySeed(
      name: 'Gaji',
      type: 'income',
      icon: 'salary',
      color: 0xFF15803D,
      sortOrder: 0,
    ),
    DefaultCategorySeed(
      name: 'Bonus',
      type: 'income',
      icon: 'bonus',
      color: 0xFFD97706,
      sortOrder: 1,
    ),
    DefaultCategorySeed(
      name: 'Usaha',
      type: 'income',
      icon: 'business',
      color: 0xFF0F766E,
      sortOrder: 2,
    ),
    DefaultCategorySeed(
      name: 'Hadiah',
      type: 'income',
      icon: 'gift',
      color: 0xFFDB2777,
      sortOrder: 3,
    ),
    DefaultCategorySeed(
      name: 'Investasi',
      type: 'income',
      icon: 'investment',
      color: 0xFF0284C7,
      sortOrder: 4,
    ),
    DefaultCategorySeed(
      name: 'Lainnya',
      type: 'income',
      icon: 'other',
      color: 0xFF475569,
      sortOrder: 5,
    ),
  ];

  /// Pintasan nama umum untuk onboarding/form dompet (ikon generik + warna saja).
  static const List<WalletPreset> walletPresets = [
    WalletPreset(name: 'Tunai', type: 'cash', icon: 'cash', color: 0xFF15803D),
    WalletPreset(name: 'BCA', type: 'bank', icon: 'bank', color: 0xFF1D4ED8),
    WalletPreset(name: 'BRI', type: 'bank', icon: 'bank', color: 0xFF0284C7),
    WalletPreset(
      name: 'Mandiri',
      type: 'bank',
      icon: 'bank',
      color: 0xFFD97706,
    ),
    WalletPreset(name: 'BNI', type: 'bank', icon: 'bank', color: 0xFFEA580C),
    WalletPreset(
      name: 'GoPay',
      type: 'ewallet',
      icon: 'ewallet',
      color: 0xFF0F766E,
    ),
    WalletPreset(
      name: 'OVO',
      type: 'ewallet',
      icon: 'ewallet',
      color: 0xFF7C3AED,
    ),
    WalletPreset(
      name: 'DANA',
      type: 'ewallet',
      icon: 'ewallet',
      color: 0xFF0284C7,
    ),
    WalletPreset(
      name: 'ShopeePay',
      type: 'ewallet',
      icon: 'ewallet',
      color: 0xFFEA580C,
    ),
    WalletPreset(
      name: 'Tabungan',
      type: 'other',
      icon: 'savings',
      color: 0xFF4F46E5,
    ),
  ];
}
