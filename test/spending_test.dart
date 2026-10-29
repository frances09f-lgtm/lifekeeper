import 'package:flutter_test/flutter_test.dart';
import 'package:lifekeeper/domain/spending.dart';

void main() {
  test('Paid totals keep custom categories and currencies separate, omit demos and document completion', () {
    final values = <Map<String, Object?>>[
      {
        'currency': 'INR',
        'category': 'Electricity',
        'amount': 79900,
        'recordId': 1,
        'title': 'Electricity',
      },
      {
        'currency': 'USD',
        'category': 'Bill',
        'amount': 1000,
        'recordId': 2,
        'title': 'Other currency',
      },
      {
        'currency': 'INR',
        'category': 'Warranty',
        'amount': 99900,
        'recordId': 3,
        'title': 'Warranty',
      },
      {
        'currency': 'INR',
        'category': 'Bill',
        'amount': 25000,
        'recordId': 4,
        'title': 'Demo electricity bill',
      },
      {
        'currency': 'INR',
        'category': 'Bill',
        'amount': 45000,
        'recordId': 5,
        'title': 'Renamed demo',
      },
    ];
    expect(paymentTotal(realPayments(values, 'INR', demoIds: {5})), 79900);
    expect(paymentTotal(realPayments(values, 'USD')), 1000);
    // A person's own bill that merely starts with "Demo" still counts.
    expect(
      paymentTotal(
        realPayments([
          {
            'currency': 'INR',
            'category': 'Bill',
            'amount': 30000,
            'recordId': 9,
            'title': 'Demo class fees',
          },
        ], 'INR'),
      ),
      30000,
    );
    expect(countsAsPayment('Electricity'), true);
    expect(countsAsPayment('ID'), false);
  });
}
