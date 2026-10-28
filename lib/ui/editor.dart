part of '../main.dart';

class RecordEditor extends StatefulWidget {
  final Repository repo;
  final AdminRecord? record;
  final Map<String, dynamic>? initial, attachment;
  final List<String> warnings;
  final bool scanned;
  const RecordEditor({
    super.key,
    required this.repo,
    this.record,
    this.initial,
    this.attachment,
    this.warnings = const [],
    this.scanned = false,
  });
  @override
  State<RecordEditor> createState() => _RecordEditorState();
}

class _RecordEditorState extends State<RecordEditor> {
  final form = GlobalKey<FormState>();
  final inputs = <String, TextEditingController>{};
  late Map<String, dynamic> original;
  late List<Map<String, dynamic>> attachments;
  final added = <String>{};
  final removed = <String>{};
  String repeat = 'none';
  Set<int> reminders = {7, 3, 1, 0};
  bool saving = false, saved = false;
  String error = '';
  List<String> warnings = [];
  static const fields = <String, String>{
    'title': 'Bill / record name',
    'issuer': 'Issuer or biller',
    'category': 'Category (custom allowed)',
    'currency': 'Currency code',
    'amountInput': 'Amount',
    'due': 'Due date YYYY-MM-DD',
    'description': 'Description',
    'tags': 'Tags, comma separated',
    'notes': 'Notes',
    'account': 'Consumer / account number',
    'billPeriod': 'Bill period',
    'upi': 'UPI ID',
    'customerCare': 'Customer care',
    'trialEnd': 'Free trial ends YYYY-MM-DD (optional)',
    'priceAfterTrialInput': 'Price after trial (optional)',
    'interval': 'Repeat interval (custom uses days)',
    'importance': 'Importance 0 to 3',
    'priorityOverride': 'Priority override 0 to 100 (optional)',
    'consequence': 'Consequence if missed',
    'grace': 'Grace period in days',
    'dependencies': 'Dependency record IDs, comma separated',
    'reminderMinute': 'Reminder time HH:MM',
  };
  @override
  void initState() {
    super.initState();
    original = {...?(widget.record?.data), ...?widget.initial};
    attachments = widget.record?.attachments ?? [];
    if (widget.attachment != null) {
      attachments.add(Map<String, dynamic>.from(widget.attachment!));
      added.add(widget.attachment!['file'] as String);
    }
    warnings = widget.warnings;
    repeat = original['repeat'] as String? ?? 'none';
    reminders = widget.record?.reminders.toSet() ?? {7, 3, 1, 0};
    for (final key in fields.keys) {
      var value = original[key]?.toString() ?? '';
      if (key == 'priceAfterTrialInput')
        value = original['priceAfterTrial'] is num
            ? ((original['priceAfterTrial'] as num).toInt() /
                      currencyScale(original['currency'] as String? ?? 'INR'))
                  .toStringAsFixed(
                    currencyScale(original['currency'] as String? ?? 'INR') == 1
                        ? 0
                        : 2,
                  )
            : '';
      if (key == 'amountInput')
        value = original['amount'] == null
            ? ''
            : ((original['amount'] as num).toInt() /
                      currencyScale(original['currency'] as String? ?? 'INR'))
                  .toStringAsFixed(
                    currencyScale(original['currency'] as String? ?? 'INR') == 1
                        ? 0
                        : 2,
                  );
      if (key == 'category' && value.isEmpty) value = 'Bill';
      if (key == 'currency' && value.isEmpty) value = 'INR';
      if (key == 'interval' && value.isEmpty) value = '1';
      if (key == 'importance' && value.isEmpty) value = '0';
      if (key == 'grace' && value.isEmpty) value = '0';
      if (key == 'tags' && original[key] is List)
        value = (original[key] as List).join(',');
      if (key == 'dependencies' && original[key] is List)
        value = (original[key] as List).join(',');
      if (key == 'reminderMinute') {
        final minute = (original[key] as num?)?.toInt() ?? 540;
        value =
            '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
      }
      inputs[key] = TextEditingController(text: value);
    }
  }

  @override
  void dispose() {
    for (final c in inputs.values) {
      c.dispose();
    }
    if (!saved) {
      for (final file in added) {
        widget.repo.removeAttachment(file);
      }
    }
    super.dispose();
  }

