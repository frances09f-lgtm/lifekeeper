import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/services.dart';

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:sqflite/sqflite.dart' show DatabaseException;
import 'package:url_launcher/url_launcher.dart';

import 'data/repository.dart';
import 'domain/record.dart';
import 'domain/spending.dart';
import 'domain/insights.dart';
import 'domain/bill_rules.dart';
import 'security/security.dart';
import 'services/notifications.dart';
import 'services/scanner.dart';
import 'update/app_update.dart';
part 'ui/editor.dart';
part 'ui/details.dart';
part 'ui/settings.dart';
part 'ui/spending.dart';
part 'ui/home.dart';
part 'ui/insights.dart';

@pragma('vm:entry-point')
void systemReconcile() async {
  await reconcileAfterSystemChange();
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Manrope font',
    ], await rootBundle.loadString('assets/fonts/Manrope-OFL.txt'));
  });
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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    "LifeKeeper couldn't open your saved data just now. Nothing has been cleared.",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: main, child: const Text('Retry')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimal, professional palette: warm neutrals with one teal accent.
class LkColors {
  static const accent = Color(0xff2c604c);
  static const accentDark = Color(0xff8fb79a);
  static const soft = Color(0xffe7efe8);
  static const softDark = Color(0xff2b4534);
  static const ring = Color(0xffb9cdbd);
  static const ringDark = Color(0xff4f6b57);
  static const canvas = Color(0xfff2f5f0);
  static const canvasDark = Color(0xff15251d);
  static const surfaceDark = Color(0xff203127);
  static const line = Color(0xffe4eae5);
  static const lineDark = Color(0xff35483a);
  static const ink = Color(0xff1c332c);
  static const inkDark = Color(0xffe2eee5);
  static const muted = Color(0xff66776d);
  static const mutedDark = Color(0xffa0b3a4);
  static const danger = Color(0xffa63d32);
  static const dangerDark = Color(0xfff0a397);
}

