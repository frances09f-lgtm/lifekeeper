part of '../main.dart';

/// Insights: Overview, Trends (price changes, months ahead, renewal
/// heatmap), Services (total paid per item) and Signals. Local data only.
extension InsightsView on _LifeKeeperState {
  Set<int> get demoIds => records
      .where((r) => r.flag('demo'))
      .map((r) => r.id)
      .whereType<int>()
      .toSet();

  List<Widget> insights(BuildContext context) {
    final theme = Theme.of(context);
    const tabs = ['Overview', 'Trends', 'Services', 'Signals'];
    return [
      pageHeader(
        'Insights',
        'From payments you marked paid and the dues on this phone.',
      ),
      Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? LkColors.softDark
              : LkColors.soft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            for (final t in tabs)
              Expanded(
                child: GestureDetector(
                  onTap: () => refreshState(() => insightsTab = t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: insightsTab == t
                          ? theme.cardColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      t,
                      maxLines: 1,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: insightsTab == t
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: insightsTab == t
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      ...switch (insightsTab) {
        'Trends' => trendsView(context),
        'Services' => servicesView(context),
        'Signals' => signalsView(context),
        _ => overviewView(context),
      },
    ];
  }

  Widget statBox(BuildContext context, String value, String label) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(fontSize: 10.5),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget bars(
    BuildContext context,
    List<int> values,
    List<String> labels, {
    int? highlight,
    String currency = 'INR',
  }) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final top = values.isEmpty ? 1 : max(1, values.reduce(max));
    return SizedBox(
      height: 150,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (values[i] > 0 && values.length <= 6)
                      Text(
                        compactRupees(values[i], currency),
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 0,
                          fontSize: 9.5,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Container(
                      height: max(4, 100 * values[i] / top),
                      decoration: BoxDecoration(
                        color: i == highlight
                            ? theme.colorScheme.primary
                            : (dark ? LkColors.ringDark : LkColors.ring),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      labels[i],
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String compactRupees(int minor, String currency) {
    final major = minor / currencyScale(currency);
    final sign = currency == 'INR' ? '₹' : '';
    if (major >= 100000) return '$sign${(major / 100000).toStringAsFixed(1)}L';
    if (major >= 1000) return '$sign${(major / 1000).toStringAsFixed(1)}k';
    return '$sign${major.round()}';
  }

  static const monthShort = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  List<Widget> overviewView(BuildContext context) {
    final now = DateTime.now();
    final s = monthSummary(
      records,
      payments,
      now,
      currency: homeCurrency,
      payday: payday,
    );
    final recurring = records.where(
      (r) =>
          r.status == 'active' &&
          isPayable(r) &&
          r.currency == homeCurrency &&
          !r.flag('demo'),
    );
    final monthly = recurring.fold<int>(0, (t, r) => t + monthlyCost(r));
    final spend = spending(context);
    return [
      Row(
        children: [
          Expanded(
            child: statBox(context, rupees(s.total, s.currency), 'This month'),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: statBox(context, rupees(s.perDay, s.currency), 'Per day'),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: statBox(
              context,
              rupees(monthly * 12, s.currency),
              'Recurring a year',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: statBox(
              context,
              '${recurring.where((r) => r.text('repeat', 'none') != 'none').length}',
              'Recurring items',
            ),
          ),
        ],
      ),
      ...spend.skip(1),
    ];
  }

  List<Widget> trendsView(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final cur = homeCurrency;
    final last12 = monthlyTotals(
      payments,
      cur,
      now,
      months: 12,
      demoIds: demoIds,
    );
    final prev12 = monthlyTotals(
      payments,
      cur,
      DateTime(now.year - 1, now.month),
      months: 12,
      demoIds: demoIds,
    );
    final thisYear = last12.fold<int>(0, (a, b) => a + b);
    final lastYear = prev12.fold<int>(0, (a, b) => a + b);
    final ahead = monthsAhead(records, now, months: 6, currency: cur);
    final changes = records
        .where((r) => r.status != 'archived' && priceChange(r) != null)
        .toList();
    return [
      title('Last 12 months vs the year before'),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              rupees(thisYear, cur),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              lastYear == 0
                  ? 'No payments recorded in the year before'
                  : '${thisYear >= lastYear ? '+' : '−'}${rupees((thisYear - lastYear).abs(), cur)} vs ${rupees(lastYear, cur)} the year before',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 14),
            bars(
              context,
              last12,
              [
                for (var i = 11; i >= 0; i--)
                  monthShort[DateTime(now.year, now.month - i).month - 1][0],
              ],
              highlight: 11,
              currency: cur,
            ),
          ],
        ),
      ),
      title('Months ahead', trailing: 'Forecast'),
      card(
        bars(
          context,
          ahead,
          [
            for (var i = 0; i < 6; i++)
              monthShort[DateTime(now.year, now.month + i).month - 1],
          ],
          highlight: 0,
          currency: cur,
        ),
      ),
      title('Renewal calendar', trailing: 'Next 12 weeks'),
      card(heatmap(context)),
      title('Price changes'),
      if (changes.isEmpty)
        card(
          const Text(
            'No price changes recorded yet. Editing an amount keeps its history.',
          ),
        )
      else
        for (final r in changes)
          signalTile(
            context,
            Signal(
              priceChange(r)! > 0 ? 'price_up' : 'price_down',
              r.title,
              '${priceChange(r)! > 0 ? '+' : '−'}${money(priceChange(r)!.abs(), r.currency)} per payment · now ${r.amount == null ? '—' : rupees(r.amount!, r.currency)}',
              r,
            ),
          ),
    ];
  }

  Widget heatmap(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final now = day(DateTime.now());
    final start = now.subtract(Duration(days: now.weekday - 1));
    final counts = renewalHeatmap(records, start, days: 84);
    Color shade(int n) => n == 0
        ? (dark ? const Color(0xff1f2a24) : const Color(0xffeef2ef))
        : n == 1
        ? (dark ? LkColors.ringDark : LkColors.ring)
        : n == 2
        ? (dark ? const Color(0xff6f9a7c) : const Color(0xff7aa287))
        : theme.colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(width: 22),
            for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
              Expanded(
                child: Center(
                  child: Text(
                    d,
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var w = 0; w < 12; w++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    start.add(Duration(days: w * 7)).day <= 7 || w == 0
                        ? monthShort[start.add(Duration(days: w * 7)).month -
                              1][0]
                        : '',
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
                  ),
                ),
                for (var d = 0; d < 7; d++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Builder(
                        builder: (context) {
                          final date = start.add(Duration(days: w * 7 + d));
                          final n = counts[date] ?? 0;
                          final past = date.isBefore(now);
                          return GestureDetector(
                            onTap: () => refreshState(() {
                              selected = date;
                              month = DateTime(date.year, date.month);
                              tab = 1;
                            }),
                            child: Container(
                              height: 18,
                              decoration: BoxDecoration(
                                color: past
                                    ? shade(0).withValues(alpha: 0.4)
                                    : shade(n),
                                borderRadius: BorderRadius.circular(4),
                                border: date == now
                                    ? Border.all(
                                        color: theme.colorScheme.primary,
                                        width: 1.5,
                                      )
                                    : null,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'Less',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
            ),
            const SizedBox(width: 6),
            for (final n in [0, 1, 2, 3])
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: shade(n),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            Text(
              'More renewals',
              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10.5),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> servicesView(BuildContext context) {
    final theme = Theme.of(context);
    final cur = homeCurrency;
    final totals = totalsByItem(payments, cur, demoIds: demoIds);
    final all = totals.fold<int>(0, (a, b) => a + b.value);
    return [
      title('Total paid per item', trailing: rupees(all, cur)),
      if (totals.isEmpty)
        card(
          const Text(
            'Mark payments as paid to see what each item has cost you.',
          ),
        )
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < totals.length; i++) ...[
                if (i > 0) const Divider(indent: 68),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      BrandAvatar(
                        title: totals[i].key,
                        category:
                            payments
                                    .where((p) => p['title'] == totals[i].key)
                                    .firstOrNull?['category']
                                as String? ??
                            'Bill',
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              totals[i].key,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(99),
                              child: LinearProgressIndicator(
                                value: all == 0 ? 0 : totals[i].value / all,
                                minHeight: 6,
                                backgroundColor:
                                    theme.brightness == Brightness.dark
                                    ? LkColors.softDark
                                    : LkColors.soft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            rupees(totals[i].value, cur),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${payments.where((p) => p['title'] == totals[i].key && p['currency'] == cur).length} payments',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
    ];
  }

  Widget signalTile(BuildContext context, Signal s) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final bad = s.kind != 'price_down';
    final color = bad
        ? (dark ? LkColors.dangerDark : LkColors.danger)
        : theme.colorScheme.primary;
    return Card(
      child: ListTile(
        onTap: s.record == null ? null : () => details(s.record!),
        leading: Icon(switch (s.kind) {
          'price_up' => Icons.trending_up_rounded,
          'price_down' => Icons.trending_down_rounded,
          'double' => Icons.copy_all_rounded,
          _ => Icons.event_busy_rounded,
        }, color: color),
        title: Text(
          s.title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(s.body),
        trailing: s.record == null
            ? null
            : const Icon(Icons.chevron_right_rounded),
      ),
    );
  }

  List<Widget> signalsView(BuildContext context) {
    final list = signals(records, payments, DateTime.now());
    final trials =
        records
            .where(
              (r) =>
                  r.status == 'active' &&
                  r.date('trialEnd') != null &&
                  !r.date('trialEnd')!.isBefore(day(DateTime.now())),
            )
            .toList()
          ..sort((a, b) => a.date('trialEnd')!.compareTo(b.date('trialEnd')!));
    return [
      title('Signals', trailing: list.isEmpty ? null : '${list.length}'),
      if (list.isEmpty)
        card(
          const Text(
            'No price changes, missed payments or double charges found.',
          ),
        )
      else
        for (final s in list) signalTile(context, s),
      title(
        'Cancel in time',
        trailing: trials.isEmpty ? null : '${trials.length} trials',
      ),
      if (trials.isEmpty)
        card(
          const Text(
            'No free trials tracked. Add a trial end date to any subscription.',
          ),
        )
      else
        for (final r in trials)
          Card(
            child: ListTile(
              onTap: () => details(r),
              leading: BrandAvatar(
                title: r.title,
                category: r.category,
                size: 36,
              ),
              title: Text(
                r.title,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                'Trial ends ${prettyDate(r.date('trialEnd'))}${r.data['priceAfterTrial'] is num ? ' · then ${rupees(r.number('priceAfterTrial'), r.currency)}' : ''}',
              ),
            ),
          ),
    ];
  }
}