  String value(String key) => inputs[key]!.text.trim();
  Future<void> pickAttachment() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'heic'],
      );
      final path = picked?.files.single.path;
      if (path == null) return;
      final attachment = await widget.repo.importAttachment(path);
      if (mounted)
        setState(() {
          attachments.add(attachment);
          added.add(attachment['file'] as String);
        });
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    }
  }

  Future<void> retake() async {
    setState(() => saving = true);
    try {
      final result = await BillScanner(widget.repo).capture(ImageSource.camera);
      if (result != null) {
        for (final name in added) {
          await widget.repo.removeAttachment(name);
        }
        added.clear();
        attachments = widget.record?.attachments ?? [];
        attachments.add(result.attachment);
        added.add(result.attachment['file'] as String);
        original = {...original, ...result.draft.fields};
        for (final key in ['title', 'issuer', 'due', 'account', 'billPeriod']) {
          inputs[key]!.text = result.draft.fields[key]?.toString() ?? '';
        }
        inputs['amountInput']!.text = result.draft.fields['amount'] == null
            ? ''
            : ((result.draft.fields['amount'] as int) / 100).toStringAsFixed(2);
        warnings = result.draft.warnings;
      }
    } catch (e) {
      error = friendlyError(e);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final currency = value('currency').toUpperCase();
      final amount = value('amountInput').isEmpty
          ? null
          : minorAmount(value('amountInput'), currency: currency);
      if (value('amountInput').isNotEmpty && amount == null)
        throw ArgumentError('Invalid amount for $currency');
      final afterTrial = value('priceAfterTrialInput').isEmpty
          ? null
          : minorAmount(value('priceAfterTrialInput'), currency: currency);
      if (value('priceAfterTrialInput').isNotEmpty && afterTrial == null)
        throw ArgumentError('Invalid price after trial for $currency');
      final data = <String, dynamic>{
        ...original,
        for (final key in fields.keys.where(
          (k) => ![
            'amountInput',
            'priceAfterTrialInput',
            'interval',
            'importance',
            'priorityOverride',
            'grace',
            'dependencies',
            'reminderMinute',
          ].contains(k),
        ))
          key: value(key),
        'currency': currency,
        'amount': amount,
        'priceAfterTrial': afterTrial,
        'repeat': repeat,
        'interval': int.parse(value('interval')),
        'importance': int.parse(value('importance')),
        'grace': int.parse(value('grace')),
        'priorityOverride': value('priorityOverride').isEmpty
            ? null
            : int.parse(value('priorityOverride')),
        'dependencies': value('dependencies').isEmpty
            ? <int>[]
            : value('dependencies')
                  .split(',')
                  .map((e) => int.parse(e.trim()))
                  .toList(),
        'reminderMinute': parseTime(value('reminderMinute')),
        'reminders': reminders.toList(),
        'attachments': attachments,
        'status': widget.record?.status ?? 'active',
      };
      await widget.repo.save(AdminRecord(data, id: widget.record?.id));
      for (final name in removed) {
        await widget.repo.removeAttachment(name);
      }
      saved = true;
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget inputField(MapEntry<String, String> entry) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: TextFormField(
      controller: inputs[entry.key],
      maxLines: ['notes', 'description', 'consequence'].contains(entry.key)
          ? 3
          : 1,
      keyboardType:
          [
            'amountInput',
            'interval',
            'importance',
            'priorityOverride',
            'grace',
          ].contains(entry.key)
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: entry.value,
        suffixIcon: ['due', 'trialEnd'].contains(entry.key)
            ? IconButton(
                icon: const Icon(Icons.calendar_month),
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: strictDate(value(entry.key)) ?? DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200),
                  );
                  if (date != null) inputs[entry.key]!.text = dateText(date);
                },
              )
            : null,
      ),
      validator: (text) {
        final v = text?.trim() ?? '';
        if (entry.key == 'title' && v.isEmpty) return 'Enter a name';
        if (['due', 'trialEnd'].contains(entry.key) &&
            v.isNotEmpty &&
            strictDate(v) == null)
          return 'Use YYYY-MM-DD';
        if (entry.key == 'currency' && !RegExp(r'^[A-Za-z]{3}$').hasMatch(v))
          return 'Use a three-letter currency code';
        if ([
          'interval',
          'importance',
          'grace',
          'priorityOverride',
        ].contains(entry.key)) {
          final n = int.tryParse(v);
          if (entry.key == 'priorityOverride' && v.isEmpty) return null;
          if (n == null ||
              n < 0 ||
              (entry.key == 'interval' && n < 1) ||
              (entry.key == 'importance' && n > 3) ||
              (entry.key == 'priorityOverride' && n > 100))
            return 'Enter a valid number';
        }
        if (entry.key == 'dependencies' &&
            v.isNotEmpty &&
            v.split(',').any((e) => int.tryParse(e.trim()) == null))
          return 'Use record IDs separated by commas';
        if (entry.key == 'reminderMinute' && parseTime(v) == null)
          return 'Use HH:MM';
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.scanned
            ? 'Review bill'
            : widget.record == null
            ? 'Add expense'
            : 'Edit record',
      ),
    ),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (widget.scanned)
            const Text(
              'Check the filled fields before saving. Missing or ambiguous values are left for you to fill.',
            ),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                warning,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (attachments.isNotEmpty &&
              isImage(attachments.last['file'] as String))
            ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.file(
                widget.repo.file(attachments.last['file'] as String),
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (_, error, stack) =>
                    const Text('Image preview unavailable'),
              ),
            ),
          if (widget.scanned)
            TextButton.icon(
              onPressed: saving ? null : retake,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Retake'),
            ),
          for (final entry in fields.entries.where(
            (e) => ['title', 'amountInput', 'due'].contains(e.key),
          ))
            inputField(entry),
          ExpansionTile(
            title: const Text('More options'),
            subtitle: const Text('Repeat, reminders, notes and attachments'),
            maintainState: true,
            tilePadding: EdgeInsets.zero,
            children: [
              for (final entry in fields.entries.where(
                (e) => !['title', 'amountInput', 'due'].contains(e.key),
              ))
                inputField(entry),
              DropdownButtonFormField<String>(
                initialValue: repeat,
                decoration: const InputDecoration(labelText: 'Repeat'),
                items:
                    ['none', 'daily', 'weekly', 'monthly', 'yearly', 'custom']
                        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                        .toList(),
                onChanged: (v) => setState(() => repeat = v ?? 'none'),
              ),
              const SizedBox(height: 16),
              const Text('Remind me before the due date'),
              Wrap(
                spacing: 8,
                children: [
                  for (final offset in [7, 3, 1, 0, -1, -3])
                    FilterChip(
                      label: Text(
                        offset == 0
                            ? 'On date'
                            : offset < 0
                            ? '${-offset} days after'
                            : '$offset days before',
                      ),
                      selected: reminders.contains(offset),
                      onSelected: (v) => setState(() {
                        if (v)
                          reminders.add(offset);
                        else
                          reminders.remove(offset);
                      }),
                    ),
                  TextButton(
                    onPressed: () async {
                      final value = await prompt(
                        context,
                        'Custom reminder',
                        'Days before due date, use negative for after',
                      );
                      final n = int.tryParse(value ?? '');
                      if (n != null && n.abs() <= 365 && mounted)
                        setState(() => reminders.add(n));
                    },
                    child: const Text('Custom'),
                  ),
                ],
              ),
              for (final a in attachments)
                ListTile(
                  title: Text(a['name'] as String),
                  subtitle: Text('${a['size']} bytes'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => setState(() {
                      attachments.remove(a);
                      if (added.contains(a['file'])) {
                        widget.repo.removeAttachment(a['file'] as String);
                        added.remove(a['file']);
                      } else
                        removed.add(a['file'] as String);
                    }),
                  ),
                ),
              TextButton.icon(
                onPressed: pickAttachment,
                icon: const Icon(Icons.attach_file),
                label: const Text('Add photo or PDF'),
              ),
            ],
          ),
          if (error.isNotEmpty)
            Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: saving ? null : save,
            child: Text(saving ? 'Saving on this phone' : 'Save'),
          ),
          const SizedBox(height: 40),
        ],
      ),
    ),
  );
}

int? parseTime(String text) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(text);
  if (m == null) return null;
  final h = int.parse(m[1]!);
  final minute = int.parse(m[2]!);
  return h < 24 && minute < 60 ? h * 60 + minute : null;
}

bool isImage(String name) => !name.toLowerCase().endsWith('.pdf');
