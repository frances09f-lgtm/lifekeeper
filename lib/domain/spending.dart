import 'record.dart';

bool countsAsPayment(String category) => !const ['Warranty','ID','Policy','Vehicle'].contains(category);
List<Map<String,Object?>> realPayments(List<Map<String,Object?>> payments,String currency,{Set<int> demoIds=const {}})=>payments.where((p)=>p['currency']==currency&&p['amount'] is num&&countsAsPayment(p['category'] as String)&&!demoIds.contains(p['recordId'])&&!(p['title'] as String).startsWith('Demo ')).toList();
int paymentTotal(List<Map<String,Object?>> payments)=>payments.fold<int>(0,(total,p)=>total+(p['amount'] as num).toInt());
String paymentLabel(AdminRecord r)=>countsAsPayment(r.category)?'Mark paid':'Complete';
