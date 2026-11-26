import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/utils/receipt_parser.dart';
import 'package:sakuin/core/utils/split_bill_calculator.dart';

void main() {
  group('ReceiptParser offline OCR & Gemini JSON', () {
    test(
      'parses Indonesian restaurant receipt with items, tax, service, discount',
      () {
        const ocrText = '''
WARUNG GEPREK MANTAP
Jl. Sudirman No. 12 Jakarta
26/11/2026 12:35
Kasir: Rina
Nasi Ayam Geprek  15.000
2x Es Teh Manis  10.000
Tahu Crispy
2 x 8.000  16.000
Subtotal  41.000
Service Charge  2.000
PB1 10%  4.300
Diskon Promo  -3.000
Grand Total  44.300
QRIS BCA  44.300
Terima Kasih
''';

        final parsed = ReceiptParser.parseOcrText(ocrText);
        expect(parsed.merchantName, 'WARUNG GEPREK MANTAP');
        expect(parsed.occurredAt, DateTime(2026, 11, 26));
        expect(parsed.items.length, 3);
        expect(parsed.items[0].name, 'Nasi Ayam Geprek');
        expect(parsed.items[0].totalPrice, 15000);
        expect(parsed.items[1].name, 'Es Teh Manis');
        expect(parsed.items[1].quantity, 2);
        expect(parsed.items[1].totalPrice, 10000);
        expect(parsed.items[2].name, 'Tahu Crispy');
        expect(parsed.items[2].quantity, 2);
        expect(parsed.items[2].totalPrice, 16000);
        expect(parsed.serviceCharge, 2000);
        expect(parsed.tax, 4300);
        expect(parsed.discount, 3000);
        expect(parsed.declaredTotal, 44300);
        expect(parsed.computedTotal, 44300);
      },
    );

    test('parses Gemini Vision fenced JSON accurately', () {
      const geminiRaw = '''
```json
{
  "merchantName": "Kopi Kenangan",
  "date": "2026-11-26",
  "items": [
    {"name": "Kopi Kenangan Mantan", "quantity": 1, "totalPrice": 22000, "category": "Makanan & Minuman"},
    {"name": "Roti Coklat", "quantity": 2, "totalPrice": 24000, "category": "Makanan & Minuman"}
  ],
  "tax": 4600,
  "serviceCharge": 0,
  "discount": 5000,
  "total": 45600
}
```
''';
      final parsed = ReceiptParser.parseGeminiJson(geminiRaw);
      expect(parsed, isNotNull);
      expect(parsed!.engineUsed, 'gemini');
      expect(parsed.merchantName, 'Kopi Kenangan');
      expect(parsed.items.length, 2);
      expect(parsed.items.first.suggestedCategory, 'Makanan & Minuman');
      expect(parsed.tax, 4600);
      expect(parsed.discount, 5000);
      expect(parsed.computedTotal, 45600);
    });
  });

  group('SplitBillCalculator', () {
    test('splits individual and shared items plus proportional tax with zero rounding loss', () {
      const participants = [
        SplitBillParticipant(id: 'self', name: 'Saya', isSelf: true),
        SplitBillParticipant(id: 'budi', name: 'Budi'),
        SplitBillParticipant(id: 'ani', name: 'Ani'),
      ];

      const items = [
        SplitBillItem(
          id: '1',
          name: 'Nasi Goreng',
          amount: 25000,
          assignedPersonIds: {'self'},
        ),
        SplitBillItem(
          id: '2',
          name: 'Mie Ayam',
          amount: 20000,
          assignedPersonIds: {'budi'},
        ),
        SplitBillItem(
          id: '3',
          name: 'Pizza Patungan',
          amount: 55000,
          assignedPersonIds: {'self', 'budi', 'ani'},
        ),
      ];

      // Subtotal = 100.000, Tax = 10.000, Service = 5.000, Discount = 2.000 -> Grand Total = 113.000
      final res = SplitBillCalculator.calculate(
        participants: participants,
        items: items,
        tax: 10000,
        serviceCharge: 5000,
        discount: 2000,
        proportionalExtras: true,
      );

      expect(res.allItemsAssigned, isTrue);
      expect(res.itemsSubtotal, 100000);
      expect(res.grandTotal, 113000);
      // Total pembagian seluruh peserta harus 100% pas == grandTotal (0 rupiah selisih!)
      expect(res.allocatedTotal, res.grandTotal);

      final shareText = SplitBillCalculator.formatShareText(
        merchantName: 'Resto Enak',
        occurredAt: DateTime(2026, 11, 26),
        payer: participants.first,
        result: res,
      );
      expect(shareText, contains('Resto Enak'));
      expect(shareText, contains('Pizza Patungan (patungan 3 org)'));
      expect(shareText, contains('Budi'));
    });

    test('tracks unassigned items accurately', () {
      const participants = [
        SplitBillParticipant(id: 'self', name: 'Saya', isSelf: true),
      ];
      const items = [
        SplitBillItem(
          id: '1',
          name: 'Es Teh',
          amount: 5000,
          assignedPersonIds: {},
        ),
      ];
      final res = SplitBillCalculator.calculate(
        participants: participants,
        items: items,
      );
      expect(res.allItemsAssigned, isFalse);
      expect(res.unassignedItems.length, 1);
    });
  });
}
