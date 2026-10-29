part of '../main.dart';

class RecordDetails extends StatefulWidget {
  final Repository repo;
  final int recordId;
  final Future<void> Function() onChanged;
  const RecordDetails({
    super.key,
    required this.repo,
    required this.recordId,
    required this.onChanged,
  });
  @override
  State<RecordDetails> createState() => _RecordDetailsState();
}

class _RecordDetailsState extends State<RecordDetails> {
  AdminRecord? record;
  String error = '';
  bool busy = false;
  bool loaded = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final r = await widget.repo.get(widget.recordId);
    if (mounted)
      setState(() {
        record = r;
        loaded = true;
      });
  }

  Future<void> change(Future<void> Function() task) async {
    setState(() => busy = true);
    try {
      await task();
      await widget.onChanged();
      await load();
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> pay(AdminRecord r) async {
    final upi = r.text('upi');
    if (!RegExp(r'^[A-Za-z0-9._-]{2,}@[A-Za-z]{2,}$').hasMatch(upi) ||
        r.amount == null ||
        r.amount! <= 0 ||
        r.currency != 'INR') {
      setState(
        () => error = 'Save a valid UPI ID and positive INR amount first',
      );
      return;
    }
    if (!await confirm(
      context,
      'Review UPI payment',
      'Pay ${money(r.amount!, r.currency)} to $upi? The installed UPI app will handle payment. LifeKeeper cannot verify its result.',
    ))
      return;
    final uri = Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upi,
        'pn': r.text('issuer', r.title),
        'am': (r.amount! / 100).toStringAsFixed(2),
        'cu': 'INR',
        'tn': r.title,
      },
    );
    try {
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
          mounted)
        setState(() => error = 'No UPI app could open this payment');
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> preview(Map<String, dynamic> attachment) async {
    final file = widget.repo.file(attachment['file'] as String);
    if (isImage(file.path)) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: Text(attachment['name'] as String)),
            body: InteractiveViewer(
              child: Center(
                child: Image.file(
                  file,
                  errorBuilder: (_, e, s) => const Text('Preview unavailable'),
                ),
              ),
            ),
          ),
        ),
      );
    } else {
      if (await confirm(
        context,
        'Open PDF',
        'Open this attachment in your installed PDF viewer?',
      )) {
        final result = await OpenFilex.open(file.path);
        if (result.type != ResultType.done && mounted)
          setState(() => error = result.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = record;
    return Scaffold(
      appBar: AppBar(title: const Text('Record')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : r == null
          ? const Center(child: Text('Record removed'))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  r.title,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 6),
                Text(
                  '${r.category} · ${capitalize(r.status)} · Record ${r.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (r.amount != null)
                          Text(
                            money(r.amount!, r.currency),
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                        const SizedBox(height: 4),
                        Builder(
                          builder: (context) {
                            final delta = r.due
                                ?.difference(day(DateTime.now()))
                                .inDays;
                            return Text(
                              r.due == null
                                  ? 'Due date not set'
                                  : 'Due ${prettyDate(r.due)} · ${delta == 0
                                        ? 'today'
                                        : delta! < 0
                                        ? '${-delta} days overdue'
                                        : 'in $delta days'}',
                              style: TextStyle(
                                color:
                                    delta != null &&
                                        delta < 0 &&
                                        r.status == 'active'
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                                fontWeight: FontWeight.w500,
                              ),
                            );
                          },
                        ),
                        if (r.category == 'Bill' ||
                            r.category == 'Subscription')
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              r.status == 'active'
                                  ? 'Payment not marked as paid'
                                  : 'Completion is recorded locally, not verified by your bank',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => change(() async {
                              await widget.repo.complete(r.id!);
                            }),
                      child: Text(
                        ['Bill', 'Subscription'].contains(r.category)
                            ? 'Mark paid'
                            : 'Complete',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final result = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => RecordEditor(
                                    repo: widget.repo,
                                    record: r,
                                  ),
                                ),
                              );
                              if (result == true) await change(() async {});
                            },
                      child: const Text('Edit'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => change(() => widget.repo.reopen(r.id!)),
                      child: const Text('Reopen'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => change(
                              () => widget.repo.snooze(
                                r.id!,
                                const Duration(days: 1),
                              ),
                            ),
                      child: const Text('Snooze 1 day'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => change(
                              () => widget.repo.patch(r.id!, {
                                'status': 'archived',
                              }),
                            ),
                      child: Text(
                        r.category == 'Subscription'
                            ? 'Cancel tracking'
                            : 'Archive',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => change(() async {
                              await widget.repo.duplicate(r.id!);
                            }),
                      child: const Text('Duplicate'),
                    ),
                    if (r.text('upi').isNotEmpty)
                      OutlinedButton.icon(
                        onPressed: () => pay(r),
                        icon: const Icon(Icons.payment),
                        label: const Text('UPI Pay'),
                      ),
                  ],
                ),
                if (r.category == 'Subscription')
                  const Text(
                    'Cancel tracking only archives this record. It does not cancel the subscription with its provider.',
                  ),
                const SizedBox(height: 18),
                for (final key in [
                  'issuer',
                  'description',
                  'tags',
                  'notes',
                  'account',
                  'billPeriod',
                  'customerCare',
                  'consequence',
                  'repeat',
                  'trialEnd',
                  'created',
                  'updated',
                  'completed',
                  'snoozeUntil',
                  'lastReminded',
                ])
                  if (r.text(key).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text('$key: ${r.text(key)}'),
                    ),
                if (r.dependencies.isNotEmpty)
                  Text('Dependencies: ${r.dependencies.join(', ')}'),
                Text('Reminders: ${r.reminders.join(', ')} days before due'),
                const SizedBox(height: 18),
                const Text(
                  'Attachments',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                for (final a in r.attachments)
                  Card(
                    child: Column(
                      children: [
                        ListTile(
                          title: Text(a['name'] as String),
                          subtitle: Text('${a['size']} bytes'),
                          onTap: () => preview(a),
                          trailing: const Icon(Icons.open_in_new),
                        ),
                        if ((a['text'] as String? ?? '').isNotEmpty)
                          ExpansionTile(
                            title: const Text('Extracted text'),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: SelectableText(a['text'] as String),
                              ),
                            ],
                          ),
                        Wrap(
                          children: [
                            TextButton(
                              onPressed: () async {
                                final name = await prompt(
                                  context,
                                  'Rename attachment',
                                  'Name',
                                  initial: a['name'] as String,
                                );
                                if (name != null && name.isNotEmpty)
                                  await change(() async {
                                    final attachments = r.attachments;
                                    attachments.firstWhere(
                                      (x) => x['file'] == a['file'],
                                    )['name'] = name;
                                    await widget.repo.patch(r.id!, {
                                      'attachments': attachments,
                                    });
                                  });
                              },
                              child: const Text('Rename'),
                            ),
                            TextButton(
                              onPressed: () => change(() async {
                                final attachments = r.attachments
                                  ..removeWhere((x) => x['file'] == a['file']);
                                await widget.repo.patch(r.id!, {
                                  'attachments': attachments,
                                });
                                await widget.repo.removeAttachment(
                                  a['file'] as String,
                                );
                              }),
                              child: const Text('Delete'),
                            ),
                            TextButton(
                              onPressed: () async {
                                final result = await FilePicker.platform
                                    .pickFiles(
                                      type: FileType.custom,
                                      allowedExtensions: [
                                        'pdf',
                                        'jpg',
                                        'jpeg',
                                        'png',
                                        'webp',
                                        'heic',
                                      ],
                                    );
                                final path = result?.files.single.path;
                                if (path != null)
                                  await change(() async {
                                    final replacement = await widget.repo
                                        .importAttachment(path);
                                    final attachments = r.attachments;
                                    final i = attachments.indexWhere(
                                      (x) => x['file'] == a['file'],
                                    );
                                    attachments[i] = replacement;
                                    await widget.repo.patch(r.id!, {
                                      'attachments': attachments,
                                    });
                                    await widget.repo.removeAttachment(
                                      a['file'] as String,
                                    );
                                  });
                              },
                              child: const Text('Replace'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Completion history',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                for (final entry
                    in r.data['completionHistory'] as List<dynamic>? ?? [])
                  Text('$entry'),
                if (r.data['priceHistory'] != null) ...[
                  const Text('Price-change history'),
                  for (final entry in r.data['priceHistory'] as List<dynamic>)
                    Text('$entry'),
                ],
                if (error.isNotEmpty)
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                const SizedBox(height: 28),
                TextButton(
                  onPressed: () async {
                    if (await confirm(
                      context,
                      'Delete record?',
                      'Its attachments will be removed. Completed payment history stays in Spending.',
                    ))
                      await change(() => widget.repo.delete(r.id!));
                  },
                  child: const Text('Delete record'),
                ),
              ],
            ),
    );
  }
}
