import 'record.dart';
import 'spending.dart';

/// Pure, offline logic behind the Subby-style Home and Insights screens.
/// Amounts are minor units (paise for INR).

bool isPayable(AdminRecord r) => countsAsPayment(r.category);

/// Monthly-equivalent cost of a recurring record, in minor units.
int monthlyCost(AdminRecord r) {
  final a = r.amount ?? 0;
  final n = r.number('interval', 1) < 1 ? 1 : r.number('interval', 1);
  switch (r.text('repeat', 'none')) {
    case 'daily':
      return (a * 30 / n).round();
    case 'weekly':
      return (a * 52 / 12 / n).round();
    case 'monthly':
      return (a / n).round();
    case 'yearly':
      return (a / 12 / n).round();
    case 'custom':
      return (a * 30 / n).round();
    default:
      return 0;
  }
}

/// Start of the pay period containing [now] for a payday of month (1-28).
/// Payday 1 (or null) means the calendar month.
DateTime periodStart(DateTime now, int? payday) {
  final p = (payday ?? 1).clamp(1, 28);
  final d = day(now);
  return d.day >= p
      ? DateTime(d.year, d.month, p)
      : DateTime(d.year, d.month - 1, p);
}

DateTime periodEnd(DateTime start) =>
    DateTime(start.year, start.month + 1, start.day);

List<DateTime> _occurrences(AdminRecord r, DateTime from, DateTime to) {
  final out = <DateTime>[];
  var d = r.due;
  var guard = 0;
  while (d != null && d.isBefore(to) && guard++ < 400) {
    if (!d.isBefore(from)) out.add(d);
    final next = r.copy({'due': dateText(d)}).nextDue();
    if (next == null || !next.isAfter(d)) break;
    d = next;
  }
  return out;
}

class MonthSummary {
  final DateTime start, end;
  final String currency;
  final int paid, left, previous, activeCount;
  MonthSummary(
    this.start,
    this.end,
    this.currency,
    this.paid,
    this.left,
    this.previous,
    this.activeCount,
  );
  int get total => paid + left;
  int get days => end.difference(start).inDays;
  int get perDay => days == 0 ? 0 : (total / days).round();
  double get paidShare => total == 0 ? 0 : paid / total;
  int get change => total - previous;
  double? get changePercent => previous == 0 ? null : change * 100 / previous;
}

int paidBetween(
  List<Map<String, Object?>> payments,
  String currency,
  DateTime from,
  DateTime to, {
  Set<int> demoIds = const {},
}) {
  final list = realPayments(payments, currency, demoIds: demoIds).where((p) {
    final at = DateTime.tryParse(p['paidAt'] as String? ?? '')?.toLocal();
    return at != null && !at.isBefore(from) && at.isBefore(to);
  }).toList();
  return paymentTotal(list);
}

/// Paid in this period + still to come (unpaid dues inside the period,
/// including overdue ones from this period), compared with last period's paid.
MonthSummary monthSummary(
  List<AdminRecord> records,
  List<Map<String, Object?>> payments,
  DateTime now, {
  String currency = 'INR',
  int? payday,
}) {
  final start = periodStart(now, payday);
  final end = periodEnd(start);
  final prevStart = DateTime(start.year, start.month - 1, start.day);
  final demoIds = records
      .where((r) => r.flag('demo'))
      .map((r) => r.id)
      .whereType<int>()
      .toSet();
  final paid = paidBetween(payments, currency, start, end, demoIds: demoIds);
  final previous = paidBetween(
    payments,
    currency,
    prevStart,
    start,
    demoIds: demoIds,
  );
  var left = 0;
  final active = records.where(
    (r) =>
        r.status == 'active' &&
        isPayable(r) &&
        r.currency == currency &&
        !r.flag('demo'),
  );
  for (final r in active) {
    final a = r.amount;
    if (a == null) continue;
    final base = r.due;
    if (base == null) continue;
    // Overdue items from before this period still count as to pay.
    if (base.isBefore(start)) left += a;
    left += a * _occurrences(r, start, end).length;
  }
  return MonthSummary(
    start,
    end,
    currency,
    paid,
    left,
    previous,
    active.length,
  );
}

class NextPayment {
  final AdminRecord record;
  final DateTime due;
  final int days;
  NextPayment(this.record, this.due, this.days);
}

String inDays(int days) => days < -1
    ? '${-days} days overdue'
    : days == -1
    ? '1 day overdue'
    : days == 0
    ? 'Today'
    : days == 1
    ? 'Tomorrow'
    : 'In $days days';

List<NextPayment> nextPayments(
  List<AdminRecord> records,
  DateTime now, {
  int limit = 8,
}) {
  final today = day(now);
  final list =
      records
          .where((r) => r.status == 'active' && r.due != null && isPayable(r))
          .map(
            (r) => NextPayment(r, r.due!, day(r.due!).difference(today).inDays),
          )
          .toList()
        ..sort((a, b) => a.due.compareTo(b.due));
  return list.take(limit).toList();
}

