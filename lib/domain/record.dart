import 'dart:math';

DateTime day(DateTime value) => DateTime(value.year, value.month, value.day);
String dateText(DateTime? value) => value == null
    ? ''
    : '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
DateTime? strictDate(String value) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (m == null) return null;
  final y = int.parse(m[1]!);
  final mo = int.parse(m[2]!);
  final d = int.parse(m[3]!);
  final date = DateTime(y, mo, d);
  return y >= 1900 &&
          y <= 2200 &&
          date.year == y &&
          date.month == mo &&
          date.day == d
      ? date
      : null;
}

int currencyScale(String currency) => const ['JPY', 'KRW'].contains(currency)
    ? 1
    : const ['KWD', 'BHD', 'OMR'].contains(currency)
    ? 1000
    : 100;
int? minorAmount(String text, {String currency = 'INR'}) {
  final clean = text.trim().replaceAll(',', '');
  final scale = currencyScale(currency);
  final digits = scale == 1
      ? 0
      : scale == 1000
      ? 3
      : 2;
  final pattern = digits == 0
      ? RegExp(r'^\d+$')
      : RegExp('^\\d+(?:\\.\\d{1,$digits})?\$');
  if (!pattern.hasMatch(clean)) return null;
  if (digits == 0 && clean.contains('.')) return null;
  final parts = clean.split('.');
  final whole = int.tryParse(parts.first);
  if (whole == null || whole > 100000000000) return null;
  return whole * scale +
      (parts.length == 1 ? 0 : int.parse(parts[1].padRight(digits, '0')));
}

String money(int value, String currency) =>
    '$currency ${(value / currencyScale(currency)).toStringAsFixed(currencyScale(currency) == 1
        ? 0
        : currencyScale(currency) == 1000
        ? 3
        : 2)}';

class AdminRecord {
  final int? id;
  final Map<String, dynamic> data;
  AdminRecord(Map<String, dynamic> values, {this.id})
    : data = Map<String, dynamic>.from(values);
  String text(String key, [String fallback = '']) =>
      data[key] is String ? data[key] as String : fallback;
  int number(String key, [int fallback = 0]) =>
      data[key] is num ? (data[key] as num).toInt() : fallback;
  bool flag(String key) => data[key] == true;
  DateTime? date(String key) => strictDate(text(key));
  DateTime? instant(String key) => DateTime.tryParse(text(key));
  String get title => text('title');
  String get category => text('category', 'Bill');
  String get status => text('status', 'active');
  String get currency => text('currency', 'INR');
  DateTime? get due => date('due');
  int? get amount => data['amount'] is num ? number('amount') : null;
  List<int> get reminders =>
      (data['reminders'] as List<dynamic>? ?? <dynamic>[7, 3, 1, 0])
          .whereType<num>()
          .map((e) => e.toInt())
          .toSet()
          .take(8)
          .toList()
        ..sort((a, b) => b.compareTo(a));
  List<int> get dependencies =>
      (data['dependencies'] as List<dynamic>? ?? <dynamic>[])
          .whereType<num>()
          .map((e) => e.toInt())
          .toList();
  List<Map<String, dynamic>> get attachments =>
      (data['attachments'] as List<dynamic>? ?? <dynamic>[])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
  AdminRecord copy(Map<String, dynamic> updates, {int? newId}) =>
      AdminRecord({...data, ...updates}, id: newId ?? id);
  DateTime? nextDue() {
    final current = due;
    if (current == null) return null;
    final interval = max(1, number('interval', 1));
    switch (text('repeat', 'none')) {
      case 'daily':
        return DateTime(current.year, current.month, current.day + interval);
      case 'weekly':
        return DateTime(
          current.year,
          current.month,
          current.day + 7 * interval,
        );
      case 'custom':
        return DateTime(current.year, current.month, current.day + interval);
      case 'monthly':
        final first = DateTime(current.year, current.month + interval, 1);
        return DateTime(
          first.year,
          first.month,
          min(
            number('anchorDay', current.day),
            DateTime(first.year, first.month + 1, 0).day,
          ),
        );
      case 'yearly':
        final y = current.year + interval;
        final m = number('anchorMonth', current.month);
        return DateTime(
          y,
          m,
          min(number('anchorDay', current.day), DateTime(y, m + 1, 0).day),
        );
      default:
        return null;
    }
  }
}

class RadarResult {
  final AdminRecord record;
  final int score;
  final List<String> reasons;
  RadarResult(this.record, this.score, this.reasons);
  String get label => score >= 80
      ? 'Critical'
      : score >= 50
      ? 'High'
      : score >= 25
      ? 'Medium'
      : 'Low';
}

RadarResult priority(
  AdminRecord r,
  DateTime now, {
  Map<String, dynamic> weights = const {},
  Set<int> activeIds = const {},
}) {
  int weight(String key, int fallback) =>
      ((weights[key] as num?)?.toInt() ?? fallback).clamp(0, 100);
  var score = 0;
  final reasons = <String>[];
  final due = r.due;
  if (due != null) {
    final delta = day(due).difference(day(now)).inDays;
    final grace = r.number('grace');
    if (delta < -grace) {
      score += weight('overdue', 50);
      reasons.add('${-delta} days overdue, grace ended');
    } else if (delta < 0) {
      score += weight('grace', 20);
      reasons.add('Due date passed, within grace period');
    } else if (delta <= 3) {
      score += weight('soon', 35);
      reasons.add('Due in $delta days');
    } else if (delta <= 7) {
      score += weight('week', 20);
      reasons.add('Due this week');
    } else if (delta <= 30) {
      score += 10;
      reasons.add('Due within 30 days');
    }
  }
  if (r.text('consequence').isNotEmpty) {
    score += weight('consequence', 15);
    reasons.add(r.text('consequence'));
  }
  if (r.number('importance') > 0) {
    score += r.number('importance').clamp(0, 3) * weight('importance', 10);
    reasons.add('Manual importance ${r.number('importance')}');
  }
  if (r.number('snoozeCount') >= 3) {
    score += weight('snoozes', 10);
    reasons.add('Snoozed ${r.number('snoozeCount')} times');
  }
  final blocked = r.dependencies.where(activeIds.contains).toList();
  if (blocked.isNotEmpty) {
    score += weight('dependencies', 10);
    reasons.add('Depends on ${blocked.join(', ')}');
  }
  if (r.instant('updated')?.isBefore(now.subtract(const Duration(days: 60))) ??
      false) {
    score += 5;
    reasons.add('Not reviewed for 60 days');
  }
  if (r.data['priorityOverride'] is num) {
    score = r.number('priorityOverride').clamp(0, 100);
    reasons.add('Manual score override');
  }
  return RadarResult(r, score.clamp(0, 100), reasons);
}

List<RadarResult> radar(
  List<AdminRecord> records,
  DateTime now, {
  Map<String, dynamic> weights = const {},
}) {
  final active = records.where((r) => r.status == 'active').toList();
  final ids = active.map((r) => r.id).whereType<int>().toSet();
  final results = active
      .where((r) => !(r.instant('dismissUntil')?.isAfter(now) ?? false))
      .map((r) => priority(r, now, weights: weights, activeIds: ids))
      .toList();
  results.sort((a, b) {
    final score = b.score.compareTo(a.score);
    return score != 0
        ? score
        : (a.record.due ?? DateTime(2200)).compareTo(
            b.record.due ?? DateTime(2200),
          );
  });
  return results;
}
