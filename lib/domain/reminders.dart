import 'record.dart';

class PlannedAlert {
  final int id; final DateTime at; final int? recordId; final String title,body;
  PlannedAlert(this.id,this.at,this.recordId,this.title,this.body);
}
DateTime quietAdjusted(DateTime at,int start,int end) {
  if(start==end)return at;
  final minute=at.hour*60+at.minute;
  final quiet=start<end?minute>=start&&minute<end:minute>=start||minute<end;
  if(!quiet)return at;
  return DateTime(at.year,at.month,at.day+(start>end&&minute>=start?1:0),end~/60,end%60);
}
List<PlannedAlert> planReminders(List<AdminRecord> records,DateTime now,Map<String,dynamic> settings) {
  if(settings['notifications']==false)return [];
  final alerts=<PlannedAlert>[]; final start=(settings['quietStart'] as num?)?.toInt()??1320;final end=(settings['quietEnd'] as num?)?.toInt()??480;
  final minute=(settings['reminderTime'] as num?)?.toInt()??540;
  final horizon=now.add(const Duration(days:366));
  for(final r in records.where((r)=>r.status=='active'&&r.id!=null)) {
    void add(int slot,DateTime at,String body){
      at=quietAdjusted(at,start,end); if(at.isAfter(now)&&at.isBefore(horizon))alerts.add(PlannedAlert(r.id!*16+slot,at,r.id,r.title,body));
    }
    final snooze=r.instant('snoozeUntil');
    if(snooze!=null&&snooze.isAfter(now)){add(12,snooze,'Snoozed reminder, review this item');continue;}
    final due=r.due;if(due==null)continue;
    var slot=0;
    for(final offset in r.reminders){final d=DateTime(due.year,due.month,due.day-offset,minute~/60,minute%60);add(slot++,d,'Due ${dateText(due)}${r.category=='Bill'||r.category=='Subscription'?' · Payment not marked as paid':''}');}
    for(var i=1;i<=3;i++){add(8+i,DateTime(due.year,due.month,due.day+r.number('grace')+i,minute~/60,minute%60),'Due date passed, review status');}
    if(r.date('trialEnd')!=null){final d=r.date('trialEnd')!;add(13,DateTime(d.year,d.month,d.day-1,minute~/60,minute%60),'Trial ends ${dateText(d)}, cancel tracking does not cancel the provider');}
  }
  if(settings['digest']!=false){
    final t=(settings['digestTime'] as num?)?.toInt()??540;
    for(var i=0;i<30;i++){
      final d=day(now).add(Duration(days:i));final at=quietAdjusted(DateTime(d.year,d.month,d.day,t~/60,t%60),start,end);if(!at.isAfter(now))continue;
      final due=records.where((r)=>r.status=='active'&&r.due!=null&&!r.due!.isAfter(d)).toList();
      alerts.add(PlannedAlert(2000000000+i,at,null,'LifeKeeper daily digest',due.isEmpty?'No due items on this date when last refreshed': '${due.length} items due or overdue: ${due.take(3).map((r)=>r.title).join(', ')}'));
    }
  }
  alerts.sort((a,b)=>a.at.compareTo(b.at));return alerts;
}
