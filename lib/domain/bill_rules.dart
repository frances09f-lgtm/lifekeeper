import 'record.dart';

class BillDraft {
  final Map<String,dynamic> fields; final List<String> warnings;
  BillDraft(this.fields,this.warnings);
}
DateTime? billDate(String value, DateTime now) {
  value=value.trim().toLowerCase().replaceAll(',', '');
  final iso=strictDate(value); if(iso!=null)return iso;
  final numeric=RegExp(r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2}|\d{4})$').firstMatch(value);
  if(numeric!=null){
    final d=int.parse(numeric[1]!); final m=int.parse(numeric[2]!); var y=int.parse(numeric[3]!);if(y<100)y+=2000;
    // A numeric day and month both <=12 is ambiguous; leave for review.
    if(d<=12&&m<=12&&d!=m)return null;
    return strictDate('$y-${m.toString().padLeft(2,'0')}-${d.toString().padLeft(2,'0')}');
  }
  final named=RegExp(r'^(\d{1,2})\s*[- /]?\s*([a-z]{3,9})(?:\s*[- /]?\s*(\d{4}))?$').firstMatch(value);
  if(named==null)return null;
  const months=['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'];
  final m=months.indexOf(named[2]!.substring(0,3))+1;if(m==0)return null;
  final y=named[3]==null?now.year:int.parse(named[3]!);
  final result=strictDate('$y-${m.toString().padLeft(2,'0')}-${named[1]!.padLeft(2,'0')}');
  if(result==null)return null;
  return named[3]==null&&result.isBefore(day(now))?strictDate('${y+1}-${m.toString().padLeft(2,'0')}-${named[1]!.padLeft(2,'0')}'):result;
}
BillDraft parseBill(String text,DateTime now,{bool quick=false}) {
  final fields=<String,dynamic>{'category':'Bill','currency':'INR','ocrText':text}; final warnings=<String>[];
  final lines=text.split(RegExp(r'[\r\n]+')).map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
  if(lines.isNotEmpty){fields['title']=lines.first.length>80?lines.first.substring(0,80):lines.first;fields['issuer']=fields['title'];}
  final amounts=RegExp(r'(?:total\s*(?:amount)?\s*due|amount\s*(?:payable|due)|net\s*payable|grand\s*total)\s*[:=-]?\s*(?:rs\.?|inr|₹)?\s*([0-9][0-9,]*(?:\.[0-9]{1,2})?)',caseSensitive:false).allMatches(text).map((m)=>minorAmount(m[1]!)).whereType<int>().toSet();
  if(amounts.length==1)fields['amount']=amounts.single;else if(amounts.length>1)warnings.add('Conflicting totals, enter the amount');
  final dueMatches=RegExp(r'(?:due\s*date|pay\s*by|payment\s*due(?:\s*date)?)\s*[:=-]?\s*(\d{4}-\d{2}-\d{2}|\d{1,2}[/-]\d{1,2}[/-](?:\d{4}|\d{2})|\d{1,2}\s*[- /]?\s*[A-Za-z]{3,9}\s*[- /]?\s*\d{4})',caseSensitive:false).allMatches(text).toList();
  final dates=dueMatches.map((m)=>billDate(m[1]!,now)).whereType<DateTime>().map(dateText).toSet();
  if(dates.length==1&&dueMatches.length==1)fields['due']=dates.single;else if(dueMatches.isNotEmpty)warnings.add('Ambiguous or conflicting due date, enter it');
  final account=RegExp(r'(?:consumer|account|customer)\s*(?:number|no\.?|id|#)\s*[:=-]?\s*([A-Za-z0-9][A-Za-z0-9/-]{3,})',caseSensitive:false).firstMatch(text);
  if(account!=null)fields['account']=account[1];
  final period=RegExp(r'bill\s*period\s*[:=-]?\s*([^\r\n]+)',caseSensitive:false).firstMatch(text);if(period!=null)fields['billPeriod']=period[1];
  final upi=RegExp(r'\b[a-zA-Z0-9._-]{2,}@[a-zA-Z]{2,}\b').firstMatch(text);if(upi!=null)fields['upi']=upi[0];
  if(quick){
    final m=RegExp(r'^(.+?)\s+(\d+(?:\.\d{1,2})?)\s+(?:on|due)\s+(\d{1,2}\s+[a-zA-Z]{3,9}(?:\s+\d{4})?)(?:\s+(daily|weekly|monthly|yearly))?$',caseSensitive:false).firstMatch(text.trim());
    if(m!=null){fields['title']=m[1];fields['issuer']=m[1];fields['amount']=minorAmount(m[2]!);final d=billDate(m[3]!,now);if(d!=null)fields['due']=dateText(d);if(m[4]!=null)fields['repeat']=m[4]!.toLowerCase();}
  }
  if(fields['amount']==null)warnings.add('Amount missing or unreadable');
  if(fields['due']==null)warnings.add('Due date missing or ambiguous, invoice date was not used');
  return BillDraft(fields,warnings);
}
