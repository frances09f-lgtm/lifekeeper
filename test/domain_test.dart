import 'package:flutter_test/flutter_test.dart';
import 'package:lifekeeper/domain/record.dart';
import 'package:lifekeeper/domain/bill_rules.dart';
import 'package:lifekeeper/domain/reminders.dart';

void main() {
  test('Month end preserves original day across short months', () {
    var r = AdminRecord({
      'title': 'bill',
      'due': '2025-01-31',
      'repeat': 'monthly',
      'anchorDay': 31,
    });
    expect(dateText(r.nextDue()), '2025-02-28');
    r = r.copy({'due': dateText(r.nextDue())});
    expect(dateText(r.nextDue()), '2025-03-31');
  });
  test('Leap year anchor returns to February 29', () {
    var r = AdminRecord({
      'due': '2024-02-29',
      'repeat': 'yearly',
      'anchorDay': 29,
      'anchorMonth': 2,
    });
    for (var year = 2025; year <= 2028; year++) {
      final next = r.nextDue()!;
      expect(next.day, year == 2028 ? 29 : 28);
      r = r.copy({'due': dateText(next)});
    }
  });
  test('Daily weekly and custom intervals', () {
    expect(
      dateText(AdminRecord({'due': '2026-10-31', 'repeat': 'daily'}).nextDue()),
      '2026-11-01',
    );
    expect(
      dateText(
        AdminRecord({'due': '2026-10-31', 'repeat': 'weekly', 'interval': 2})
            .nextDue(),
      ),
      '2026-11-14',
    );
    expect(
      dateText(
        AdminRecord({'due': '2026-10-31', 'repeat': 'custom', 'interval': 10})
            .nextDue(),
      ),
      '2026-11-10',
    );
  });
  test('Strict date rejects normalized invalid day', () {
    expect(strictDate('2026-02-30'), isNull);
    expect(strictDate('2024-02-29'), DateTime(2024, 2, 29));
    expect(strictDate('01/02/2026'), isNull);
  });
  test('Currency minor units and precision', () {
    expect(minorAmount('1,299.95'), 129995);
    expect(minorAmount('1.234', currency: 'KWD'), 1234);
    expect(minorAmount('1.234'), isNull);
    expect(minorAmount('-1'), isNull);
    expect(minorAmount('abc'), isNull);
    expect(minorAmount('120', currency: 'JPY'), 120);
  });
  test('OCR explicitly labeled due and total', () {
    final d = parseBill(
      'MSEB\nAmount due: Rs. 1,299.50\nDue date: 25/11/2026\nConsumer no: 12345678',
      DateTime(2026, 10, 24),
    );
    expect(d.fields['amount'], 129950);
    expect(d.fields['due'], '2026-11-25');
    expect(d.fields['account'], '12345678');
  });
  test('Invoice date is never used as due date', () {
    final d = parseBill(
      'Bill\nInvoice date: 2026-11-25\nAmount due: 500',
      DateTime(2026),
    );
    expect(d.fields['due'], isNull);
  });
  test('Ambiguous numeric dates and conflicting totals stay blank', () {
    final d = parseBill(
      'Bill\nDue date: 05/11/2026\nAmount due: 500\nGrand total: 600',
      DateTime(2026),
    );
    expect(d.fields['due'], isNull);
    expect(d.fields['amount'], isNull);
    expect(d.warnings, isNotEmpty);
  });
  test('Named Indian date and quick add rule', () {
    final d = parseBill(
      'jio bill 799 on 5 nov monthly',
      DateTime(2026, 10, 24),
      quick: true,
    );
    expect(d.fields['title'], 'jio bill');
    expect(d.fields['amount'], 79900);
    expect(d.fields['due'], '2026-11-05');
    expect(d.fields['repeat'], 'monthly');
  });
  test('Missing and invalid dates are not invented', () {
    expect(billDate('31 February 2026', DateTime(2026)), isNull);
    final d = parseBill('Unclear image', DateTime(2026));
    expect(d.fields['amount'], isNull);
    expect(d.fields['due'], isNull);
  });
  test('Money does not change urgency', () {
    final a = AdminRecord({'due': '2026-10-20', 'amount': 1});
    final b = a.copy({'amount': 999999999});
    expect(
      priority(a, DateTime(2026, 10, 24)).score,
      priority(b, DateTime(2026, 10, 24)).score,
    );
  });
  test('Grace, dependencies and manual weights explain priority', () {
    final r = AdminRecord({
      'title': 'policy',
      'due': '2026-10-22',
      'grace': 3,
      'importance': 2,
      'dependencies': [2],
      'consequence': 'Coverage ends',
      'snoozeCount': 3,
    });
    final score = priority(r, DateTime(2026, 10, 24), activeIds: {2});
    expect(score.reasons.join(' '), contains('within grace'));
    expect(score.reasons.join(' '), contains('Depends'));
    expect(score.score, greaterThan(50));
    expect(priority(r.copy({'priorityOverride': 9}), DateTime(2026)).score, 9);
  });
  test('Radar excludes archived and dismissed records', () {
    expect(
      radar([
        AdminRecord({'title': 'x', 'status': 'archived'}),
        AdminRecord({'title': 'y', 'dismissUntil': '2027-01-01T00:00:00'}),
      ], DateTime(2026)),
      isEmpty,
    );
  });
  test('Quiet hours rollover and inclusive start exclusive end', () {
    expect(
      quietAdjusted(DateTime(2026, 10, 24, 22), 1320, 480),
      DateTime(2026, 10, 25, 8),
    );
    expect(
      quietAdjusted(DateTime(2026, 10, 24, 8), 1320, 480),
      DateTime(2026, 10, 24, 8),
    );
    expect(
      quietAdjusted(DateTime(2026, 10, 24, 2), 1320, 480),
      DateTime(2026, 10, 24, 8),
    );
    expect(
      quietAdjusted(DateTime(2026, 10, 24, 14), 780, 900),
      DateTime(2026, 10, 24, 15),
    );
  });
  test('Stable unique reminder IDs and completed cancellation', () {
    final r = AdminRecord({
      'title': 'x',
      'due': '2026-11-10',
      'reminders': [7, 3, 1, 0],
    }, id: 1);
    final now = DateTime(2026, 10, 24);
    final a = planReminders([r], now, {'digest': false});
    final b = planReminders(
      [
        r.copy({'due': '2026-11-15'}),
      ],
      now,
      {'digest': false},
    );
    expect(a.map((e) => e.id), b.map((e) => e.id));
    expect(a.map((e) => e.id).toSet().length, a.length);
    expect(
      planReminders(
        [
          r.copy({'status': 'completed'}),
        ],
        now,
        {'digest': false},
      ),
      isEmpty,
    );
  });
  test('Snooze replaces scheduled dues and disabled clears all', () {
    final r = AdminRecord({
      'title': 'x',
      'due': '2026-11-10',
      'snoozeUntil': '2026-10-25T09:00:00',
    }, id: 2);
    final a = planReminders([r], DateTime(2026, 10, 24), {'digest': false});
    expect(a.length, 1);
    expect(a.single.id, 44);
    expect(
      planReminders([r], DateTime(2026), {'notifications': false}),
      isEmpty,
    );
  });
}
