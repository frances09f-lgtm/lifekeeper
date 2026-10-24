import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import 'data/repository.dart';
import 'domain/record.dart';
import 'domain/bill_rules.dart';
import 'security/security.dart';
import 'services/notifications.dart';
import 'services/scanner.dart';
part 'ui/editor.dart';
part 'ui/details.dart';
part 'ui/settings.dart';
part 'ui/spending.dart';

@pragma('vm:entry-point')
void systemReconcile() async {
  await reconcileAfterSystemChange();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final repo = await Repository.open();
    final notifications = NotificationService(repo);
    runApp(LifeKeeper(repo: repo, notifications: notifications));
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'LifeKeeper could not open local storage. Your data has not been cleared. Restart the app to retry.\n$e',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData lifeTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff006c58),
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: dark
        ? const Color(0xff10221c)
        : const Color(0xffeaf5ee),
    cardTheme: CardThemeData(
      color: dark ? const Color(0xff1d3028) : Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
    ),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      indicatorColor: scheme.primaryContainer,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    ),
  );
}

class LifeKeeper extends StatefulWidget {
  final Repository repo;
  final NotificationService? notifications;
  final bool enforceLock;
  const LifeKeeper({
    super.key,
    required this.repo,
    this.notifications,
    this.enforceLock = true,
  });
  @override
  State<LifeKeeper> createState() => _LifeKeeperState();
}

