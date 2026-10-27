import 'package:flutter_test/flutter_test.dart';
import 'package:lifekeeper/domain/insights.dart';
import 'package:lifekeeper/domain/record.dart';
import 'package:lifekeeper/domain/reminders.dart';

Map<String, Object?> pay(
  int recordId,
  String at,
  int amount, {
  String title = 'Netflix',
  String category = 'Subscription',
}) => {
  'recordId': recordId,
  'occurrence': at.substring(0, 10),
  'paidAt': at,
  'amount': amount,
  'currency': 'INR',
  'title': title,
  'category': category,
};

void main() {
  final now = DateTime(2026, 10, 28, 10);
  test('Month summary counts paid, still to come and change vs last month', () {
    final records = [
      AdminRecord({
        'title': 'Jio',
        'category': 'Bill',
        'amount': 79900,
        'due': '2026-10-30',
        'repeat': 'monthly',
      }, id: 1),
      AdminRecord({
        'title': 'Gym',
        'category': 'Subscription',
        'amount': 100000,
        'due': '2026-10-20',
        'repeat': 'monthly',
      }, id: 2),
      AdminRecord({
        'title': 'Phone warranty',
        'category': 'Warranty',
        'amount': 500000,
        'due': '2026-10-29',
      }, id: 3),
      AdminRecord({
        'title': 'Weekly milk',
        'category': 'Bill',
        'amount': 10000,
        'due': '2026-10-29',
        'repeat': 'weekly',
      }, id: 4),
    ];
    final payments = [
      pay(5, '2026-10-05T10:00:00', 64900),
      pay(5, '2026-09-05T10:00:00', 50000),
    ];
    final s = monthSummary(records, payments, now);
    expect(s.paid, 64900);
    // Jio 799 + overdue gym 1000 + milk once in Oct (29th) = 1899; warranty ignored.
    expect(s.left, 79900 + 100000 + 10000);
    expect(s.previous, 50000);
    expect(s.total, 64900 + 189900);
    expect(s.days, 31);
    expect(s.perDay, ((64900 + 189900) / 31).round());
    expect(s.change, s.total - 50000);
  });

  test('Payday budget period starts on the payday', () {
    expect(periodStart(DateTime(2026, 10, 28), 25), DateTime(2026, 10, 25));
    expect(periodStart(DateTime(2026, 10, 3), 25), DateTime(2026, 9, 25));
    expect(periodStart(DateTime(2026, 1, 3), 25), DateTime(2025, 12, 25));
    expect(periodEnd(DateTime(2026, 9, 25)), DateTime(2026, 10, 25));
    expect(periodStart(DateTime(2026, 10, 28), null), DateTime(2026, 10, 1));
    final s = monthSummary(
      [],
      [pay(1, '2026-10-24T09:00:00', 100), pay(1, '2026-10-26T09:00:00', 200)],
      now,
      payday: 25,
    );
    expect(s.paid, 200);
    expect(s.previous, 100);
  });

  test('Next payments sorted with In N days chips and no documents', () {
    final records = [
      AdminRecord({
        'title': 'B',
        'category': 'Bill',
        'amount': 1,
        'due': '2026-10-30',
      }, id: 1),
      AdminRecord({
        'title': 'A',
        'category': 'Bill',
        'amount': 1,
        'due': '2026-10-28',
      }, id: 2),
      AdminRecord({
        'title': 'Passport',
        'category': 'ID',
        'due': '2026-10-29',
      }, id: 3),
      AdminRecord({
        'title': 'Done',
        'category': 'Bill',
        'due': '2026-10-29',
        'status': 'completed',
      }, id: 4),
    ];
    final n = nextPayments(records, now);
    expect(n.map((e) => e.record.title), ['A', 'B']);
    expect(n.map((e) => inDays(e.days)), ['Today', 'In 2 days']);
    expect(inDays(1), 'Tomorrow');
    expect(inDays(-3), '3 days overdue');
  });

  test(
    'Alerts: trial ending, overdue bulk and price change, each dismissible',
    () {
      final trial = AdminRecord({
        'title': 'Prime',
        'category': 'Subscription',
        'amount': 0,
        'priceAfterTrial': 29900,
        'repeat': 'monthly',
        'due': '2026-11-02',
        'trialEnd': '2026-11-01',
      }, id: 1);
      final late1 = AdminRecord({
        'title': 'Power',
        'category': 'Bill',
        'amount': 1,
        'due': '2026-10-20',
      }, id: 2);
      final late2 = AdminRecord({
        'title': 'Water',
        'category': 'Bill',
        'amount': 1,
        'due': '2026-10-27',
      }, id: 3);
      final price = AdminRecord({
        'title': 'Spotify',
        'category': 'Subscription',
        'amount': 13900,
        'due': '2026-11-20',
        'priceHistory': [
          {'at': '2026-10-20T10:00:00', 'from': 11900, 'to': 13900},
        ],
      }, id: 4);
      final alerts = homeAlerts([trial, late1, late2, price], now);
      expect(alerts.map((a) => a.kind), ['trial', 'overdue', 'price']);
      expect(alerts[0].title, 'Prime trial ends in 4 days');
      expect(alerts[0].body, contains('save ₹3,588 a year'));
      expect(alerts[1].action, 'Mark all paid');
      expect(alerts[1].records.length, 2);
      expect(alerts[2].body, '+₹20 per payment · review it');
      final dismissed = homeAlerts([
        trial.copy({'trialKept': true}),
        price.copy({'priceSeen': '2026-10-20T10:00:00'}),
      ], now);
      expect(dismissed, isEmpty);
    },
  );

  test('Signals: price rise, missed payment and possible double charge', () {
    final r = AdminRecord({
      'title': 'Spotify',
      'category': 'Subscription',
      'amount': 13900,
      'due': '2026-10-21',
      'priceHistory': [
        {'at': '2026-10-01', 'from': 11900, 'to': 13900},
      ],
    }, id: 7);
    final s = signals(
      [r],
      [
        pay(7, '2026-09-01T10:00:00', 11900),
        pay(7, '2026-09-03T10:00:00', 11900),
      ],
      now,
    );
    expect(s.map((e) => e.kind).toSet(), {'price_up', 'missed', 'double'});
  });

  test('Insights totals, months ahead, heatmap and monthly cost', () {
    final payments = [
      pay(1, '2026-10-01T10:00:00', 100),
      pay(1, '2026-09-01T10:00:00', 100),
      pay(2, '2026-10-02T10:00:00', 500, title: 'Rent', category: 'Bill'),
    ];
    expect(totalsByItem(payments, 'INR').map((e) => '${e.key}:${e.value}'), [
      'Rent:500',
      'Netflix:200',
    ]);
    expect(monthlyTotals(payments, 'INR', now, months: 2), [100, 600]);
    final monthly = AdminRecord({
      'title': 'Jio',
      'category': 'Bill',
      'amount': 1000,
      'due': '2026-10-31',
      'repeat': 'monthly',
    }, id: 1);
    expect(monthsAhead([monthly], now, months: 3), [1000, 1000, 1000]);
    final heat = renewalHeatmap([monthly], now, days: 40);
    expect(heat[DateTime(2026, 10, 31)], 1);
    expect(heat[DateTime(2026, 11, 30)], 1);
    expect(
      monthlyCost(monthly.copy({'repeat': 'yearly', 'amount': 12000})),
      1000,
    );
    expect(monthlyCost(monthly.copy({'repeat': 'none'})), 0);
  });

  test('CSV export escapes text, guards formulas and uses major units', () {
    final csv = paymentsCsv([
      pay(1, '2026-10-02T10:00:00', 79900, title: 'Jio, postpaid'),
      pay(2, '2026-10-01T10:00:00', 100, title: '=HYPERLINK("x")'),
    ]);
    final lines = csv.trim().split('\r\n');
    expect(lines.first, 'Paid at,Title,Category,Amount,Currency,Due date');
    expect(lines[1], contains('"\'=HYPERLINK(""x"")"'));
    expect(lines[2], contains('"Jio, postpaid",Subscription,799.00,INR'));
  });

  test('Rupee total uses Indian grouping', () {
    expect(rupees(12345678900), '₹12,34,56,789');
    expect(rupees(79900), '₹799');
    expect(rupees(-150000), '-₹1,500');
  });

  test(
    'Unpaid reminders repeat daily for a week and Remind tomorrow snoozes',
    () {
      final r = AdminRecord({
        'title': 'Jio',
        'category': 'Bill',
        'due': '2026-11-10',
        'reminders': [0],
      }, id: 3);
      final alerts = planReminders(
        [r],
        now,
        {'digest': false, 'quietStart': 0, 'quietEnd': 0},
      );
      final days = alerts.map((a) => a.at.day).toList();
      expect(days, [10, 11, 12, 13, 14, 15, 16]);
      expect(alerts.map((a) => a.id).toSet().length, 7);
      expect(alerts.every((a) => a.id >= 48 && a.id < 64), isTrue);
      expect(
        remindTomorrowAt(DateTime(2026, 10, 28, 22, 15), 540),
        DateTime(2026, 10, 29, 9),
      );
    },
  );
}
