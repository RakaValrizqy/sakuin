import 'package:flutter/material.dart';

/// Warna semantik & palet pilihan untuk Sakuin.
/// Aturan spesifikasi: pengeluaran = merah, pemasukan = hijau, transfer = biru/netral.
class AppColors {
  AppColors._();

  // Brand accent
  static const Color seed = Color(0xFF0F766E);

  // Semantic colors - Light
  static const Color expenseLight = Color(0xFFDC2626);
  static const Color expenseContainerLight = Color(0xFFFEE2E2);
  static const Color incomeLight = Color(0xFF15803D);
  static const Color incomeContainerLight = Color(0xFFDCFCE7);
  static const Color transferLight = Color(0xFF2563EB);
  static const Color transferContainerLight = Color(0xFFDBEAFE);
  static const Color warningLight = Color(0xFFD97706);
  static const Color warningContainerLight = Color(0xFFFEF3C7);

  // Semantic colors - Dark
  static const Color expenseDark = Color(0xFFF87171);
  static const Color expenseContainerDark = Color(0xFF451A1A);
  static const Color incomeDark = Color(0xFF4ADE80);
  static const Color incomeContainerDark = Color(0xFF143824);
  static const Color transferDark = Color(0xFF60A5FA);
  static const Color transferContainerDark = Color(0xFF172B4D);
  static const Color warningDark = Color(0xFFFBBF24);
  static const Color warningContainerDark = Color(0xFF422C08);

  static Color expense(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? expenseDark
      : expenseLight;

  static Color expenseContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? expenseContainerDark
      : expenseContainerLight;

  static Color income(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? incomeDark
      : incomeLight;

  static Color incomeContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? incomeContainerDark
      : incomeContainerLight;

  static Color transfer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? transferDark
      : transferLight;

  static Color transferContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? transferContainerDark
      : transferContainerLight;

  static Color warning(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? warningDark
      : warningLight;

  static Color warningContainer(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? warningContainerDark
      : warningContainerLight;

  /// Palet warna pilihan untuk dompet & kategori.
  static const List<int> pickerPalette = [
    0xFF0F766E, // Teal
    0xFF15803D, // Hijau
    0xFF0284C7, // Biru Langit
    0xFF1D4ED8, // Biru Bank
    0xFF4F46E5, // Indigo
    0xFF7C3AED, // Ungu
    0xFFDB2777, // Pink
    0xFFDC2626, // Merah
    0xFFEA580C, // Oranye
    0xFFD97706, // Kuning Emas
    0xFF65A30D, // Lime
    0xFF475569, // Abu Slate
  ];
}
