part of '../main.dart';

/// Subby-style Home: one clear total, alerts with one-tap fixes, next
/// payments carousel, then the full list. Everything is computed locally.
extension HomeView on _LifeKeeperState {
  String get homeCurrency {
    final chosen = settings['spendingCurrency'] as String? ?? 'INR';
    return chosen;
  }

  int? get payday => (settings['payday'] as num?)?.toInt();

  List<Widget> home(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final nowTime = DateTime.now();
    final now = day(nowTime);
    final active = records.where((r) => r.status == 'active').toList();
    final summary = monthSummary(
      records,
      payments,
      nowTime,
      currency: homeCurrency,
      payday: payday,
    );
    if (records.isEmpty) return emptyHome(context, summary);
    final alerts = homeAlerts(records, nowTime);
    final next = nextPayments(records, nowTime);
    final ranked = radar(
      records,
      nowTime,
      weights: Map<String, dynamic>.from(settings['weights'] as Map? ?? {}),
    ).where((r) => !isPayable(r.record) || r.score >= 50).toList();
    final visible = records
        .where(
          (r) =>
              (status == 'All' || r.status == status) &&
              (category == 'All' || r.category == category) &&
              (search.isEmpty ||
                  r.data.values
                      .join(' ')
                      .toLowerCase()
                      .contains(search.toLowerCase())),
        )
        .toList();
    if (sort == 'Title') {
      visible.sort((a, b) => a.title.compareTo(b.title));
    } else if (sort == 'Priority') {
      visible.sort(
        (a, b) =>
            priority(b, nowTime).score.compareTo(priority(a, nowTime).score),
      );
    } else if (sort == 'Amount') {
      visible.sort((a, b) => (b.amount ?? 0).compareTo(a.amount ?? 0));
    } else {
      visible.sort(
        (a, b) => (a.due ?? DateTime(2200)).compareTo(b.due ?? DateTime(2200)),
      );
    }
    List<AdminRecord> dueOn(DateTime d) =>
        active.where((r) => r.text('due') == dateText(d)).toList();
    final overlaps = active
        .map((r) => r.text('due'))
        .where((d) => d.isNotEmpty)
        .toSet()
        .where((d) => active.where((r) => r.text('due') == d).length > 1)
        .toList();
    return [
      const SizedBox(height: 4),
      totalCard(context, summary),
      if (alerts.isNotEmpty) ...[
        const SizedBox(height: 12),
        for (final a in alerts) alertCard(context, a),
      ],
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: scan,
              icon: const Icon(Icons.document_scanner_outlined, size: 20),
              label: const Text('Scan bill'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: quick,
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: const Text('Quick add'),
            ),
          ),
        ],
      ),
      title(
        'Next payments',
        trailing: next.isEmpty ? null : '${next.length} upcoming',
      ),
      if (next.isEmpty)
        card(
          Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, color: scheme.primary),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Nothing to pay yet. Add a bill or subscription to see it here.',
                ),
              ),
            ],
          ),
        )
      else
        SizedBox(
          height: 178,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: next.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => nextCard(context, next[i]),
          ),
        ),
      if (ranked.isNotEmpty) ...[
        title('Needs attention', trailing: '${ranked.length} items'),
        for (final r in ranked.take(3)) tile(r.record, result: r),
      ],
      title('All records', trailing: '${visible.length} shown'),
      TextField(
        decoration: const InputDecoration(
          hintText: 'Search your records',
          prefixIcon: Icon(Icons.search_rounded, size: 20),
        ),
        onChanged: (v) => refreshState(() => search = v),
      ),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            dropdown(
              category,
              ['All', ...records.map((r) => r.category).toSet()],
              (v) => refreshState(() => category = v),
              label: 'Category',
            ),
            const SizedBox(width: 8),
            dropdown(
              status,
              ['All', 'active', 'completed', 'archived'],
              (v) => refreshState(() => status = v),
              label: 'Status',
            ),
            const SizedBox(width: 8),
            dropdown(
              sort,
              ['Due date', 'Amount', 'Title', 'Priority'],
              (v) => refreshState(() => sort = v),
              label: 'Sort',
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      if (visible.isEmpty)
        card(const Text('No records match these filters'))
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const Divider(indent: 68),
                listRow(context, visible[i]),
              ],
            ],
          ),
        ),
      title('Next 7 days'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < 7; i++) ...[
              if (i > 0) const Divider(),
              InkWell(
                onTap: () => refreshState(() {
                  selected = now.add(Duration(days: i));
                  month = DateTime(selected.year, selected.month);
                  tab = 1;
                }),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 92,
                        child: Text(
                          i == 0
                              ? 'Today'
                              : i == 1
                              ? 'Tomorrow'
                              : shortDay(now.add(Duration(days: i))),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          dueOn(now.add(Duration(days: i))).isEmpty
                              ? 'No due items'
                              : dueOn(now.add(Duration(days: i)))
                                    .map((r) => r.title)
                                    .join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: dueOn(now.add(Duration(days: i))).isEmpty
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      title('Widget preview', trailing: 'Preview only'),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Not a phone home-screen widget',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (next.isEmpty)
              const Text('Nothing upcoming')
            else
              for (final n in next.take(3))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.record.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(prettyDate(n.due), style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
          ],
        ),
      ),
      if (active.any((r) => r.dependencies.isNotEmpty) ||
          overlaps.isNotEmpty) ...[
        title('Dependencies and overlaps'),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in active.where((r) => r.dependencies.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${r.title} depends on ${r.dependencies.map((id) => records.where((x) => x.id == id).firstOrNull?.title ?? 'missing record').join(', ')}',
                  ),
                ),
              for (final d in overlaps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Text(
                    '${prettyDate(strictDate(d))}: ${active.where((r) => r.text('due') == d).map((r) => r.title).join(', ')}',
                  ),
                ),
            ],
          ),
        ),
      ],
      Padding(
        padding: const EdgeInsets.only(top: 16, left: 4),
        child: Text(
          '${active.length} active items · ${records.where((r) => r.category == 'Warranty').length} warranties · All data stays on this phone',
          style: theme.textTheme.bodySmall,
        ),
      ),
    ];
  }

  /// First-run Home: the same cards as the full Home (total, alert, next
  /// payments row, list) filled with starting points instead of records.
  List<Widget> emptyHome(BuildContext context, MonthSummary summary) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 4),
      totalCard(context, summary),
      const SizedBox(height: 12),
      tipCard(
        context,
        key: const Key('home-welcome'),
        icon: Icons.notifications_active_outlined,
        title: 'Never miss a due date',
        body:
            'Add a bill and get a reminder before it is due. It all stays on this phone.',
        action: 'Add bill',
        onPressed: () => edit(),
      ),
      const SizedBox(height: 2),
      Row(
        children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: scan,
              icon: const Icon(Icons.document_scanner_outlined, size: 20),
              label: const Text('Scan bill'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: quick,
              icon: const Icon(Icons.bolt_rounded, size: 20),
              label: const Text('Quick add'),
            ),
          ),
        ],
      ),
      title('Next payments', trailing: 'Start here'),
      SizedBox(
        height: 178,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            starterCard(
              context,
              key: const Key('home-add-first'),
              icon: Icons.add_rounded,
              chip: 'Step 1',
              title: 'Add your first bill',
              subtitle: 'Rent, EMI, power',
              action: 'Add bill',
              onPressed: () => edit(),
            ),
            const SizedBox(width: 10),
            starterCard(
              context,
              icon: Icons.document_scanner_outlined,
              chip: 'Fastest',
              title: 'Scan a bill',
              subtitle: 'Reads amount + date',
              action: 'Scan',
              onPressed: scan,
            ),
            const SizedBox(width: 10),
            starterCard(
              context,
              icon: Icons.hourglass_bottom_rounded,
              chip: 'Trials',
              title: 'Track a free trial',
              subtitle: 'Cancel in time',
              action: 'Add trial',
              onPressed: () => edit(initial: {'category': 'Subscription'}),
            ),
          ],
        ),
      ),
      title('Popular to add', trailing: 'Tap to add'),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var i = 0; i < starters.length; i++) ...[
              if (i > 0) const Divider(indent: 68),
              starterRow(context, starters[i]),
            ],
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 16, left: 4),
        child: Text(
          'No account, no bank login · All data stays on this phone',
          style: theme.textTheme.bodySmall,
        ),
      ),
    ];
  }

  static const starters = <(String, String, String, String)>[
    ('Electricity', 'Bill', 'monthly', 'Monthly'),
    ('Jio recharge', 'Bill', 'monthly', 'Monthly'),
    ('Netflix', 'Subscription', 'monthly', 'Monthly'),
    ('Rent', 'Bill', 'monthly', 'Monthly'),
    ('Car insurance', 'Insurance', 'yearly', 'Yearly'),
    ('Phone warranty', 'Warranty', 'none', 'Warranty'),
  ];

  Widget tipCard(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required String title,
    required String body,
    required String action,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      key: key,
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: dark ? LkColors.softDark : LkColors.soft,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Row(
          children: [
            Icon(icon, color: scheme.primary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: dark ? Colors.black : Colors.white,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: onPressed,
              child: Text(action),
            ),
          ],
        ),
      ),
    );
  }

  Widget starterCard(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required String chip,
    required String title,
    required String subtitle,
    required String action,
    required VoidCallback onPressed,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final soft = dark ? LkColors.softDark : LkColors.soft;
    return SizedBox(
      key: key,
      width: 172,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, size: 19, color: scheme.primary),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: soft,
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        chip,
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 0,
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: onPressed,
                    child: Text(action),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget starterRow(
    BuildContext context,
    (String, String, String, String) s,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: () => edit(
        initial: {
          'title': s.$1,
          'category': s.$2,
          if (s.$3 != 'none') 'repeat': s.$3,
        },
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            BrandAvatar(title: s.$1, category: s.$2),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.$1,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(s.$2, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 18, color: scheme.primary),
                    const SizedBox(width: 2),
                    Text(
                      'Add',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: dark ? LkColors.softDark : LkColors.soft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    s.$4,
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String periodName(MonthSummary s) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    if (s.start.day == 1) return '${months[s.start.month - 1]} total';
    return 'This pay period';
  }

  Widget totalCard(BuildContext context, MonthSummary s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final change = s.change;
    final up = change > 0;
    final changeColor = s.previous == 0
        ? scheme.onSurfaceVariant
        : up
        ? (dark ? LkColors.dangerDark : LkColors.danger)
        : scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    periodName(s).toUpperCase(),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
                if (s.start.day != 1)
                  Text(
                    '${shortDay(s.start)} – ${shortDay(s.end.subtract(const Duration(days: 1)))}',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              rupees(s.total, s.currency),
              key: const Key('home-total'),
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: -1.2,
                fontSize: 40,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              records.isEmpty
                  ? 'No bills yet · ${rupees(0, s.currency)} a day'
                  : '${s.activeCount} active · ${rupees(s.perDay, s.currency)} a day',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: s.paidShare,
                minHeight: 10,
                backgroundColor: dark ? LkColors.softDark : LkColors.soft,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: legend(
                    context,
                    scheme.primary,
                    'Paid',
                    rupees(s.paid, s.currency),
                  ),
                ),
                Expanded(
                  child: legend(
                    context,
                    dark ? LkColors.ringDark : LkColors.ring,
                    'Left to pay',
                    rupees(s.left, s.currency),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  s.previous == 0
                      ? Icons.remove_rounded
                      : up
                      ? Icons.trending_up_rounded
                      : Icons.trending_down_rounded,
                  size: 18,
                  color: changeColor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    records.isEmpty
                        ? 'Your first month starts here'
                        : s.previous == 0
                        ? 'Nothing paid last ${s.start.day == 1 ? 'month' : 'period'} to compare'
                        : '${up
                              ? '+'
                              : change < 0
                              ? '−'
                              : ''}${rupees(change.abs(), s.currency)}${s.changePercent == null ? '' : ' (${s.changePercent!.abs().round()}%)'} vs last ${s.start.day == 1 ? 'month' : 'period'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: changeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget legend(BuildContext context, Color color, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: theme.textTheme.bodySmall),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget alertCard(BuildContext context, HomeAlert a) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final danger = a.kind == 'overdue';
    final bg = danger
        ? (dark ? const Color(0xff3a2420) : const Color(0xfffbeeeb))
        : a.kind == 'trial'
        ? (dark ? const Color(0xff383120) : const Color(0xfffbf3e2))
        : (dark ? LkColors.softDark : LkColors.soft);
    final fg = danger
        ? (dark ? LkColors.dangerDark : LkColors.danger)
        : a.kind == 'trial'
        ? (dark ? const Color(0xffe9c77b) : const Color(0xff8a5a00))
        : scheme.primary;
    final icon = switch (a.kind) {
      'trial' => Icons.hourglass_bottom_rounded,
      'overdue' => Icons.error_outline_rounded,
      _ => Icons.trending_up_rounded,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
        child: Row(
          children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    a.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: fg,
                foregroundColor: dark ? Colors.black : Colors.white,
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              onPressed: () => action(() async {
                switch (a.kind) {
                  case 'overdue':
                    for (final r in a.records) {
                      if (r.id != null) await repo.complete(r.id!);
                    }
                  case 'trial':
                    for (final r in a.records) {
                      if (r.id != null) {
                        await repo.patch(r.id!, {'trialKept': true});
                      }
                    }
                  default:
                    for (final r in a.records) {
                      if (r.id != null) {
                        await repo.patch(r.id!, {
                          'priceSeen': lastPriceChangeAt(r),
                        });
                      }
                    }
                }
              }),
              child: Text(a.action),
            ),
          ],
        ),
      ),
    );
  }

  Widget brandAvatar(AdminRecord r, {double size = 40}) =>
      BrandAvatar(title: r.title, category: r.category, size: size);

  Widget nextCard(BuildContext context, NextPayment n) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final late = n.days < 0;
    final r = n.record;
    return SizedBox(
      width: 172,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => details(r),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    brandAvatar(r, size: 34),
                    const SizedBox(width: 6),
                    const Spacer(),
                    Flexible(
                      flex: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: late
                              ? (dark
                                    ? const Color(0xff3a2420)
                                    : const Color(0xfffbeeeb))
                              : (dark ? LkColors.softDark : LkColors.soft),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          n.days < 0 ? 'Overdue' : inDays(n.days),
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 0,
                            color: late
                                ? (dark ? LkColors.dangerDark : LkColors.danger)
                                : scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  r.amount == null
                      ? 'No amount'
                      : rupees(r.amount!, r.currency),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: r.id == null
                        ? null
                        : () => action(() async {
                            await repo.complete(r.id!);
                          }),
                    child: const Text('Mark paid'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String cycleLabel(AdminRecord r) {
    final n = r.number('interval', 1);
    return switch (r.text('repeat', 'none')) {
      'daily' => n > 1 ? 'Every $n days' : 'Daily',
      'weekly' => n > 1 ? 'Every $n weeks' : 'Weekly',
      'monthly' =>
        n == 3
            ? 'Quarterly'
            : n > 1
            ? 'Every $n months'
            : 'Monthly',
      'yearly' => n > 1 ? 'Every $n years' : 'Yearly',
      'custom' => 'Every $n days',
      _ => r.category,
    };
  }

  Widget listRow(BuildContext context, AdminRecord r) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final d = r.due == null
        ? null
        : day(r.due!).difference(day(DateTime.now())).inDays;
    final trial = r.date('trialEnd');
    final late = r.status == 'active' && d != null && d < 0;
    return InkWell(
      onTap: () => details(r),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            brandAvatar(r),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    r.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    r.status != 'active'
                        ? capitalize(r.status)
                        : trial != null && !trial.isBefore(day(DateTime.now()))
                        ? 'Free trial · ends ${prettyDate(trial)}'
                        : d == null
                        ? 'No date'
                        : '${inDays(d)} · ${prettyDate(r.due)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: late
                          ? (dark ? LkColors.dangerDark : LkColors.danger)
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  r.amount == null ? '—' : rupees(r.amount!, r.currency),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: dark ? LkColors.softDark : LkColors.soft,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    cycleLabel(r),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0,
                      color: scheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Offline "logo": a bundled colour + initial for well-known Indian
/// services, otherwise a sage tile with the category icon or initials.
class BrandAvatar extends StatelessWidget {
  final String title, category;
  final double size;
  const BrandAvatar({
    super.key,
    required this.title,
    required this.category,
    this.size = 40,
  });

  static const brands = <String, (int, String)>{
    'netflix': (0xffe50914, 'N'),
    'spotify': (0xff1db954, 'S'),
    'jio': (0xff0f3cc9, 'Jio'),
    'airtel': (0xffe40000, 'a'),
    'vi ': (0xffee2a24, 'Vi'),
    'hotstar': (0xff0c1a4b, 'D+'),
    'prime': (0xff00a8e1, 'P'),
    'amazon': (0xffff9900, 'a'),
    'youtube': (0xffff0000, 'YT'),
    'google': (0xff4285f4, 'G'),
    'apple': (0xff111111, ''),
    'icloud': (0xff3693f3, 'iC'),
    'swiggy': (0xfffc8019, 'S'),
    'zomato': (0xffe23744, 'z'),
    'hdfc': (0xff004c8f, 'H'),
    'icici': (0xffb02a30, 'i'),
    'sbi': (0xff22409a, 'SBI'),
    'lic': (0xffffcb05, 'LIC'),
    'tata': (0xff2b4c9b, 'T'),
    'bescom': (0xff2f6f3e, 'B'),
    'electricity': (0xfff2b01e, 'E'),
    'gas': (0xff2f7fb8, 'G'),
    'rent': (0xff5c6b73, 'R'),
    'gym': (0xff3a3a3a, 'G'),
    'chatgpt': (0xff10a37f, 'AI'),
    'openai': (0xff10a37f, 'AI'),
    'microsoft': (0xff00a4ef, 'M'),
    'adobe': (0xffda1f26, 'A'),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final lower = '${title.toLowerCase()} ';
    (int, String)? brand;
    for (final e in brands.entries) {
      if (lower.contains(e.key)) {
        brand = e.value;
        break;
      }
    }
    final icon = switch (category) {
      'Warranty' => Icons.verified_user_outlined,
      'ID' => Icons.badge_outlined,
      'Policy' => Icons.shield_outlined,
      'Vehicle' => Icons.directions_car_outlined,
      'Insurance' => Icons.health_and_safety_outlined,
      _ => null,
    };
    final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final initials = words.isEmpty
        ? '?'
        : words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    final bg = brand != null
        ? Color(brand.$1)
        : (dark ? LkColors.softDark : LkColors.soft);
    final fg = brand != null
        ? (brand.$1 == 0xffffcb05 || brand.$1 == 0xffff9900
              ? Colors.black
              : Colors.white)
        : (dark ? LkColors.accentDark : LkColors.accent);
    final label = brand?.$2 ?? initials;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: brand == null && icon != null
          ? Icon(icon, color: fg, size: size * 0.5)
          : brand != null && label.isEmpty
          ? Icon(Icons.apple, color: fg, size: size * 0.55)
          : Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                fontSize: size * (label.length > 2 ? 0.28 : 0.38),
                letterSpacing: -0.3,
              ),
            ),
    );
  }
}