ThemeData lifeTheme(Brightness brightness, {bool trueBlack = false}) {
  final dark = brightness == Brightness.dark;
  final black = dark && trueBlack;
  final accent = dark ? LkColors.accentDark : LkColors.accent;
  final line = black
      ? const Color(0xff262626)
      : dark
      ? LkColors.lineDark
      : LkColors.line;
  final ink = dark ? LkColors.inkDark : LkColors.ink;
  final muted = dark ? LkColors.mutedDark : LkColors.muted;
  final surface = black
      ? const Color(0xff111111)
      : dark
      ? LkColors.surfaceDark
      : Colors.white;
  final canvas = black
      ? Colors.black
      : dark
      ? LkColors.canvasDark
      : LkColors.canvas;
  final scheme =
      ColorScheme.fromSeed(
        seedColor: LkColors.accent,
        brightness: brightness,
      ).copyWith(
        primary: accent,
        onPrimary: dark ? const Color(0xff14251b) : Colors.white,
        primaryContainer: dark ? LkColors.softDark : LkColors.soft,
        onPrimaryContainer: accent,
        secondaryContainer: dark ? LkColors.softDark : LkColors.soft,
        onSecondaryContainer: accent,
        surface: surface,
        onSurface: ink,
        onSurfaceVariant: muted,
        surfaceContainerLowest: surface,
        surfaceContainerLow: surface,
        surfaceContainer: surface,
        surfaceContainerHigh: surface,
        surfaceContainerHighest: dark ? LkColors.softDark : LkColors.soft,
        outline: line,
        outlineVariant: line,
        error: dark ? LkColors.dangerDark : LkColors.danger,
      );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: 'Manrope',
  );
  final text = base.textTheme.apply(bodyColor: ink, displayColor: ink);
  final shape12 = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(10),
  );
  const pill = StadiumBorder();
  return base.copyWith(
    scaffoldBackgroundColor: canvas,
    dividerColor: line,
    dividerTheme: DividerThemeData(color: line, thickness: 1, space: 1),
    textTheme: text.copyWith(
      headlineMedium: text.headlineMedium?.copyWith(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -1,
        height: 1.2,
      ),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
      ),
      titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      bodyMedium: text.bodyMedium?.copyWith(height: 1.4),
      bodySmall: text.bodySmall?.copyWith(color: muted, height: 1.4),
      labelSmall: text.labelSmall?.copyWith(
        color: muted,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: line),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: muted,
      subtitleTextStyle: text.bodySmall?.copyWith(color: muted),
      shape: shape12,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: pill,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: pill,
        foregroundColor: ink,
        side: BorderSide(color: line),
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: pill,
        textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: surface,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      labelStyle: text.labelLarge?.copyWith(
        color: ink,
        fontWeight: FontWeight.w500,
      ),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        systemNavigationBarColor: surface,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      elevation: 0,
      foregroundColor: ink,
      titleTextStyle: text.titleMedium?.copyWith(
        color: ink,
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      height: 70,
      indicatorColor: scheme.primaryContainer,
      indicatorShape: const StadiumBorder(),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? accent : muted,
          size: 22,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? ink : muted,
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: scheme.onPrimary,
      elevation: 2,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    popupMenuTheme: PopupMenuThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: line),
      ),
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
  void refreshState(VoidCallback change) {
    if (mounted) setState(change);
  }

  final navigator = GlobalKey<NavigatorState>();
  final pin = PinSecurity();
  final bio = BiometricUnlock();
  bool bioEnabled = false;
  List<AdminRecord> records = [];
  List<Map<String, Object?>> payments = [];
  Map<String, dynamic> settings = {};
  bool loading = true, busy = false, locked = false, pinEnabled = false;
  bool homeYearly = false, searchOpen = false;
  String? error;
  int tab = 0;
  String insightsTab = 'Overview';
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
      bioEnabled = widget.enforceLock && await bio.enabled();
      if (locked &&
          biometricUnlockAllowed(
            pinEnabled: pinEnabled,
            biometricEnabled: bioEnabled,
            deviceSupports: await bio.deviceSupports(),
          )) {
        await unlockWithBiometrics();
      }
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
          error = friendlyError(e);
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(friendlyError(e)),
              action: e is DatabaseException
                  ? SnackBarAction(
                      label: 'Retry',
                      onPressed: () => action(task),
                    )
                  : null,
            ),
          );
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

  Future<void> unlockWithBiometrics() async {
    if (!biometricUnlockAllowed(
      pinEnabled: pinEnabled,
      biometricEnabled: bioEnabled,
      deviceSupports: await bio.deviceSupports(),
    ))
      return;
    if (await bio.authenticate()) {
      pinInput.clear();
      if (mounted)
        setState(() {
          locked = false;
          pinError = '';
        });
      openPending();
    }
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

  Future<void> quick({bool paste = false}) async {
    final text = await prompt(
      navigator.currentContext!,
      paste ? 'Paste bill text' : 'Quick add',
      paste
          ? 'Paste the text of a bill or SMS. LifeKeeper does not read your SMS inbox.'
          : 'Type the bill name, amount and due date',
      multiline: true,
    );
    if (text == null || text.trim().isEmpty) return;
    final draft = parseBill(text, DateTime.now(), quick: !paste);
    await edit(
      initial: {
        ...draft.fields,
        if (paste) 'notes': 'Pasted bill text, review before saving',
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
      darkTheme: lifeTheme(
        Brightness.dark,
        trueBlack: settings['theme'] == 'black',
      ),
      themeMode: settings['theme'] == 'dark' || settings['theme'] == 'black'
          ? ThemeMode.dark
          : settings['theme'] == 'system'
          ? ThemeMode.system
          : ThemeMode.light,
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
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: Theme.of(context)
                                    .colorScheme
                                    .primaryContainer,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Icon(
                                Icons.lock_outline,
                                size: 26,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Unlock LifeKeeper',
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Enter your PIN to continue',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: pinInput,
                              obscureText: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 20,
                                letterSpacing: 8,
                              ),
                              decoration: InputDecoration(
                                hintText: 'PIN',
                                errorText: pinError.isEmpty ? null : pinError,
                              ),
                              onSubmitted: (_) => unlock(),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: unlock,
                                child: const Text('Unlock'),
                              ),
                            ),
                            if (pinEnabled && bioEnabled) ...[
                              const SizedBox(height: 8),
                              TextButton.icon(
                                onPressed: unlockWithBiometrics,
                                icon: const Icon(Icons.fingerprint),
                                label: const Text('Use fingerprint'),
                              ),
                            ],
                            const SizedBox(height: 20),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  size: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Your records stay on this phone',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
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
            toolbarHeight: 64,
            titleSpacing: 20,
            title: Row(
              children: [
                const LkLogo(size: 32),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    [
                      'LifeKeeper',
                      'Calendar',
                      'Insights',
                      'Vault',
                      'Settings',
                    ][tab],
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontSize: 23,
                      letterSpacing: -0.6,
                    ),
                  ),
                ),
              ],
            ),
            actions: tab == 0 && !loading && error == null
                ? [
                    IconButton(
                      tooltip: 'Quick add',
                      onPressed: quick,
                      icon: const Icon(Icons.bolt_rounded, size: 22),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 16, left: 2),
                      child: Tooltip(
                        message: 'Scan bill',
                        child: OutlinedButton.icon(
                          onPressed: scan,
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            side: BorderSide(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 1.3,
                            ),
                          ),
                          icon: const Icon(
                            Icons.document_scanner_outlined,
                            size: 17,
                          ),
                          label: const Text('Scan'),
                        ),
                      ),
                    ),
                  ]
                : null,
          ),
          body: loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LkLogo(size: 64),
                      SizedBox(height: 20),
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      ),
                    ],
                  ),
                )
              : error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(error!, textAlign: TextAlign.center),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          setState(() {
                            loading = true;
                            error = null;
                          });
                          start();
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : SafeArea(
                  child: RefreshIndicator(
                    onRefresh: reload,
                    child: ListView(
                      key: PageStorageKey<String>('tab-$tab'),
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 112),
                      children: tab == 0
                          ? home(context)
                          : tab == 1
                          ? calendar()
                          : tab == 2
                          ? insights(context)
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
                  tooltip: 'Add expense',
                  child: const Icon(Icons.add, size: 28),
                ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.6),
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (v) => setState(() => tab = v),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home_rounded),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.calendar_today_outlined),
                  selectedIcon: Icon(Icons.calendar_today_rounded),
                  label: 'Calendar',
                ),
                NavigationDestination(
                  icon: Icon(Icons.insights_outlined),
                  selectedIcon: Icon(Icons.insights_rounded),
                  label: 'Insights',
                ),
                NavigationDestination(
                  icon: Icon(Icons.folder_outlined),
                  selectedIcon: Icon(Icons.folder_rounded),
                  label: 'Vault',
                ),
                NavigationDestination(
                  icon: Icon(Icons.settings_outlined),
                  selectedIcon: Icon(Icons.settings_rounded),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget pageHeader(String heading, String sub, {String? eyebrow}) => Builder(
    builder: (context) {
      final t = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(eyebrow.toUpperCase(), style: t.labelSmall),
              const SizedBox(height: 6),
            ],
            Text(
              heading,
              style: t.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                fontSize: 26,
                letterSpacing: -0.8,
              ),
            ),
            const SizedBox(height: 6),
            Text(sub, style: t.bodySmall?.copyWith(fontSize: 14)),
          ],
        ),
      );
    },
  );
  Widget title(String text, {String? trailing}) => Builder(
    builder: (context) {
      final t = Theme.of(context).textTheme;
      return Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: t.titleMedium?.copyWith(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ),
            if (trailing != null) Text(trailing, style: t.bodySmall),
          ],
        ),
      );
    },
  );
  Widget card(Widget child) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Card(
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
  Widget statTile(String value, String label, {bool alert = false}) => Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(fontSize: 11),
              ),
              const SizedBox(height: 6),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.8,
                  color: alert ? scheme.error : scheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  Widget heroCard(BuildContext context, int count, int overdue) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ring = dark ? LkColors.ringDark : LkColors.ring;
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 18, 22),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NEEDS ATTENTION', style: t.labelSmall),
                const SizedBox(height: 8),
                Text(
                  count == 0
                      ? 'You are all caught up.'
                      : '$count ${count == 1 ? 'thing' : 'things'} to keep an eye on.',
                  style: t.headlineSmall?.copyWith(
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -0.6,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${overdue > 0 ? '$overdue overdue. ' : ''}Sorted by what needs you first.',
                  style: t.bodySmall?.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 76,
            height: 76,
            child: CustomPaint(
              painter: RadarRings(ring),
              child: Center(
                child: Text(
                  '$count',
                  style: t.headlineSmall?.copyWith(
                    fontSize: 24,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData recordIcon(AdminRecord r) => switch (r.category) {
    'Warranty' => Icons.verified_user_outlined,
    'Subscription' => Icons.autorenew_rounded,
    'ID' => Icons.badge_outlined,
    'Policy' => Icons.shield_outlined,
    'Vehicle' => Icons.directions_car_outlined,
    _ => Icons.receipt_long_outlined,
  };
  Widget pill(String text, {bool strong = false}) => Builder(
    builder: (context) {
      final scheme = Theme.of(context).colorScheme;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: strong
              ? scheme.error.withValues(alpha: 0.10)
              : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: strong ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      );
    },
  );
  Widget tile(AdminRecord r, {RadarResult? result}) {
    final delta = r.due?.difference(day(DateTime.now())).inDays;
    final payable = r.category == 'Bill' || r.category == 'Subscription';
    final overdue = r.status == 'active' && delta != null && delta < 0;
    final when = r.due == null
        ? 'No due date'
        : delta == 0
        ? 'Due today'
        : delta == 1
        ? 'Due tomorrow'
        : overdue
        ? '${-delta} days overdue'
        : 'Due ${prettyDate(r.due)}';
    return Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: () => details(r),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            recordIcon(r),
                            size: 20,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.title.isEmpty ? 'Untitled' : r.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${r.category} · $when',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: overdue ? scheme.error : null,
                                ),
                              ),
                              if (r.status == 'active' && payable)
                                Text(
                                  'Payment not marked as paid',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        if (r.amount != null) ...[
                          const SizedBox(width: 8),
                          Text(
                            money(r.amount!, r.currency),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontSize: 15,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ],
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 20,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                if (result != null) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        pill(
                          '${result.label} · ${result.score}',
                          strong: result.score >= 50,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            result.reasons.isEmpty
                                ? 'No urgent rule matched'
                                : result.reasons.join(' · '),
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
                    child: Row(
                      children: [
                        TextButton(
                          onPressed: () => action(() async {
                            await repo.complete(r.id!);
                          }),
                          child: Text(payable ? 'Mark paid' : 'Complete'),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: scheme.onSurfaceVariant,
                          ),
                          onPressed: () => action(
                            () => repo.snooze(r.id!, const Duration(days: 1)),
                          ),
                          child: const Text('Snooze'),
                        ),
                        const Spacer(),
                        PopupMenuButton<String>(
                          tooltip: 'More actions',
                          icon: Icon(
                            Icons.more_horiz_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                          onSelected: (v) {
                            if (v == 'dismiss') {
                              action(
                                () => repo.patch(r.id!, {
                                  'dismissUntil': DateTime.now()
                                      .add(const Duration(days: 1))
                                      .toIso8601String(),
                                }),
                              );
                            } else {
                              details(r);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'dismiss',
                              child: Text('Dismiss 1 day'),
                            ),
                            PopupMenuItem(
                              value: 'investigate',
                              child: Text('Investigate'),
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
        );
      },
    );
  }

  Widget dropdown(
    String current,
    List<String> options,
    void Function(String) onChanged, {
    String? label,
  }) => Builder(
    builder: (context) {
      final theme = Theme.of(context);
      final value = options.contains(current) ? current : options.first;
      return Container(
        height: 38,
        padding: const EdgeInsets.only(left: 12, right: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border.all(color: theme.dividerColor),
          borderRadius: BorderRadius.circular(999),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isDense: true,
            borderRadius: BorderRadius.circular(12),
            icon: const Icon(Icons.expand_more_rounded, size: 18),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
            selectedItemBuilder: (context) => options
                .map(
                  (v) => Center(
                    child: Text(
                      label == null
                          ? capitalize(v)
                          : '$label: ${capitalize(v)}',
                    ),
                  ),
                )
                .toList(),
            items: options
                .map(
                  (v) => DropdownMenuItem(value: v, child: Text(capitalize(v))),
                )
                .toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ),
      );
    },
  );
  List<Widget> calendar() {
    final first = DateTime(month.year, month.month);
    final length = DateTime(month.year, month.month + 1, 0).day;
    final offset = first.weekday - 1;
    final today = day(DateTime.now());
    final dueSelected = records
        .where(
          (r) => r.status == 'active' && r.text('due') == dateText(selected),
        )
        .toList();
    return [
      Builder(
        builder: (context) {
          final theme = Theme.of(context);
          final scheme = theme.colorScheme;
          return Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][month.month - 1]} ${month.year}',
                          style: theme.textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Previous month',
                        onPressed: () => setState(
                          () => month = DateTime(month.year, month.month - 1),
                        ),
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      IconButton(
                        tooltip: 'Next month',
                        onPressed: () => setState(
                          () => month = DateTime(month.year, month.month + 1),
                        ),
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final d in ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                        Expanded(
                          child: Center(
                            child: Text(d, style: theme.textTheme.labelSmall),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: offset + length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                    itemBuilder: (context, i) {
                      if (i < offset) return const SizedBox();
                      final d = DateTime(
                        month.year,
                        month.month,
                        i - offset + 1,
                      );
                      final dues = records
                          .where(
                            (r) =>
                                r.status == 'active' &&
                                r.text('due') == dateText(d),
                          )
                          .length;
                      final isSelected = d == selected;
                      final isToday = d == today;
                      return InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setState(() => selected = d),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? scheme.primary : null,
                            borderRadius: BorderRadius.circular(10),
                            border: isToday && !isSelected
                                ? Border.all(color: scheme.primary)
                                : null,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${d.day}',
                                style: TextStyle(
                                  fontWeight: isSelected || isToday
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? scheme.onPrimary
                                      : scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: dues == 0
                                      ? Colors.transparent
                                      : isSelected
                                      ? scheme.onPrimary
                                      : scheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
      title(
        'Due ${prettyDate(selected)}',
        trailing: dueSelected.isEmpty ? null : '${dueSelected.length} items',
      ),
      if (dueSelected.isEmpty)
        card(const Text('No active items due on this date')),
      for (final r in dueSelected) tile(r),
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
    final shown = docs
        .where(
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
        )
        .toList();
    return [
      pageHeader(
        'Your private vault',
        'Photos, PDFs, extracted text and expiry dates stay on this phone.',
      ),
      TextField(
        decoration: const InputDecoration(
          hintText: 'Search attachments or document text',
          prefixIcon: Icon(Icons.search_rounded, size: 20),
        ),
        onChanged: (v) => setState(() => search = v),
      ),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilterChip(
            label: const Text('Expires in 30 days'),
            selected: settings['vaultExpiry'] == true,
            onSelected: (v) => action(() => repo.setting('vaultExpiry', v)),
          ),
          ActionChip(
            avatar: const Icon(Icons.sms_outlined, size: 16),
            label: const Text('Paste bill text'),
            onPressed: () => quick(paste: true),
          ),
        ],
      ),
      title('Documents', trailing: '${shown.length} items'),
      for (final r in shown) tile(r),
      if (docs.isEmpty)
        card(
          const Text(
            'Add a warranty, ID, policy, subscription or attachment to see it here',
          ),
        )
      else if (shown.isEmpty)
        card(const Text('No documents match this search')),
    ];
  }
}

const _months = [
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
const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Human date for display, e.g. "5 Nov 2026". Storage keeps ISO dates.
String prettyDate(DateTime? d) =>
    d == null ? '' : '${d.day} ${_months[d.month - 1]} ${d.year}';

/// e.g. "Thu 29 Oct".
String shortDay(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

/// e.g. "Tuesday, 27 October".
String longDate(DateTime d) =>
    '${const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][d.weekday - 1]}, ${d.day} ${const ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'][d.month - 1]}';

String capitalize(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

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

/// LifeKeeper mark: an "L" that finishes as a check, on a deep green tile.
class LkLogo extends StatelessWidget {
  const LkLogo({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(size * 0.29),
      ),
      child: CustomPaint(painter: LkMarkPainter(scheme.onPrimary)),
    );
  }
}

class LkMarkPainter extends CustomPainter {
  LkMarkPainter(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.4 * s
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(16 * s, 12.5 * s)
      ..lineTo(16 * s, 28.5 * s)
      ..lineTo(21.5 * s, 34 * s)
      ..lineTo(33 * s, 19.5 * s);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(LkMarkPainter old) => old.color != color;
}

/// Two quiet concentric rings behind the attention count.
class RadarRings extends CustomPainter {
  RadarRings(this.color);
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawCircle(c, r - 0.5, p);
    canvas.drawCircle(c, r * 0.66, p);
    canvas.drawCircle(c, r * 0.33, p);
  }

  @override
  bool shouldRepaint(RadarRings old) => old.color != color;
}