class HomeAlert {
  final String kind; // trial, overdue, price
  final String title, body, action;
  final List<AdminRecord> records;
  HomeAlert(this.kind, this.title, this.body, this.action, this.records);
}

/// Alerts shown first on Home: free trials ending within 7 days, overdue
/// payments (bulk Mark all paid) and recent price changes (Keep it).
List<HomeAlert> homeAlerts(List<AdminRecord> records, DateTime now) {
  final today = day(now);
  final active = records.where((r) => r.status == 'active').toList();
  final alerts = <HomeAlert>[];
  for (final r in active) {
    final end = r.date('trialEnd');
    if (end == null || r.flag('trialKept')) continue;
    final d = day(end).difference(today).inDays;
    if (d < 0 || d > 7) continue;
    final after = (r.data['priceAfterTrial'] is num)
        ? r.number('priceAfterTrial')
        : r.amount;
    final yearly = after == null
        ? null
        : monthlyCost(r.copy({'amount': after})) * 12;
    alerts.add(
      HomeAlert(
        'trial',
        '${r.title} trial ends ${d == 0
            ? 'today'
            : d == 1
            ? 'tomorrow'
            : 'in $d days'}',
        after == null
            ? 'Cancel with the provider before it renews.'
            : 'Then ${rupees(after, r.currency)}${yearly != null && yearly > 0 ? ' · cancel first to save ${rupees(yearly, r.currency)} a year' : ''}',
        'Keep it',
        [r],
      ),
    );
  }
  final overdue = active
      .where(
        (r) => isPayable(r) && r.due != null && day(r.due!).isBefore(today),
      )
      .toList();
  if (overdue.isNotEmpty) {
    alerts.add(
      HomeAlert(
        'overdue',
        overdue.length == 1
            ? '${overdue.first.title} is overdue'
            : '${overdue.length} payments overdue',
        overdue.length == 1
            ? 'Was due ${_dayMonth(overdue.first.due)}${overdue.first.amount == null ? '' : ' · ${rupees(overdue.first.amount!, overdue.first.currency)}'}'
            : overdue.map((r) => r.title).take(3).join(', '),
        overdue.length == 1 ? 'Mark paid' : 'Mark all paid',
        overdue,
      ),
    );
  }
  for (final r in active) {
    final change = priceChange(r);
    if (change == null || r.text('priceSeen') == lastPriceChangeAt(r)) continue;
    final changed = DateTime.tryParse(lastPriceChangeAt(r));
    if (changed != null && today.difference(day(changed)).inDays > 45) continue;
    alerts.add(
      HomeAlert(
        'price',
        '${r.title} price ${change > 0 ? 'went up' : 'went down'}',
        '${change > 0 ? '+' : '−'}${rupees(change.abs(), r.currency)} per payment · review it',
        'Keep it',
        [r],
      ),
    );
  }
  return alerts;
}

/// Latest price change from the record's priceHistory entries
/// ({at, from, to} in minor units, written by Repository.save), or null.
int? priceChange(AdminRecord r) {
  final h = (r.data['priceHistory'] as List<dynamic>? ?? [])
      .whereType<Map<dynamic, dynamic>>()
      .where((e) => e['from'] is num && e['to'] is num)
      .toList();
  if (h.isEmpty) return null;
  final last = h.last;
  final change = (last['to'] as num).toInt() - (last['from'] as num).toInt();
  return change == 0 ? null : change;
}

String lastPriceChangeAt(AdminRecord r) {
  final h = (r.data['priceHistory'] as List<dynamic>? ?? [])
      .whereType<Map<dynamic, dynamic>>()
      .toList();
  return h.isEmpty ? '' : '${h.last['at'] ?? ''}';
}

class Signal {
  final String kind, title, body;
  final AdminRecord? record;
  Signal(this.kind, this.title, this.body, [this.record]);
}

/// Simple local signals: price rise/drop, missed (overdue) payments,
/// possible double charge (two payments for one record within 3 days).
List<Signal> signals(
  List<AdminRecord> records,
  List<Map<String, Object?>> payments,
  DateTime now,
) {
  final out = <Signal>[];
  final today = day(now);
  for (final r in records.where((r) => r.status != 'archived')) {
    final c = priceChange(r);
    if (c != null) {
      out.add(
        Signal(
          c > 0 ? 'price_up' : 'price_down',
          '${r.title} price ${c > 0 ? 'rise' : 'drop'}',
          '${c > 0 ? '+' : '-'}${money(c.abs(), r.currency)} per payment',
          r,
        ),
      );
    }
    if (r.status == 'active' && isPayable(r) && r.due != null) {
      final late = today.difference(day(r.due!)).inDays;
      if (late > 0) {
        out.add(
          Signal(
            'missed',
            '${r.title} not marked paid',
            'Due ${_dayMonth(r.due)}, $late day${late == 1 ? '' : 's'} ago',
            r,
          ),
        );
      }
    }
  }
  final byRecord = <Object?, List<DateTime>>{};
  for (final p in payments) {
    final at = DateTime.tryParse(p['paidAt'] as String? ?? '');
    if (at != null) byRecord.putIfAbsent(p['recordId'], () => []).add(at);
  }
  byRecord.forEach((id, dates) {
    dates.sort();
    for (var i = 1; i < dates.length; i++) {
      if (dates[i].difference(dates[i - 1]).inDays.abs() <= 3) {
        final r = records.where((x) => x.id == id).firstOrNull;
        out.add(
          Signal(
            'double',
            'Possible double payment',
            '${r?.title ?? 'A record'} marked paid twice within 3 days',
            r,
          ),
        );
        break;
      }
    }
  });
  return out;
}