class _LifeKeeperState extends State<LifeKeeper> with WidgetsBindingObserver {
  final navigator = GlobalKey<NavigatorState>();
  final pin = PinSecurity();
  List<AdminRecord> records = [];
  List<Map<String, Object?>> payments = [];
  Map<String, dynamic> settings = {};
  bool loading = true, busy = false, locked = true, pinEnabled = false;
  String? error;
  int tab = 0;
  int? pendingOpen;
  final pinInput = TextEditingController();
  String pinError = '';
  String search = '', category = 'All', status = 'active', sort = 'Due date';
  DateTime selected = day(DateTime.now());
  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  Repository get repo => widget.repo;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    start();
  }

  Future<void> start() async {
    try {
      pinEnabled = widget.enforceLock && await pin.enabled();
      locked = pinEnabled;
      await widget.notifications?.initialize(
        onResponse: (response) async {
          pendingOpen = int.tryParse(response.payload ?? '');
          await action(() => applyNotificationAction(repo, response));
          if (!locked && pendingOpen != null) openPending();
        },
      );
      final launch = await widget.notifications?.plugin
          .getNotificationAppLaunchDetails();
      pendingOpen = int.tryParse(launch?.notificationResponse?.payload ?? '');
      if (launch?.notificationResponse != null)
        await applyNotificationAction(repo, launch!.notificationResponse!);
      await reload();
      await widget.notifications?.reconcile();
      if (!locked && pendingOpen != null) openPending();
      if (widget.enforceLock) {
        final scan = await BillScanner(repo).recover();
        if (scan != null && mounted) {
          await edit(
            initial: scan.draft.fields,
            attachment: scan.attachment,
            warnings: scan.draft.warnings,
            scanned: true,
          );
        }
      }
    } catch (e) {
      if (mounted)
        setState(() {
          error = '$e';
          loading = false;
          locked = false;
        });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pinInput.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (pinEnabled && mounted) setState(() => locked = true);
    }
    if (state == AppLifecycleState.resumed) {
      action(() async {
        await reload();
        await widget.notifications?.reconcile();
      });
    }
  }

  Future<void> reload() async {
    final rs = await repo.records();
    final ps = await repo.payments();
    final st = await repo.settings();
    if (mounted)
      setState(() {
        records = rs;
        payments = ps;
        settings = st;
        loading = false;
        error = null;
      });
  }

  Future<void> action(Future<void> Function() task) async {
    if (mounted) setState(() => busy = true);
    try {
      await task();
      await reload();
      await widget.notifications?.reconcile();
    } catch (e) {
      if (mounted) {
        final context = navigator.currentContext;
        if (context != null)
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void openPending() {
    final id = pendingOpen;
    pendingOpen = null;
    final r = records.where((r) => r.id == id).firstOrNull;
    if (r != null) details(r);
  }

  Future<void> unlock() async {
    try {
      if (await pin.verify(pinInput.text)) {
        pinInput.clear();
        if (mounted)
          setState(() {
            locked = false;
            pinError = '';
          });
        openPending();
      } else if (mounted)
        setState(() => pinError = 'Incorrect PIN');
    } catch (e) {
      if (mounted) setState(() => pinError = '$e');
    }
  }

  Future<void> edit({
    AdminRecord? record,
    Map<String, dynamic>? initial,
    Map<String, dynamic>? attachment,
    List<String> warnings = const [],
    bool scanned = false,
  }) async {
    final result = await navigator.currentState!.push<bool>(
      MaterialPageRoute(
        builder: (context) => RecordEditor(
          repo: repo,
          record: record,
          initial: initial,
          attachment: attachment,
          warnings: warnings,
          scanned: scanned,
        ),
      ),
    );
    if (result == true) await action(() async {});
  }

  Future<void> details(AdminRecord record) async {
    await navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (context) => RecordDetails(
          repo: repo,
          recordId: record.id!,
          onChanged: () => action(() async {}),
        ),
      ),
    );
    await reload();
  }

  Future<void> scan() async {
    final context = navigator.currentContext!;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Scan bill',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Hold the bill flat. Everything is processed on this phone.',
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Gallery'),
                onTap: () => Navigator.pop(context, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null) return;
    if (mounted) setState(() => busy = true);
    try {
      final scan = await BillScanner(repo).capture(source);
      if (mounted) setState(() => busy = false);
      if (scan != null && mounted)
        await edit(
          initial: scan.draft.fields,
          attachment: scan.attachment,
          warnings: scan.draft.warnings,
          scanned: true,
        );
    } catch (e) {
      if (mounted) setState(() => busy = false);
      if (context.mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not scan the bill: $e. You can add the fields manually.',
            ),
          ),
        );
    }
  }

  Future<void> quick({bool sms = false}) async {
    final text = await prompt(
      navigator.currentContext!,
      sms ? 'SMS bill demo' : 'Quick add',
      sms
          ? 'Paste bill text or use the sample. This does not read your SMS inbox.'
          : 'Example: jio bill 799 on 5 nov monthly',
      initial: sms
          ? 'Jio\nAmount due: INR 799\nDue date: 25 November 2026\nAccount no: 123456789'
          : '',
      multiline: true,
    );
    if (text == null || text.trim().isEmpty) return;
    final draft = parseBill(text, DateTime.now(), quick: !sms);
    await edit(
      initial: {
        ...draft.fields,
        if (sms) 'notes': 'Pasted text / SMS demo, review before saving',
      },
      warnings: draft.warnings,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigator,
      title: 'LifeKeeper',
      debugShowCheckedModeBanner: false,
      theme: lifeTheme(Brightness.light),
      darkTheme: lifeTheme(Brightness.dark),
      themeMode: settings['theme'] == 'dark'
          ? ThemeMode.dark
          : settings['theme'] == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      builder: (context, child) => Stack(
        children: [
          child!,
          if (locked)
            Positioned.fill(
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: SafeArea(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.lock_outline, size: 48),
                            const SizedBox(height: 20),
                            const Text(
                              'Unlock LifeKeeper',
                              style: TextStyle(fontSize: 26),
                            ),
                            TextField(
                              controller: pinInput,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: 'PIN',
                                errorText: pinError.isEmpty ? null : pinError,
                              ),
                              onSubmitted: (_) => unlock(),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: unlock,
                              child: const Text('Unlock'),
                            ),
                            const Text('Your records stay on this phone'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x44000000),
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('Processing on this phone'),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: Text(
              ['LifeKeeper', 'Calendar', 'Spending', 'Vault', 'Settings'][tab],
            ),
          ),
          body: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(error!),
                      FilledButton(
                        onPressed: start,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 110),
                      children: tab == 0
                          ? home(context)
                          : tab == 1
                          ? calendar()
                          : tab == 2
                          ? spending(context)
                          : tab == 3
                          ? vault(context)
                          : preferences(context),
                    ),
                  ),
                ),
          floatingActionButton: tab == 4
              ? null
              : FloatingActionButton(
                  onPressed: () => edit(),
                  tooltip: 'Add record',
                  child: const Icon(Icons.add, size: 32),
                ),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(40),
                child: NavigationBar(
                  selectedIndex: tab,
                  onDestinationSelected: (v) => setState(() => tab = v),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'Home',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.calendar_month_outlined),
                      label: 'Calendar',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.bar_chart),
                      label: 'Spending',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.folder_outlined),
                      label: 'Vault',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.settings_outlined),
                      label: 'Settings',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget title(String text) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
    ),
  );
  Widget card(Widget child) => Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(padding: const EdgeInsets.all(18), child: child),
  );
  Widget tile(AdminRecord r, {RadarResult? result}) {
    final delta = r.due?.difference(day(DateTime.now())).inDays;
    return card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            onTap: () => details(r),
            leading: Icon(
              r.category == 'Warranty'
                  ? Icons.verified_user_outlined
                  : r.category == 'Subscription'
                  ? Icons.autorenew
                  : Icons.description_outlined,
            ),
            title: Text(
              r.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              '${r.flag('demo') ? 'DEMO · ' : ''}${r.category} · ${r.due == null ? 'No due date' : dateText(r.due)}${delta != null && delta < 0 ? ' · ${-delta} days past due' : ''}\n${r.amount == null ? '' : money(r.amount!, r.currency)}${r.status == 'active' && (r.category == 'Bill' || r.category == 'Subscription') ? ' · Payment not marked as paid' : ''}',
            ),
            trailing: const Icon(Icons.chevron_right),
          ),
          if (result != null) ...[
            Text('${result.label} · score ${result.score}'),
            Text(
              result.reasons.isEmpty
                  ? 'No urgent rule matched'
                  : result.reasons.join(' · '),
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => action(() async {
                    await repo.complete(r.id!);
                  }),
                  child: Text(
                    r.category == 'Bill' || r.category == 'Subscription'
                        ? 'Mark paid'
                        : 'Complete',
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      action(() => repo.snooze(r.id!, const Duration(days: 1))),
                  child: const Text('Snooze'),
                ),
                TextButton(
                  onPressed: () => action(
                    () => repo.patch(r.id!, {
                      'dismissUntil': DateTime.now()
                          .add(const Duration(days: 1))
                          .toIso8601String(),
                    }),
                  ),
                  child: const Text('Dismiss 1 day'),
                ),
                TextButton(
                  onPressed: () => details(r),
                  child: const Text('Investigate'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> home(BuildContext context) {
    final now = day(DateTime.now());
    final active = records.where((r) => r.status == 'active').toList();
    final ranked = radar(
      records,
      DateTime.now(),
      weights: Map<String, dynamic>.from(settings['weights'] as Map? ?? {}),
    );
    int count(int days) => active
        .where(
          (r) =>
              r.due != null &&
              !r.due!.isBefore(now) &&
              r.due!.isBefore(now.add(Duration(days: days))),
        )
        .length;
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
    if (sort == 'Title')
      visible.sort((a, b) => a.title.compareTo(b.title));
    else if (sort == 'Priority')
      visible.sort(
        (a, b) => priority(
          b,
          DateTime.now(),
        ).score.compareTo(priority(a, DateTime.now()).score),
      );
    else
      visible.sort(
        (a, b) => (a.due ?? DateTime(2200)).compareTo(b.due ?? DateTime(2200)),
      );
    return [
      const Text(
        'Your admin, handled',
        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
      ),
      const Text('Bills, renewals and warranties. All on this phone.'),
      const SizedBox(height: 18),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          Chip(
            label: Text(
              '${active.where((r) => r.due?.isBefore(now) ?? false).length} overdue',
            ),
          ),
          Chip(label: Text('${count(7)} this week')),
          Chip(label: Text('${count(30)} this month')),
        ],
      ),
      Wrap(
        spacing: 10,
        children: [
          FilledButton.icon(
            onPressed: scan,
            icon: const Icon(Icons.document_scanner_outlined),
            label: const Text('Scan bill'),
          ),
          OutlinedButton.icon(
            onPressed: quick,
            icon: const Icon(Icons.bolt),
            label: const Text('Quick add'),
          ),
        ],
      ),
      title('Attention Queue'),
      if (ranked.isEmpty)
        card(
          const Text(
            'All clear. Add a bill, document or renewal to get started.',
          ),
        ),
      for (final r in ranked.take(3)) tile(r.record, result: r),
      title('7-day timeline'),
      card(
        Column(
          children: [
            for (var i = 0; i < 7; i++)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(dateText(now.add(Duration(days: i)))),
                subtitle: Text(
                  active
                          .where(
                            (r) =>
                                r.text('due') ==
                                dateText(now.add(Duration(days: i))),
                          )
                          .map((r) => r.title)
                          .join(', ')
                          .isEmpty
                      ? 'No due items'
                      : active
                            .where(
                              (r) =>
                                  r.text('due') ==
                                  dateText(now.add(Duration(days: i))),
                            )
                            .map((r) => r.title)
                            .join(', '),
                ),
                onTap: () => setState(() {
                  selected = now.add(Duration(days: i));
                  month = DateTime(selected.year, selected.month);
                  tab = 1;
                }),
              ),
          ],
        ),
      ),
      title('Ask LifeKeeper'),
      card(
        Column(
          children: [
            const Text('Local keyword search and summaries. No AI model.'),
            TextField(
              decoration: const InputDecoration(
                hintText: 'Search your records',
              ),
              onChanged: (v) => setState(() => search = v),
            ),
            Text(
              '${active.length} active items · ${records.where((r) => r.category == 'Warranty').length} warranties',
            ),
          ],
        ),
      ),
      title('Widget preview'),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Preview only, not a phone home-screen widget'),
            for (final r
                in (active..sort(
                      (a, b) => (a.due ?? DateTime(2200)).compareTo(
                        b.due ?? DateTime(2200),
                      ),
                    ))
                    .take(3))
              Text('${r.title} · ${dateText(r.due)}'),
          ],
        ),
      ),
      if (active.any((r) => r.dependencies.isNotEmpty)) ...[
        title('Dependencies and overlaps'),
        card(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in active.where((r) => r.dependencies.isNotEmpty))
                Text(
                  '${r.title} depends on ${r.dependencies.map((id) => records.where((x) => x.id == id).firstOrNull?.title ?? 'missing record').join(', ')}',
                ),
              for (final d
                  in active
                      .map((r) => r.text('due'))
                      .where((d) => d.isNotEmpty)
                      .toSet()
                      .where(
                        (d) =>
                            active.where((r) => r.text('due') == d).length > 1,
                      ))
                Text(
                  '$d: ${active.where((r) => r.text('due') == d).map((r) => r.title).join(', ')}',
                ),
            ],
          ),
        ),
      ],
      title('Record manager'),
      Wrap(
        spacing: 10,
        runSpacing: 8,
        children: [
          dropdown(category, [
            'All',
            ...records.map((r) => r.category).toSet(),
          ], (v) => setState(() => category = v)),
          dropdown(status, [
            'All',
            'active',
            'completed',
            'archived',
          ], (v) => setState(() => status = v)),
          dropdown(sort, [
            'Due date',
            'Title',
            'Priority',
          ], (v) => setState(() => sort = v)),
        ],
      ),
      const SizedBox(height: 12),
      if (visible.isEmpty) card(const Text('No records match these filters')),
      for (final r in visible) tile(r),
    ];
  }

  Widget dropdown(
    String current,
    List<String> options,
    void Function(String) onChanged,
  ) => DropdownButton<String>(
    value: options.contains(current) ? current : options.first,
    items: options
        .map((v) => DropdownMenuItem(value: v, child: Text(v)))
        .toList(),
    onChanged: (v) {
      if (v != null) onChanged(v);
    },
  );
  List<Widget> calendar() {
    final first = DateTime(month.year, month.month);
    final length = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1;
    return [
      Row(
        children: [
          IconButton(
            onPressed: () =>
                setState(() => month = DateTime(month.year, month.month - 1)),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              '${month.year} · ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][month.month - 1]}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24),
            ),
          ),
          IconButton(
            onPressed: () =>
                setState(() => month = DateTime(month.year, month.month + 1)),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
      const Row(
        children: [
          for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
            Expanded(child: Center(child: Text(d))),
        ],
      ),
      GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: offset + length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 7,
        ),
        itemBuilder: (context, i) {
          if (i < offset) return const SizedBox();
          final d = DateTime(month.year, month.month, i - offset + 1);
          final dues = records
              .where(
                (r) => r.status == 'active' && r.text('due') == dateText(d),
              )
              .length;
          return TextButton(
            style: TextButton.styleFrom(
              backgroundColor: d == selected
                  ? Theme.of(context).colorScheme.primaryContainer
                  : null,
            ),
            onPressed: () => setState(() => selected = d),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${d.day}'),
                if (dues > 0)
                  Text('• $dues', style: const TextStyle(fontSize: 11)),
              ],
            ),
          );
        },
      ),
      title('Due ${dateText(selected)}'),
      if (!records.any(
        (r) => r.status == 'active' && r.text('due') == dateText(selected),
      ))
        card(const Text('No active items due on this date')),
      for (final r in records.where(
        (r) => r.status == 'active' && r.text('due') == dateText(selected),
      ))
        tile(r),
    ];
  }

  List<Widget> vault(BuildContext context) {
    final docs = records
        .where(
          (r) =>
              r.attachments.isNotEmpty ||
              [
                'Warranty',
                'ID',
                'Policy',
                'Vehicle',
                'Subscription',
              ].contains(r.category),
        )
        .toList();
    return [
      const Text(
        'Your private vault',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
      ),
      const Text(
        'Photos, PDFs, extracted text and expiry dates stay on this phone.',
      ),
      TextField(
        decoration: const InputDecoration(
          hintText: 'Search attachments or document text',
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      Wrap(
        spacing: 8,
        children: [
          FilterChip(
            label: const Text('Expires in 30 days'),
            selected: settings['vaultExpiry'] == true,
            onSelected: (v) => action(() => repo.setting('vaultExpiry', v)),
          ),
          TextButton(
            onPressed: () => quick(sms: true),
            child: const Text('SMS bill demo'),
          ),
        ],
      ),
      for (final r in docs.where(
        (r) =>
            (search.isEmpty ||
                r.data.values
                    .join(' ')
                    .toLowerCase()
                    .contains(search.toLowerCase())) &&
            (settings['vaultExpiry'] != true ||
                (r.due != null &&
                    r.due!.isBefore(
                      day(DateTime.now()).add(const Duration(days: 31)),
                    ))),
      ))
        tile(r),
      if (docs.isEmpty)
        card(
          const Text(
            'Add a warranty, ID, policy, subscription or attachment to see it here',
          ),
        ),
    ];
  }
}

Future<String?> prompt(
  BuildContext context,
  String title,
  String hint, {
  String initial = '',
  bool secret = false,
  bool multiline = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: secret,
        maxLines: multiline ? 5 : 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String message,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    ) ??
    false;
