import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:lifekeeper/data/repository.dart';
import 'package:lifekeeper/main.dart';
void main(){testWidgets('Home and add review show real editable fields and navigation',(tester)async{sqfliteFfiInit();final dir=await Directory.systemTemp.createTemp('lk_widget');final repo=await Repository.open(factory:databaseFactoryFfi,directory:dir);await tester.pumpWidget(LifeKeeper(repo:repo,enforceLock:false));await tester.pumpAndSettle();expect(find.text('Your admin, handled'),findsOneWidget);expect(find.text('Scan bill'),findsOneWidget);expect(find.text('Quick add'),findsOneWidget);expect(find.text('Calendar'),findsOneWidget);await tester.tap(find.byTooltip('Add record'));await tester.pumpAndSettle();expect(find.text('Add record'),findsOneWidget);expect(find.text('Bill / record name'),findsOneWidget);await tester.enterText(find.byType(TextFormField).first,'My bill');await tester.pumpWidget(const SizedBox());await tester.pumpAndSettle();await repo.db.close();await dir.delete(recursive:true);});}
