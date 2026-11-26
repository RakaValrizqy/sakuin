import 'package:flutter_test/flutter_test.dart';
import 'package:sakuin/core/utils/income_allocation_calculator.dart';

void main() {
  group('IncomeAllocationCalculator', () {
    test('allocates income by percentage and puts remainder into Belum Dialokasikan', () {
      final res = IncomeAllocationCalculator.calculate(
        incomeAmount: 5000000,
        pocketIds: const [1, 2, 3],
        rawPercentByPocketId: const {1: 40, 2: 30, 3: 10},
      );

      expect(res.allocatedPercent, 80);
      expect(res.unallocatedPercent, 20);
      expect(res.amountByPocketId[1], 2000000);
      expect(res.amountByPocketId[2], 1500000);
      expect(res.amountByPocketId[3], 500000);
      expect(res.unallocatedAmount, 1000000);
      expect(res.allocatedTotal + res.unallocatedAmount, 5000000);
    });

    test('preserves exact Rupiah total via largest-remainder rounding', () {
      // 100.000 dibagi 33% + 33% + 34% (atau 33% + 33% + 33% + 1% unallocated)
      final res = IncomeAllocationCalculator.calculate(
        incomeAmount: 100001,
        pocketIds: const [10, 20, 30],
        rawPercentByPocketId: const {10: 33, 20: 33, 30: 33},
      );

      expect(res.allocatedPercent, 99);
      expect(res.unallocatedPercent, 1);
      expect(res.allocatedTotal + res.unallocatedAmount, 100001);
    });

    test(
      'clamps total percentages to 100% and handles 0% (100% unallocated)',
      () {
        final clamped = IncomeAllocationCalculator.calculate(
          incomeAmount: 1000000,
          pocketIds: const [1, 2],
          rawPercentByPocketId: const {1: 70, 2: 60},
        );
        expect(clamped.percentByPocketId[1], 70);
        expect(clamped.percentByPocketId[2], 30);
        expect(clamped.unallocatedPercent, 0);
        expect(clamped.allocatedTotal, 1000000);

        final allUnallocated = IncomeAllocationCalculator.calculate(
          incomeAmount: 1000000,
          pocketIds: const [1, 2],
          rawPercentByPocketId: const {},
        );
        expect(allUnallocated.allocatedPercent, 0);
        expect(allUnallocated.unallocatedPercent, 100);
        expect(allUnallocated.unallocatedAmount, 1000000);
      },
    );
  });
}
