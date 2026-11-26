import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/utils/thousands_input_formatter.dart';

void main() {
  group('ThousandsSeparatorInputFormatter', () {
    final formatter = ThousandsSeparatorInputFormatter();

    TextEditingValue apply(String oldText, String newText, {int? cursor}) {
      return formatter.formatEditUpdate(
        TextEditingValue(text: oldText),
        TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: cursor ?? newText.length),
        ),
      );
    }

    test('formats plain digits with Indonesian dot separators', () {
      expect(apply('', '300000').text, '300.000');
      expect(apply('', '1500000').text, '1.500.000');
      expect(apply('', '50').text, '50');
      expect(apply('', '1000').text, '1.000');
    });

    test('strips non-digit characters and leading zeros', () {
      expect(apply('', 'Rp 250.000abc').text, '250.000');
      expect(apply('', '0005000').text, '5.000');
      expect(apply('', '000').text, '0');
      expect(apply('', '').text, '');
    });

    test('keeps cursor at natural digit position when editing in middle', () {
      // Typing '5' after '1' in '1.000' -> '15.000', cursor sits right after '15' (offset 2)
      final res = apply('1.000', '15.000', cursor: 2);
      expect(res.text, '15.000');
      expect(res.selection.baseOffset, 2);

      // Typing '2' after first '0' in '15.000' -> '150.200', cursor right after '2' (offset 5)
      final res2 = apply('15.000', '15.0200', cursor: 5);
      expect(res2.text, '150.200');
      expect(res2.selection.baseOffset, 5);
    });
  });
}
