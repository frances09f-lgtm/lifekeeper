part of '../main.dart';

extension SettingsView on _LifeKeeperState {
  List<Widget> preferences(BuildContext context) {
    Widget toggle(String label, String key, {bool fallback = true}) =>
        SwitchListTile(
          title: Text(label),
          value: settings[key] as bool? ?? fallback,
          onChanged: (v) => action(() => repo.setting(key, v)),
        );
    Widget time(String label, String key, int fallback) => ListTile(
      title: Text(label),
      subtitle: Text(
        '${((settings[key] as num?)?.toInt() ?? fallback) ~/ 60}:${(((settings[key] as num?)?.toInt() ?? fallback) % 60).toString().padLeft(2, '0')}',
      ),
      onTap: () async {
        final minute = (settings[key] as num?)?.toInt() ?? fallback;
        final picked = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(hour: minute ~/ 60, minute: minute % 60),
        );
        if (picked != null)
          await action(
            () => repo.setting(key, picked.hour * 60 + picked.minute),
          );
      },
    );
    return [
      const Text(
        'Settings',
        style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
      ),
      title('Appearance'),
      card(
        dropdown(settings['theme'] as String? ?? 'system', [
          'system',
          'light',
          'dark',
        ], (v) => action(() => repo.setting('theme', v))),
      ),
      title('Notifications'),
      card(
        Column(
          children: [
            toggle('Reminders', 'notifications'),
            toggle('Daily digest', 'digest'),
            time('Reminder time', 'reminderTime', 540),
            time('Digest time', 'digestTime', 540),
            ListTile(
              title: const Text('Snooze duration'),
              subtitle: Text('${settings['snoozeMinutes'] ?? 60} minutes'),
              onTap: () async {
                final input = await prompt(
                  context,
                  'Snooze duration',
                  'Minutes (1 to 10080)',
                  initial: '${settings['snoozeMinutes'] ?? 60}',
                );
                final n = int.tryParse(input ?? '');
                if (n != null && n > 0 && n <= 10080)
                  await action(() => repo.setting('snoozeMinutes', n));
              },
            ),
            time('Quiet hours start', 'quietStart', 1320),
            time('Quiet hours end', 'quietEnd', 480),
            toggle('Sound', 'sound'),
            toggle('Vibration', 'vibration'),
            toggle(
              'Hide record details in alerts',
              'privateAlerts',
              fallback: false,
            ),
            Text(
              settings['notificationHealth'] as String? ??
                  widget.notifications?.health ??
                  'Not checked',
            ),
            TextButton(
              onPressed: () => action(() async {
                await widget.notifications?.permissions();
              }),
              child: const Text('Grant notification and alarm access'),
            ),
            TextButton(
              onPressed: () => action(() async {
                await widget.notifications?.test();
              }),
              child: const Text('Send test notification'),
            ),
            TextButton(
              onPressed: () =>
                  widget.notifications?.plugin.openAppNotificationSettings(),
              child: const Text('Open system notification settings'),
            ),
            const Text(
              'If reminders are delayed, allow LifeKeeper in your phone battery settings. Exact alarm access is optional, inexact alarms may arrive later. OEM delivery is not guaranteed. Digest is planned 30 days ahead and refreshed on app use, boot and time changes.',
            ),
          ],
        ),
      ),
      title('Radar weights'),
      card(
        Column(
          children: [
            for (final entry in <String, int>{
              'overdue': 50,
              'grace': 20,
              'soon': 35,
              'week': 20,
              'consequence': 15,
              'importance': 10,
              'snoozes': 10,
              'dependencies': 10,
            }.entries)
              ListTile(
                title: Text(entry.key),
                trailing: Text(
                  '${(settings['weights'] as Map?)?[entry.key] ?? entry.value}',
                ),
                onTap: () async {
                  final text = await prompt(
                    context,
                    '${entry.key} weight',
                    '0 to 100',
                    initial:
                        '${(settings['weights'] as Map?)?[entry.key] ?? entry.value}',
                  );
                  final value = int.tryParse(text ?? '');
                  if (value != null && value >= 0 && value <= 100) {
                    final weights = Map<String, dynamic>.from(
                      settings['weights'] as Map? ?? {},
                    );
                    weights[entry.key] = value;
                    await action(() => repo.setting('weights', weights));
                  }
                },
              ),
          ],
        ),
      ),
      title('Security and backup'),
      card(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              title: Text(pinEnabled ? 'Change PIN' : 'Set PIN lock'),
              subtitle: const Text(
                '6 to 12 digits, locks when the app leaves the screen',
              ),
              onTap: () async {
                if (pinEnabled) {
                  final old = await prompt(
                    context,
                    'Current PIN',
                    'PIN',
                    secret: true,
                  );
                  if (old == null) return;
                  if (!await pin.verify(old)) {
                    if (context.mounted)
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Incorrect PIN')),
                      );
                    return;
                  }
                }
                if (!context.mounted) return;
                final value = await prompt(
                  context,
                  'New PIN',
                  '6 to 12 digits',
                  secret: true,
                );
                if (value == null || !context.mounted) return;
                final again = await prompt(
                  context,
                  'Confirm PIN',
                  'Repeat PIN',
                  secret: true,
                );
                if (again != value) {
                  if (context.mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('PINs do not match')),
                    );
                  return;
                }
                await action(() async {
                  await pin.set(value);
                  if (mounted) refreshState(() => pinEnabled = true);
                });
              },
            ),
            if (pinEnabled)
              TextButton(
                onPressed: () async {
                  final value = await prompt(
                    context,
                    'Disable PIN',
                    'Current PIN',
                    secret: true,
                  );
                  if (value != null)
                    await action(() async {
                      await pin.disable(value);
                      if (mounted) refreshState(() => pinEnabled = false);
                    });
                },
                child: const Text('Disable PIN'),
              ),
            TextButton.icon(
              onPressed: () => backup(context),
              icon: const Icon(Icons.save_alt),
              label: const Text('Password-encrypted export'),
            ),
            TextButton.icon(
              onPressed: () => restoreBackup(context),
              icon: const Icon(Icons.restore),
              label: const Text('Restore encrypted backup'),
            ),
            const Text(
              'Records and attachments are app-private, but are not encrypted at rest by LifeKeeper. PIN protects the screen; Android storage encryption depends on your device. Exports use AES-256-GCM and PBKDF2. Keep the backup password safe. It cannot be recovered. PIN secrets are not exported. No biometric lock is included in version 1.',
            ),
          ],
        ),
      ),
      title('Demo and privacy'),
      card(
        Column(
          children: [
            TextButton(
              onPressed: () => action(() => repo.demo()),
              child: const Text('Add labeled demo records'),
            ),
            TextButton(
              onPressed: () => action(() => repo.removeDemo()),
              child: const Text('Remove demo records'),
            ),
            TextButton(
              onPressed: () => quick(sms: true),
              child: const Text('SMS bill demo (pasted text only)'),
            ),
            TextButton(
              onPressed: () async {
                if (await confirm(
                  context,
                  'Delete all local data?',
                  'This removes all records, history, attachments and settings from this phone. Export a backup first if you need one.',
                ))
                  await action(() async {
                    await widget.notifications?.plugin.cancelAll();
                    await repo.clear();
                    await pin.storage.deleteAll();
                    if (mounted)
                      refreshState(() {
                        pinEnabled = false;
                        locked = false;
                      });
                  });
              },
              child: const Text('Delete all data'),
            ),
          ],
        ),
      ),
      title('About'),
      card(
        const Text(
          'LifeKeeper 1.0.0\nOffline bills, renewals and warranties\nNo account, backend, cloud, language controls or AI model\nBundled Latin Google ML Kit OCR plus editable deterministic rules\nNo SMS inbox access. Widget is a preview only. UPI return is not proof of payment.\nNothing is phone-tested.\nManual checks: camera/OCR, airplane mode, notification permissions/actions/delivery, reboot and timezone changes, PIN/background lock, encrypted restore, UPI and PDF preview.',
        ),
      ),
    ];
  }

  Future<void> backup(BuildContext context) async {
    final password = await prompt(
      context,
      'Backup password',
      'At least 10 characters',
      secret: true,
    );
    if (password == null) return;
    await action(() async {
      final data = await repo.exportData();
      final bytes = await encryptBackup(data, password);
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save encrypted LifeKeeper backup',
        fileName: 'LifeKeeper-${dateText(DateTime.now())}.lkbackup',
        bytes: Uint8List.fromList(bytes),
      );
      if (path != null && context.mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Encrypted backup saved')));
    });
  }

  Future<void> restoreBackup(BuildContext context) async {
    final picked = await FilePicker.platform.pickFiles();
    final path = picked?.files.single.path;
    if (path == null || !context.mounted) return;
    final password = await prompt(
      context,
      'Backup password',
      'Password used for this backup',
      secret: true,
    );
    if (password == null) return;
    await action(() async {
      final backup = await decryptBackup(
        await File(path).readAsBytes(),
        password,
      );
      if (!context.mounted) return;
      if (await confirm(
        context,
        'Replace local data?',
        'This backup has ${(backup['records'] as List).length} records. Current records, history and settings will be replaced. Your PIN stays unchanged.',
      ))
        await repo.restore(backup);
    });
  }
}
