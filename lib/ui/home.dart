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
    final overlaps = active
        .map((r) => r.text('due'))
        .where((d) => d.isNotEmpty)
        .toSet()
        .where((d) => active.where((r) => r.text('due') == d).length > 1)
        .toList();
    final next30 = next.where((n) => n.days <= 30).toList();
    final next30Total = next30.fold<int>(
      0,
      (s, n) =>
          s + (n.record.currency == homeCurrency ? (n.record.amount ?? 0) : 0),
    );
    return [
      const SizedBox(height: 4),
      totalCard(context, summary),
      if (alerts.isNotEmpty) ...[
        const SizedBox(height: 14),
        for (final a in alerts) alertCard(context, a),
      ],
      sectionHeader(
        context,
        'Next payments',
        action: next.isEmpty ? null : 'See all',
        onAction: () => refreshState(() => tab = 1),
      ),
      if (next.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 2),
          child: Text(
            next30.isEmpty
                ? '${next.length} coming up'
                : 'Next 30 days: ${rupees(next30Total, homeCurrency)} across ${next30.length} ${next30.length == 1 ? 'charge' : 'charges'}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
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
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: next.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, i) => nextCard(context, next[i]),
          ),
        ),
      sectionHeader(
        context,
        'Your bills',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              tooltip: 'Sort',
              initialValue: sort,
              onSelected: (v) => refreshState(() => sort = v),
              itemBuilder: (_) => [
                for (final s in ['Due date', 'Amount', 'Title', 'Priority'])
                  PopupMenuItem(value: s, child: Text(s)),
              ],
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  border: Border.all(color: theme.dividerColor),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      sort == 'Due date' ? 'Next payment' : sort,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Search',
              visualDensity: VisualDensity.compact,
              onPressed: () => refreshState(() {
                searchOpen = !searchOpen;
                if (!searchOpen) search = '';
              }),
              icon: Icon(
                searchOpen ? Icons.close_rounded : Icons.search_rounded,
                size: 22,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Filter',
              icon: Icon(
                Icons.tune_rounded,
                size: 21,
                color: category != 'All' || status != 'active'
                    ? scheme.primary
                    : null,
              ),
              onSelected: (v) => refreshState(() {
                if (v.startsWith('s:')) status = v.substring(2);
                if (v.startsWith('c:')) category = v.substring(2);
              }),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  enabled: false,
                  height: 32,
                  child: Text('Status'),
                ),
                for (final s in ['active', 'completed', 'archived', 'All'])
                  CheckedPopupMenuItem(
                    value: 's:$s',
                    checked: status == s,
                    child: Text(capitalize(s)),
                  ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  enabled: false,
                  height: 32,
                  child: Text('Category'),
                ),
                for (final c in [
                  'All',
                  ...records.map((r) => r.category).toSet(),
                ])
                  CheckedPopupMenuItem(
                    value: 'c:$c',
                    checked: category == c,
                    child: Text(c),
                  ),
              ],
            ),
          ],
        ),
      ),
      if (searchOpen) ...[
        TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Search your bills',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
          ),
          onChanged: (v) => refreshState(() => search = v),
        ),
        const SizedBox(height: 12),
      ],
      if (visible.isEmpty)
        card(const Text('No records match these filters'))
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0) const Divider(indent: 72, endIndent: 16),
                listRow(context, visible[i]),
              ],
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
        padding: const EdgeInsets.only(top: 18, left: 4),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline_rounded,
              size: 14,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${active.length} active · ${records.where((r) => r.category == 'Warranty').length} warranties · All data stays on this phone',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    ];
  }

  /// Section header in the Subby style: bold title, optional link or
  /// trailing controls on the right.
  Widget sectionHeader(
    BuildContext context,
    String text, {
    String? action,
    VoidCallback? onAction,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 6, left: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 21,
                letterSpacing: -0.4,
              ),
            ),
          ),
          if (trailing != null) trailing,
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 36),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
              child: Text(action),
            ),
        ],
      ),
    );
  }

  /// First-run Home: the real (zero) total card and one prompt. No example
  /// bills, suggestions or placeholder amounts.
  List<Widget> emptyHome(BuildContext context, MonthSummary summary) {
    final theme = Theme.of(context);
    return [
      const SizedBox(height: 4),
      totalCard(context, summary),
      const SizedBox(height: 12),
      tipCard(
        context,
        key: const Key('home-add-first'),
        icon: Icons.add_circle_outline_rounded,
        title: 'Add your first bill',
        body: 'Get a reminder before it is due. It all stays on this phone.',
        action: 'Add bill',
        onPressed: () => edit(),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Text(
          'No account, no bank login · All data stays on this phone',
          style: theme.textTheme.bodySmall,
        ),
      ),
    ];
  }

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
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: scheme.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              body,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: dark ? scheme.primary : LkColors.ink,
                foregroundColor: dark ? Colors.black : Colors.white,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              onPressed: onPressed,
              child: Text(action),
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

  /// Annualised cost of active recurring payable records, in minor units.
  int yearlyCost(String currency) => records
      .where(
        (r) =>
            r.status == 'active' &&
            isPayable(r) &&
            r.currency == currency &&
            !r.flag('demo'),
      )
      .fold<int>(0, (s, r) => s + monthlyCost(r) * 12);

  Widget periodToggle(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    Widget seg(String label, bool yearly) {
      final on = homeYearly == yearly;
      return GestureDetector(
        onTap: () => refreshState(() => homeYearly = yearly),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: on ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(99),
            boxShadow: on && !dark
                ? const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: on ? FontWeight.w700 : FontWeight.w600,
              color: on ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: dark ? LkColors.softDark : LkColors.soft,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [seg('Monthly cost', false), seg('Yearly cost', true)],
      ),
    );
  }

  Widget bigAmount(BuildContext context, int minor, String currency) {
    final theme = Theme.of(context);
    final whole = rupees(minor - minor % 100, currency);
    final paise = (minor % 100).toString().padLeft(2, '0');
    final big = theme.textTheme.displaySmall?.copyWith(
      fontWeight: FontWeight.w800,
      letterSpacing: -1.5,
      fontSize: 42,
      height: 1.1,
    );
    return Text.rich(
      key: const Key('home-total'),
      TextSpan(
        children: [
          TextSpan(text: whole, style: big),
          if (currency == 'INR')
            TextSpan(
              text: '.$paise',
              style: big?.copyWith(
                fontSize: 24,
                letterSpacing: -0.5,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget totalCard(BuildContext context, MonthSummary s) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final yearly = homeYearly && records.isNotEmpty;
    final year = yearlyCost(s.currency);
    final now = DateTime.now();
    final paidYear = paidBetween(
      payments,
      s.currency,
      DateTime(now.year),
      DateTime(now.year + 1),
    );
    final total = yearly ? year : s.total;
    final paid = yearly ? paidYear : s.paid;
    final left = yearly ? (year - paidYear).clamp(0, 1 << 52) : s.left;
    final change = s.change;
    final up = change > 0;
    const months = [
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
    final prevName = s.start.day == 1
        ? months[(s.start.month + 10) % 12]
        : 'last period';
    final good = dark ? const Color(0xff9fd3a8) : const Color(0xff2f7a4c);
    final bad = dark ? LkColors.dangerDark : LkColors.danger;
    final paidColor = scheme.primary;
    final leftColor = dark ? const Color(0xff7d9aa3) : const Color(0xff46666f);
    final history = monthlyTotals(payments, s.currency, now, months: 6);
    history[history.length - 1] = s.total;
    final paidFlex = total == 0 ? 0 : (paid * 1000 / total).round();
    final leftFlex = total == 0 ? 1000 : 1000 - paidFlex;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: periodToggle(context),
                  ),
                ),
                const SizedBox(width: 8),
                if (!yearly &&
                    records.isNotEmpty &&
                    s.previous != 0 &&
                    change != 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: (up ? bad : good).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${up ? '↑' : '↓'} ${rupees(change.abs(), s.currency)} vs $prevName',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: up ? bad : good,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            bigAmount(context, total, s.currency),
            const SizedBox(height: 8),
            Text(
              records.isEmpty
                  ? 'No bills yet · ${rupees(0, s.currency)} a day'
                  : '${s.activeCount} active ${s.activeCount == 1 ? 'bill' : 'bills'}',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.8),
              ),
            ),
            if (records.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: yearly
                          ? rupees((year / 12).round(), s.currency)
                          : rupees(s.perDay, s.currency),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: yearly ? ' a month' : ' a day'),
                  ],
                ),
                style: theme.textTheme.bodyLarge,
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: legend(
                      context,
                      paidColor,
                      yearly ? 'Paid this year' : 'Paid',
                      rupees(paid, s.currency),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: legend(
                      context,
                      leftColor,
                      yearly ? 'Rest of year' : 'Left to pay',
                      rupees(left, s.currency),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 10,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (paidFlex > 0)
                    Expanded(
                      flex: paidFlex,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: paidColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                  if (paidFlex > 0 && leftFlex > 0) const SizedBox(width: 4),
                  if (leftFlex > 0)
                    Expanded(
                      flex: leftFlex,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: total == 0
                              ? (dark ? LkColors.softDark : LkColors.soft)
                              : leftColor,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              yearly
                  ? 'Jan 1 to Dec 31 · projected from your repeating bills'
                  : '${s.start.day} ${months[s.start.month - 1]} to ${s.end.subtract(const Duration(days: 1)).day} ${months[s.end.subtract(const Duration(days: 1)).month - 1]}',
              style: theme.textTheme.bodySmall,
            ),
            if (!yearly &&
                history
                    .take(history.length - 1)
                    .where((v) => v > 0)
                    .isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 70,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < history.length; i++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Flexible(
                                child: FractionallySizedBox(
                                  heightFactor: () {
                                    final top = history.fold<int>(
                                      0,
                                      (a, b) => a > b ? a : b,
                                    );
                                    if (top == 0) return 0.08;
                                    final f = history[i] / top;
                                    return f < 0.08 ? 0.08 : f;
                                  }(),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: i == history.length - 1
                                          ? paidColor
                                          : (dark
                                                ? LkColors.ringDark
                                                : const Color(0xffa3b1a6)),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                months[(now.month - 6 + i + 12) % 12],
                                style: theme.textTheme.labelSmall?.copyWith(
                                  letterSpacing: 0,
                                  fontWeight: i == history.length - 1
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                  color: i == history.length - 1
                                      ? scheme.onSurface
                                      : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget legend(BuildContext context, Color color, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
        ),
        Text(
          value,
          maxLines: 1,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w800,
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
        ? (dark ? const Color(0xff3a2420) : const Color(0xfffaebe6))
        : a.kind == 'trial'
        ? (dark ? const Color(0xff383120) : const Color(0xfff6ecd9))
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
          borderRadius: BorderRadius.circular(22),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    a.title,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              a.body,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: dark ? fg : LkColors.ink,
                    foregroundColor: dark ? Colors.black : Colors.white,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 18),
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
                const SizedBox(width: 6),
                if (a.records.isNotEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurface,
                      minimumSize: const Size(0, 40),
                    ),
                    onPressed: () => a.records.length == 1
                        ? details(a.records.first)
                        : refreshState(() => tab = 1),
                    child: Text(a.records.length == 1 ? 'See bill' : 'See all'),
                  ),
              ],
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
    final soon = n.days <= 1;
    final r = n.record;
    final chipBg = late
        ? (dark ? const Color(0xff3a2420) : const Color(0xfffaebe6))
        : soon
        ? (dark ? const Color(0xff383120) : const Color(0xfff6ecd9))
        : (dark ? LkColors.softDark : LkColors.soft);
    final chipFg = late
        ? (dark ? LkColors.dangerDark : LkColors.danger)
        : soon
        ? (dark ? const Color(0xffe9c77b) : const Color(0xff8a5a00))
        : scheme.primary;
    return SizedBox(
      width: 158,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => details(r),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                brandAvatar(r, size: 42),
                const SizedBox(height: 12),
                Text(
                  r.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  r.amount == null
                      ? 'No amount'
                      : rupees(r.amount!, r.currency),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    late ? 'Overdue' : inDays(n.days),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0,
                      color: chipFg,
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 36),
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: r.id == null
                        ? null
                        : () => action(() async {
                            await repo.complete(r.id!);
                          }),
                    icon: const Icon(Icons.check_rounded, size: 16),
                    label: const Text('Mark paid'),
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
    final onTrial =
        r.status == 'active' &&
        trial != null &&
        !trial.isBefore(day(DateTime.now()));
    final late = r.status == 'active' && d != null && d < 0;
    final today = r.status == 'active' && d == 0;
    final when = d == null
        ? 'No date'
        : d == 0
        ? 'Due today'
        : d < 0
        ? inDays(d)
        : 'Due ${inDays(d).toLowerCase()}';
    final sub = r.status != 'active'
        ? capitalize(r.status)
        : onTrial
        ? 'Free trial · ends ${trial.day} ${InsightsView.monthShort[trial.month - 1]}'
        : d == null
        ? '${r.category} · No date'
        : '$when · ${r.due!.day} ${InsightsView.monthShort[r.due!.month - 1]} · ${r.category}';
    return InkWell(
      onTap: () => details(r),
      child: Container(
        color: late
            ? (dark ? const Color(0xff2e211d) : const Color(0xfffcf1ee))
            : today
            ? (dark ? const Color(0xff2f2a1d) : const Color(0xfffaf3e6))
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            brandAvatar(r, size: 42),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          r.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (onTrial) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            'TRIAL',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimary,
                              fontSize: 9,
                              letterSpacing: 0.4,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12.5,
                      color: late
                          ? (dark ? LkColors.dangerDark : LkColors.danger)
                          : null,
                      fontWeight: late || today ? FontWeight.w600 : null,
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
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: Text(
                    cycleLabel(r),
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 0,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
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
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
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
