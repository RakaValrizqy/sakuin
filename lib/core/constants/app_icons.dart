import 'package:flutter/material.dart';

/// Peta ikon Material konstan (tree-shake friendly, tanpa asset bitmap berat).
class AppIcons {
  AppIcons._();

  static const Map<String, IconData> _map = {
    // Dompet
    'wallet': Icons.account_balance_wallet_rounded,
    'cash': Icons.payments_rounded,
    'bank': Icons.account_balance_rounded,
    'ewallet': Icons.smartphone_rounded,
    'savings': Icons.savings_rounded,
    'card': Icons.credit_card_rounded,
    'safe': Icons.lock_rounded,
    'briefcase': Icons.work_rounded,

    // Pengeluaran
    'food': Icons.restaurant_rounded,
    'coffee': Icons.local_cafe_rounded,
    'transport': Icons.directions_car_rounded,
    'motorcycle': Icons.two_wheeler_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'groceries': Icons.shopping_cart_rounded,
    'bills': Icons.receipt_long_rounded,
    'electricity': Icons.bolt_rounded,
    'phone': Icons.wifi_rounded,
    'health': Icons.medical_services_rounded,
    'education': Icons.school_rounded,
    'entertainment': Icons.movie_rounded,
    'game': Icons.sports_esports_rounded,
    'home': Icons.home_rounded,
    'gift': Icons.card_giftcard_rounded,
    'charity': Icons.volunteer_activism_rounded,
    'admin_fee': Icons.swap_horiz_rounded,
    'travel': Icons.flight_rounded,
    'pet': Icons.pets_rounded,
    'fitness': Icons.fitness_center_rounded,
    'beauty': Icons.spa_rounded,
    'family': Icons.family_restroom_rounded,

    // Pemasukan
    'salary': Icons.payments_outlined,
    'bonus': Icons.stars_rounded,
    'business': Icons.storefront_rounded,
    'investment': Icons.trending_up_rounded,
    'freelance': Icons.laptop_mac_rounded,
    'refund': Icons.replay_rounded,

    // Umum
    'other': Icons.category_rounded,
    'more': Icons.more_horiz_rounded,
    'debt': Icons.handshake_rounded,
  };

  static const List<String> walletIconKeys = [
    'cash',
    'bank',
    'ewallet',
    'wallet',
    'savings',
    'card',
    'briefcase',
    'safe',
  ];

  static const List<String> categoryIconKeys = [
    'food',
    'coffee',
    'transport',
    'motorcycle',
    'fuel',
    'shopping',
    'groceries',
    'bills',
    'electricity',
    'phone',
    'health',
    'education',
    'entertainment',
    'game',
    'home',
    'gift',
    'charity',
    'admin_fee',
    'travel',
    'pet',
    'fitness',
    'beauty',
    'family',
    'salary',
    'bonus',
    'business',
    'investment',
    'freelance',
    'refund',
    'other',
  ];

  static IconData fromKey(String key) => _map[key] ?? Icons.category_rounded;
}
