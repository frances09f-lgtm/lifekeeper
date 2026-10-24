from pathlib import Path

def replace(file, old, new):
    path=Path(file)
    text=path.read_text()
    if new in text:
        return
    if old not in text:
        raise ValueError('Expected source not found: '+file+' '+old[:80])
    path.write_text(text.replace(old,new))

replace('lib/main.dart',"import 'package:flutter/services.dart';", "import 'dart:typed_data';")
replace('lib/domain/record.dart', "  if (!RegExp('^\\\\d+(?:\\\\.\\\\d{1,$digits})?\\$').hasMatch(clean) && !(digits == 0 && RegExp(r'^\\d+$').hasMatch(clean))) return null;", "  final pattern = digits == 0 ? RegExp(r'^\\d+$') : RegExp('^\\\\d+(?:\\\\.\\\\d{1,$digits})?\\$');\n  if (!pattern.hasMatch(clean)) return null;")
replace('lib/domain/reminders.dart', "    final due=r.due;if(due==null)continue;", "    final due=r.due;if(due==null)continue;\n    final recordMinute=r.number('reminderMinute',minute);")
replace('lib/domain/reminders.dart', "due.day-offset,minute~/60,minute%60", "due.day-offset,recordMinute~/60,recordMinute%60")
replace('lib/domain/reminders.dart', "due.day+r.number('grace')+i,minute~/60,minute%60", "due.day+r.number('grace')+i,recordMinute~/60,recordMinute%60")
replace('lib/domain/reminders.dart', "d.day-1,minute~/60,minute%60", "d.day-1,recordMinute~/60,recordMinute%60")
replace('lib/services/notifications.dart', "title:alert.title,body:alert.body,scheduledDate:local", "title:settings['privateAlerts']==true?'LifeKeeper reminder':alert.title,body:settings['privateAlerts']==true?'Open LifeKeeper to review':alert.body,scheduledDate:local")
replace('lib/data/repository.dart', "final r=decode(rows.first);if(r.status!='active')return false;", "final r=decode(rows.first);if(r.status!='active')return false;\n      final last=r.instant('completed');if(last!=null&&now.difference(last).abs()<const Duration(seconds:3))return false;")
replace('lib/data/repository.dart', "if(existing.isNotEmpty)return false;", "if(existing.isNotEmpty){await tx.update('records',row(r.copy({'status':'completed','updated':now.toIso8601String()})),where:'id=?',whereArgs:[id]);return false;}")
replace('lib/ui/editor.dart', "if(key=='dependencies'&&original[key] is List)value=(original[key] as List).join(',');", "if(key=='tags'&&original[key] is List)value=(original[key] as List).join(',');if(key=='dependencies'&&original[key] is List)value=(original[key] as List).join(',');")
