import 'dart:ui';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import '../data/repository.dart';
import '../domain/reminders.dart';

@pragma('vm:entry-point')
void notificationAction(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();DartPluginRegistrant.ensureInitialized();
  final repo=await Repository.open();try{await applyNotificationAction(repo,response);final service=NotificationService(repo);await service.initialize();await service.reconcile();}finally{await repo.db.close();}
}
Future<void> applyNotificationAction(Repository repo,NotificationResponse response)async{
  final id=int.tryParse(response.payload??'');if(id==null)return;
  if(response.actionId=='complete')await repo.complete(id);
  if(response.actionId=='snooze')await repo.snooze(id,const Duration(hours:1));
}
Future<void> reconcileAfterSystemChange()async{
  WidgetsFlutterBinding.ensureInitialized();DartPluginRegistrant.ensureInitialized();
  Repository? repo;
  try {repo=await Repository.open();final service=NotificationService(repo);await service.initialize();await service.reconcile();}
  finally{await repo?.db.close();await const MethodChannel('lifekeeper/system').invokeMethod<void>('done');}
}
class NotificationService {
  final Repository repo;final plugin=FlutterLocalNotificationsPlugin();String health='Not checked';
  NotificationService(this.repo);
  Future<void> initialize({void Function(NotificationResponse)? onResponse})async{
    tzdata.initializeTimeZones();final zone=await FlutterTimezone.getLocalTimezone();tz.setLocalLocation(tz.getLocation(zone.identifier));
    await plugin.initialize(settings:const InitializationSettings(android:AndroidInitializationSettings('ic_notification')),onDidReceiveNotificationResponse:onResponse,onDidReceiveBackgroundNotificationResponse:notificationAction);
  }
  AndroidFlutterLocalNotificationsPlugin? get android=>plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
  Future<void> permissions()async{await android?.requestNotificationsPermission();await android?.requestExactAlarmsPermission();await reconcile();}
  Future<void> reconcile()async{
    try {
      final zone=await FlutterTimezone.getLocalTimezone();tz.setLocalLocation(tz.getLocation(zone.identifier));
      final settings=await repo.settings();final records=await repo.records();final alerts=planReminders(records,DateTime.now(),settings);
      final enabled=await android?.areNotificationsEnabled()??false;final exact=await android?.canScheduleExactNotifications()??false;
      await plugin.cancelAll();
      final details=NotificationDetails(android:AndroidNotificationDetails('admin_${settings['sound']!=false}_${settings['vibration']!=false}','Life admin reminders',channelDescription:'Local dues, renewals and digest',importance:Importance.high,priority:Priority.high,playSound:settings['sound']!=false,enableVibration:settings['vibration']!=false,actions:const [AndroidNotificationAction('complete','Complete'),AndroidNotificationAction('snooze','Snooze 1h'),AndroidNotificationAction('open','Open',showsUserInterface:true)]));
      for(final alert in alerts){
        final local=tz.TZDateTime(tz.local,alert.at.year,alert.at.month,alert.at.day,alert.at.hour,alert.at.minute);
        try {await plugin.zonedSchedule(id:alert.id,title:settings['privateAlerts']==true?'LifeKeeper reminder':alert.title,body:settings['privateAlerts']==true?'Open LifeKeeper to review':alert.body,scheduledDate:local,notificationDetails:details,androidScheduleMode:exact?AndroidScheduleMode.exactAllowWhileIdle:AndroidScheduleMode.inexactAllowWhileIdle,payload:alert.recordId?.toString());}
        on PlatformException {await plugin.zonedSchedule(id:alert.id,title:alert.title,body:alert.body,scheduledDate:local,notificationDetails:details,androidScheduleMode:AndroidScheduleMode.inexactAllowWhileIdle,payload:alert.recordId?.toString());}
      }
      health='${enabled?'Permission granted':'Notifications disabled'} · ${exact?'Exact alarm access':'Inexact fallback'} · ${alerts.length} scheduled · ${zone.identifier}';
      await repo.setting('notificationHealth',health);await repo.setting('lastReconciled',DateTime.now().toIso8601String());
    }catch(e){health='Scheduling failed: $e';await repo.setting('notificationHealth',health);}
  }
  Future<void> test()async{await plugin.show(id:1999999999,title:'LifeKeeper test',body:'This is a local test notification',notificationDetails:const NotificationDetails(android:AndroidNotificationDetails('test','Notification tests',importance:Importance.high,priority:Priority.high)));}
}
