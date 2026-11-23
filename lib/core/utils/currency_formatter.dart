import 'package:intl/intl.dart';

class CurrencyFormatter {
  CurrencyFormatter._();

  static final NumberFormat _idrFormat = NumberFormat('#,##0', 'id_ID');

  /// Format penuh: `Rp 1.250.000` atau `-Rp 1.250.000`
  static String format(int amount, {bool withSymbol = true}) {
    final isNegative = amount < 0;
    final formatted = _idrFormat.format(amount.abs());
    if (!withSymbol) {
      return isNegative ? '-$formatted' : formatted;
    }
    return isNegative ? '-Rp $formatted' : 'Rp $formatted';
  }

  /// Format dengan tanda eksplisit (+ / -): `+Rp 50.000`, `-Rp 25.000`
  static String formatSigned(int amount) {
    if (amount == 0) return 'Rp 0';
    final formatted = _idrFormat.format(amount.abs());
    return amount > 0 ? '+Rp $formatted' : '-Rp $formatted';
  }

  /// Format ringkas untuk grafik / label sempit: `Rp 1,5 jt`, `Rp 250 rb`
  static String formatCompact(int amount) {
    final abs = amount.abs();
    final prefix = amount < 0 ? '-Rp ' : 'Rp ';
    if (abs >= 1000000000) {
      final val = abs / 1000000000;
      return '$prefix${_trimDecimal(val)} M';
    }
    if (abs >= 1000000) {
      final val = abs / 1000000;
      return '$prefix${_trimDecimal(val)} jt';
    }
    if (abs >= 1000) {
      final val = abs / 1000;
      return '$prefix${_trimDecimal(val)} rb';
    }
    return '$prefix$abs';
  }

  static String _trimDecimal(double value) {
    final str = value.toStringAsFixed(1);
    if (str.endsWith('.0')) {
      return str.substring(0, str.length - 2);
    }
    return str.replaceAll('.', ',');
  }

  static const String masked = 'Rp ••••••';
}
