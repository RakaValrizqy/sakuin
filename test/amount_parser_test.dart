import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/utils/amount_parser.dart';
import 'package:sakuin/core/utils/currency_formatter.dart';

void main() {
  group('AmountParser', () {
    test('parses plain integers and Indonesian thousand separators', () {
      expect(AmountParser.parse('15000'), 15000);
      expect(AmountParser.parse('1.250.000'), 1250000);
      expect(AmountParser.parse('Rp 25.000'), 25000);
      expect(AmountParser.parse('0'), 0);
    });

    test('parses shorthand k / rb / ribu / jt / juta', () {
      expect(AmountParser.parse('15k'), 15000);
      expect(AmountParser.parse('15rb'), 15000);
      expect(AmountParser.parse('15ribu'), 15000);
      expect(AmountParser.parse('2,5k'), 2500);
      expect(AmountParser.parse('1,5jt'), 1500000);
      expect(AmountParser.parse('1.5jt'), 1500000);
      expect(AmountParser.parse('2juta'), 2000000);
    });

    test('evaluates arithmetic expressions with operator precedence', () {
      expect(AmountParser.parse('15k+5k'), 20000);
      expect(AmountParser.parse('100k−15k'), 85000);
      expect(AmountParser.parse('25000×3'), 75000);
      expect(AmountParser.parse('100000÷4'), 25000);
      expect(AmountParser.parse('20k+10k×2'), 40000);
      expect(AmountParser.parse('15k+'), 15000); // trailing operator ignored
    });

    test('returns null for empty or invalid input', () {
      expect(AmountParser.parse(''), isNull);
      expect(AmountParser.parse('abc'), isNull);
      expect(AmountParser.parse('100÷0'), isNull);
    });
  });

  group('CurrencyFormatter', () {
    test('formats Rupiah cleanly', () {
      expect(CurrencyFormatter.format(1250000), 'Rp 1.250.000');
      expect(CurrencyFormatter.format(-50000), '-Rp 50.000');
      expect(CurrencyFormatter.formatSigned(50000), '+Rp 50.000');
      expect(CurrencyFormatter.formatCompact(1500000), 'Rp 1,5 jt');
      expect(CurrencyFormatter.formatCompact(250000), 'Rp 250 rb');
    });
  });
}
