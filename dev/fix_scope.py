import re
from pathlib import Path
p=Path('lib/main.dart');s=p.read_text()
if "import 'domain/spending.dart';" not in s:s=s.replace("import 'domain/record.dart';", "import 'domain/record.dart';\nimport 'domain/spending.dart';")
p.write_text(s)
p=Path('lib/ui/settings.dart');s=p.read_text()
if 'Snooze duration' not in s:
    marker="time('Digest time', 'digestTime', 540),"
    if marker not in s:raise ValueError('Digest control not found')
    s=s.replace(marker,marker+"\n              ListTile(title: const Text('Snooze duration'), subtitle: Text('${settings['snoozeMinutes'] ?? 60} minutes'), onTap: () async { final input=await prompt(context,'Snooze duration','Minutes (1 to 10080)',initial:'${settings['snoozeMinutes'] ?? 60}'); final n=int.tryParse(input??''); if(n!=null&&n>0&&n<=10080) await action(()=>repo.setting('snoozeMinutes',n)); }),")
p.write_text(s)
p=Path('lib/services/notifications.dart');s=p.read_text()
s=s.replace("const Duration(hours: 1)", "Duration(minutes: ((await repo.settings())['snoozeMinutes'] as num?)?.toInt() ?? 60)")
s=s.replace("'Snooze 1h'", "'Snooze'")
p.write_text(s)