/// Paid totals per record title (descending) for the Services tab.
List<MapEntry<String, int>> totalsByItem(
  List<Map<String, Object?>> payments,
  String currency, {
  Set<int> demoIds = const {},
}) {
  final totals = <String, int>{};
  for (final p in realPayments(payments, currency, demoIds: demoIds)) {
    final t = p['title'] as String;
    totals[t] = (totals[t] ?? 0) + (p['amount'] as num).toInt();
  }
  return totals.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

/// Paid totals for the last [months] months, oldest first.
List<int> monthlyTotals(
  List<Map<String, Object?>> payments,
  String currency,
  DateTime now, {
  int months = 12,
  Set<int> demoIds = const {},
}) => [
  for (var i = months - 1; i >= 0; i--)
    paidBetween(
      payments,
      currency,
      DateTime(now.year, now.month - i),
      DateTime(now.year, now.month - i + 1),
      demoIds: demoIds,
    ),
];

/// Expected cost for each of the next [months] months from active recurring
/// and dated records (renewal forecast), oldest first.
List<int> monthsAhead(
  List<AdminRecord> records,
  DateTime now, {
  int months = 6,
  String currency = 'INR',
}) => [
  for (var i = 0; i < months; i++)
    records
        .where(
          (r) =>
              r.status == 'active' &&
              isPayable(r) &&
              r.currency == currency &&
              !r.flag('demo'),
        )
        .fold<int>(
          0,
          (s, r) =>
              s +
              (r.amount ?? 0) *
                  _occurrences(
                    r,
                    DateTime(now.year, now.month + i),
                    DateTime(now.year, now.month + i + 1),
                  ).length,
        ),
];

/// Renewal heatmap: number of due/renewal occurrences per day for the next
/// [days] days starting today.
Map<DateTime, int> renewalHeatmap(
  List<AdminRecord> records,
  DateTime now, {
  int days = 84,
}) {
  final start = day(now);
  final end = start.add(Duration(days: days));
  final map = <DateTime, int>{};
  for (final r in records.where((r) => r.status == 'active')) {
    for (final d in _occurrences(r, start, end)) {
      map[day(d)] = (map[day(d)] ?? 0) + 1;
    }
    final t = r.date('trialEnd');
    if (t != null && !t.isBefore(start) && t.isBefore(end)) {
      map[day(t)] = (map[day(t)] ?? 0) + 1;
    }
  }
  return map;
}

String _csv(Object? v) {
  final s = '${v ?? ''}';
  return RegExp(r'[",\n\r]').hasMatch(s) || s.startsWith(RegExp(r'[=+\-@]'))
      ? '"${(s.startsWith(RegExp(r'[=+\-@]')) ? "'" : '') + s.replaceAll('"', '""')}"'
      : s;
}

/// CSV of payment history (oldest first). Amounts in major units.
String paymentsCsv(List<Map<String, Object?>> payments) {
  final rows = [...payments]
    ..sort((a, b) => '${a['paidAt']}'.compareTo('${b['paidAt']}'));
  final b = StringBuffer('Paid at,Title,Category,Amount,Currency,Due date\r\n');
  for (final p in rows) {
    final cur = p['currency'] as String? ?? 'INR';
    final scale = currencyScale(cur);
    final amount = p['amount'] is num
        ? ((p['amount'] as num) / scale).toStringAsFixed(
            scale == 1
                ? 0
                : scale == 1000
                ? 3
                : 2,
          )
        : '';
    b.write(
      [
        p['paidAt'],
        p['title'],
        p['category'],
        amount,
        cur,
        p['occurrence'],
      ].map(_csv).join(','),
    );
    b.write('\r\n');
  }
  return b.toString();
}

/// "₹1,234" style rupee text for the Home total (whole rupees, Indian grouping).
String _dayMonth(DateTime? d) => d == null
    ? ''
    : '${d.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][d.month - 1]}';

String rupees(int minor, [String currency = 'INR']) {
  if (currency != 'INR') return money(minor, currency);
  final neg = minor < 0;
  final whole = (minor.abs() / 100).round().toString();
  String grouped;
  if (whole.length <= 3) {
    grouped = whole;
  } else {
    final last3 = whole.substring(whole.length - 3);
    var rest = whole.substring(0, whole.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    grouped = '${parts.join(',')},$last3';
  }
  return '${neg ? '-' : ''}₹$grouped';
}
