import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sakuin/app.dart';

/// Entry point Sakuin — tanpa pekerjaan berat di main() agar cold start <= 1 detik.
/// Database, notifikasi, dan transaksi berulang diinisialisasi secara lazy setelah frame pertama.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SakuinApp()));
}
