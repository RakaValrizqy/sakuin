import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// TextInputFormatter untuk input nominal Rupiah dengan pemisah ribuan titik secara live.
/// Contoh: mengetik `300000` langsung tampil `300.000` (dipasangkan dengan `prefixText: 'Rp '`).
class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  ThousandsSeparatorInputFormatter({this.maxDigits = 12});

  final int maxDigits;
  static final NumberFormat _fmt = NumberFormat('#,##0', 'id_ID');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }

    final trimmed = digits.length > maxDigits
        ? digits.substring(0, maxDigits)
        : digits;
    final parsed = int.tryParse(trimmed);
    if (parsed == null) return oldValue;

    final formatted = _fmt.format(parsed);

    // Pertahankan posisi kursor relatif terhadap jumlah digit di sebelah kanan kursor
    final rightSlice =
        newValue.selection.end >= 0 &&
            newValue.selection.end <= newValue.text.length
        ? newValue.text.substring(newValue.selection.end)
        : '';
    final digitsToRight = rightSlice.replaceAll(RegExp(r'[^0-9]'), '').length;

    var cursorOffset = formatted.length;
    if (digitsToRight > 0) {
      cursorOffset = 0;
      var seenDigits = 0;
      for (var i = formatted.length - 1; i >= 0; i--) {
        final code = formatted.codeUnitAt(i);
        if (code >= 48 && code <= 57) {
          seenDigits++;
          if (seenDigits == digitsToRight) {
            cursorOffset = i;
            // Jika tepat di depan kursor ada titik pemisah ribuan, geser kursor ke kiri titik
            // agar tombol backspace menghapus digit sebelumnya, bukan terjebak di titik.
            if (cursorOffset > 0 &&
                formatted.codeUnitAt(cursorOffset - 1) == 46) {
              cursorOffset--;
            }
            break;
          }
        }
      }
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: cursorOffset.clamp(0, formatted.length),
      ),
    );
  }
}
