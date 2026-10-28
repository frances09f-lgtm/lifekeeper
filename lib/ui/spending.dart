part of '../main.dart';

extension SpendingView on _LifeKeeperState {
  List<Widget> spending(BuildContext context) {
    final currencies = payments.map((p) => p['currency'] as String).toSet()
      ..add('INR');
    final chosen = settings['spendingCurrency'] as String? ?? 'INR';
    final currency = currencies.contains(chosen) ? chosen : 'INR';
    final actual = realPayments(
      payments,
      currency,
      demoIds: records.where((r) => r.flag('demo')).map((r) => r.id!).toSet(),
    );
    final now = DateTime.now();
    List<Map<String, Object?>> forMonth(DateTime date) => actual.where((p) {
      final at = DateTime.parse(p['paidAt'] as String).toLocal();
      return at.year == date.year && at.month == date.month;
    }).toList();
    final current = forMonth(now);
    final paid = paymentTotal(current);
    final budgets = Map<String, dynamic>.from(
      settings['budgets'] as Map? ?? {},
    );
    final budget = (budgets[currency] as num?)?.toInt() ?? 0;
    final bars = [
      for (var i = 5; i >= 0; i--)
        paymentTotal(forMonth(DateTime(now.year, now.month - i))),
    ];
    final categories = current.map((p) => p['category'] as String).toSet();
    final theme = Theme.of(context);
    final paidLabel = currency == 'INR'
        ? rupees(paid, currency)
        : money(paid, currency);
    String amt(int v) =>
        currency == 'INR' ? rupees(v, currency) : money(v, currency);
    return [
      sectionHeader(
        context,
        'Spending',
        trailing: currencies.length > 1
            ? PopupMenuButton<String>(
                tooltip: 'Currency',
                initialValue: currency,
                onSelected: (v) =>
                    action(() => repo.setting('spendingCurrency', v)),
                itemBuilder: (_) => [
                  for (final c in currencies.toList()..sort())
                    PopupMenuItem(value: c, child: Text(c)),
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
                      Text(currency, style: theme.textTheme.labelLarge),
                      const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                    ],
                  ),
                ),
              )
            : null,
      ),
      const SizedBox(height: 6),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paid this month',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              paidLabel,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              budget == 0
                  ? 'No monthly budget set'
                  : '${amt((budget - paid).clamp(0, 1 << 52))} left of ${amt(budget)} budget',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (budget > 0) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 10,
                  value: (paid / budget).clamp(0.0, 1.0),
                  color: paid > budget
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  backgroundColor: theme.brightness == Brightness.dark
                      ? LkColors.softDark
                      : LkColors.soft,
                ),
              ),
            ],
            const SizedBox(height: 6),
            TextButton(
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 36),
              ),
              onPressed: () async {
                final input = await prompt(
                  context,
                  'Monthly $currency budget',
                  'Amount',
                  initial: budget == 0
                      ? ''
                      : (budget / currencyScale(currency)).toString(),
                );
                if (input != null) {
                  final value = minorAmount(input, currency: currency);
                  if (value == null) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Invalid budget amount')),
                      );
                    return;
                  }
                  budgets[currency] = value;
                  await action(() => repo.setting('budgets', budgets));
                }
              },
              child: Text(budget == 0 ? 'Set monthly budget' : 'Change budget'),
            ),
          ],
        ),
      ),
      sectionHeader(context, 'Last six months'),
      const SizedBox(height: 6),
      card(
        this.bars(
          context,
          bars,
          [
            for (var i = 0; i < 6; i++)
              InsightsView.monthShort[DateTime(
                    now.year,
                    now.month - 5 + i,
                  ).month -
                  1],
          ],
          highlight: 5,
          currency: currency,
        ),
      ),
      sectionHeader(context, 'Where it went'),
      const SizedBox(height: 6),
      card(
        categories.isEmpty
            ? const Text('No paid items this month')
            : Column(
                children: [
                  for (final category in categories)
                    Builder(
                      builder: (context) {
                        final v = paymentTotal(
                          current
                              .where((p) => p['category'] == category)
                              .toList(),
                        );
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      category,
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    amt(v),
                                    style: theme.textTheme.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(99),
                                child: LinearProgressIndicator(
                                  minHeight: 6,
                                  value: paid == 0 ? 0 : v / paid,
                                  backgroundColor:
                                      theme.brightness == Brightness.dark
                                      ? LkColors.softDark
                                      : LkColors.soft,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
      ),
      sectionHeader(context, 'Payment history'),
      const SizedBox(height: 6),
      if (actual.isEmpty)
        card(const Text('No payments marked paid yet'))
      else
        Card(
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < actual.length; i++) ...[
                if (i > 0) const Divider(indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              actual[i]['title'] as String,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'Paid ${prettyDate(DateTime.tryParse(actual[i]['paidAt'] as String? ?? '')?.toLocal())}',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      Text(
                        amt((actual[i]['amount'] as num).toInt()),
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
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
}
