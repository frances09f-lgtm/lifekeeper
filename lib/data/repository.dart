import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/record.dart';

/// User-facing text for an error from a repository call. Storage errors get a
/// calm message instead of the raw `DatabaseException(...)` text.
String friendlyError(Object e) {
  if (e is DatabaseException) {
    return "Couldn't reach your saved data just now. Nothing was lost. Tap Retry.";
  }
  return '$e';
}

/// Schema version. 2 (LifeKeeper 1.1.5) removes sample/demo rows on upgrade;
/// the tables themselves are unchanged from version 1.
const schemaVersion = 2;

/// Titles of the two records the old "Add labeled demo records" button
/// (LifeKeeper 1.0.0 to 1.1.2) inserted. Every one of them also carried
/// `demo: true`.
const sampleSeedTitles = {'Demo electricity bill', 'Demo warranty'};

/// True only for a record LifeKeeper itself created as sample data:
/// - anything the demo seeder wrote (`demo: true`), or
/// - the untouched pre-filled example from the old "SMS bill demo" chip
///   (title Jio, INR 799, account 123456789, the chip's own note).
/// A record the person typed, scanned or edited into their own bill is never
/// matched.
bool isSampleRecord(Map<String, dynamic> data) {
  if (data['demo'] == true) return true;
  return data['notes'] == 'Pasted text / SMS demo, review before saving' &&
      '${data['title'] ?? ''}'.trim() == 'Jio' &&
      '${data['account'] ?? ''}' == '123456789' &&
      data['amount'] == 79900;
}

/// Deletes sample records, their payments, and payments the seeder's records
/// left behind after a plain Delete (which keeps payment history). Returns
/// the ids of the removed records. Runs inside the caller's transaction.
Future<List<int>> purgeSampleData(DatabaseExecutor db) async {
  final rows = await db.query('records', columns: ['id', 'data']);
  final existing = <int>{};
  final sample = <int>[];
  for (final row in rows) {
    final id = row['id'] as int;
    existing.add(id);
    Map<String, dynamic> data;
    try {
      data = Map<String, dynamic>.from(
        jsonDecode(row['data'] as String) as Map,
      );
    } catch (_) {
      continue;
    }
    if (isSampleRecord(data)) sample.add(id);
  }
  for (final id in sample) {
    await db.delete('records', where: 'id=?', whereArgs: [id]);
    await db.delete('payments', where: 'recordId=?', whereArgs: [id]);
    existing.remove(id);
  }
  final payments = await db.query(
    'payments',
    columns: ['id', 'recordId', 'title'],
  );
  for (final p in payments) {
    if (!existing.contains(p['recordId']) &&
        sampleSeedTitles.contains(p['title'])) {
      await db.delete('payments', where: 'id=?', whereArgs: [p['id']]);
    }
  }
  return sample;
}

class Repository {
  final Directory root;
  final DatabaseFactory _factory;
  final String _path;
  Database _db;
  Future<Database>? _opening;

  Repository._(this._factory, this._path, this._db, this.root);

  /// The handle in use right now. It can be closed underneath us (for example
  /// by another Flutter engine in the same process), so repository methods go
  /// through [database] / [withDatabase], which reopen transparently.
  Database get db => _db;

  static String pathIn(Directory root) => p.join(root.path, 'lifekeeper.db');

  /// Every opener (the UI, the notification-action isolate, the boot/time
  /// change receiver) gets its OWN native connection (`singleInstance: false`).
  /// With the default shared instance, sqflite's Android plugin hands every
  /// engine in the process the same connection, so a background engine's
  /// close() closed the UI's database ("database_closed").
  static Future<Database> _openRaw(
    DatabaseFactory factory,
    String path,
  ) => factory.openDatabase(
    path,
    options: OpenDatabaseOptions(
      version: schemaVersion,
      singleInstance: false,
      onConfigure: (db) async {
        try {
          // Two connections may write at once (UI + notification action).
          await db.rawQuery('PRAGMA busy_timeout = 5000');
        } catch (_) {}
      },
      onCreate: (db, v) async {
        await db.execute(
          'CREATE TABLE IF NOT EXISTS records (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL, due TEXT, status TEXT NOT NULL, category TEXT NOT NULL)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS records_due_status ON records(status,due)',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS records_category ON records(category)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS payments (id INTEGER PRIMARY KEY AUTOINCREMENT, recordId INTEGER NOT NULL, occurrence TEXT NOT NULL, paidAt TEXT NOT NULL, amount INTEGER, currency TEXT NOT NULL, title TEXT NOT NULL, category TEXT NOT NULL, UNIQUE(recordId,occurrence))',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS payments_date ON payments(paidAt,currency)',
        );
        await db.execute(
          'CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 1.1.5: drop sample rows that earlier versions could insert.
          await db.transaction((tx) => purgeSampleData(tx));
        }
      },
    ),
  );

  static Future<Repository> open({
    DatabaseFactory? factory,
    Directory? directory,
  }) async {
    final root = directory ?? await getApplicationSupportDirectory();
    await root.create(recursive: true);
    final f = factory ?? databaseFactory;
    final path = pathIn(root);
    final database = await _openRaw(f, path);
    return Repository._(f, path, database, root);
  }

  /// An open handle, reopening if the current one was closed. Concurrent
  /// callers share one reopen.
  Future<Database> database() async {
    if (_db.isOpen) return _db;
    return _reopen(_db);
  }

  Future<Database> _reopen(Database stale) {
    if (!identical(stale, _db)) return Future.value(_db);
    return _opening ??= () async {
      try {
        try {
          if (stale.isOpen) await stale.close();
        } catch (_) {}
        final fresh = await _openRaw(_factory, _path);
        _db = fresh;
        return fresh;
      } finally {
        _opening = null;
      }
    }();
  }

  /// Runs [op] on an open handle. If the handle turns out to be closed
  /// natively (the Dart side can still think it is open), reopen once and
  /// retry; a closed connection ran nothing, so the retry is safe.
  Future<T> withDatabase<T>(Future<T> Function(Database db) op) async {
    final first = await database();
    try {
      return await op(first);
    } on DatabaseException catch (e) {
      if (!e.isDatabaseClosedError()) rethrow;
      return op(await _reopen(first));
    }
  }

  /// Closes this repository's own connection. A later call reopens it.
  Future<void> close() async {
    final pending = _opening;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {}
    }
    if (_db.isOpen) await _db.close();
  }

  AdminRecord decode(Map<String, Object?> row) => AdminRecord(
    Map<String, dynamic>.from(jsonDecode(row['data'] as String) as Map),
    id: row['id'] as int,
  );
  Future<List<AdminRecord>> records() async =>
      (await withDatabase((db) => db.query('records', orderBy: 'due, id')))
          .map(decode)
          .toList();
  Future<AdminRecord?> get(int id) async {
    final rows = await withDatabase(
      (db) => db.query('records', where: 'id=?', whereArgs: [id]),
    );
    return rows.isEmpty ? null : decode(rows.first);
  }

  Map<String, Object?> row(AdminRecord r) => {
    'data': jsonEncode(r.data),
    'due': r.text('due'),
    'status': r.status,
    'category': r.category,
  };
  Future<int> save(AdminRecord record) async {
    if (record.title.trim().isEmpty) throw ArgumentError('Title is required');
    if (record.text('due').isNotEmpty && record.due == null)
      throw ArgumentError('Invalid due date');
    if (record.amount != null && record.amount! < 0)
      throw ArgumentError('Amount cannot be negative');
    final now = DateTime.now().toIso8601String();
    final old = record.id == null ? null : await get(record.id!);
    final anchorChanged =
        old == null ||
        old.text('due') != record.text('due') ||
        old.text('repeat') != record.text('repeat');
    final data = {
      ...record.data,
      'updated': now,
      'created': record.text('created', now),
      'status': record.status,
    };
    if (anchorChanged && record.due != null) {
      data['anchorDay'] = record.due!.day;
      data['anchorMonth'] = record.due!.month;
    }
    if (old != null && old.amount != record.amount) {
      final history = List<dynamic>.from(
        record.data['priceHistory'] as List<dynamic>? ?? [],
      );
      history.add({
        'at': now,
        'from': old.amount,
        'to': record.amount,
        'currency': record.currency,
      });
      data['priceHistory'] = history;
    }
    final r = AdminRecord(data, id: record.id);
    if (r.id == null) return withDatabase((db) => db.insert('records', row(r)));
    await withDatabase(
      (db) => db.update('records', row(r), where: 'id=?', whereArgs: [r.id]),
    );
    return r.id!;
  }

  Future<bool> complete(int id, {DateTime? at}) async {
    final now = at ?? DateTime.now();
    return withDatabase(
      (db) => db.transaction((tx) async {
        final rows = await tx.query('records', where: 'id=?', whereArgs: [id]);
        if (rows.isEmpty) return false;
        final r = decode(rows.first);
        if (r.status != 'active') return false;
        final last = r.instant('completed');
        if (last != null &&
            now.difference(last).abs() < const Duration(seconds: 3))
          return false;
        final occurrence = r.text('due', r.text('created'));
        final existing = await tx.query(
          'payments',
          where: 'recordId=? AND occurrence=?',
          whereArgs: [id, occurrence],
        );
        if (existing.isNotEmpty) {
          await tx.update(
            'records',
            row(
              r.copy({'status': 'completed', 'updated': now.toIso8601String()}),
            ),
            where: 'id=?',
            whereArgs: [id],
          );
          return false;
        }
        await tx.insert('payments', {
          'recordId': id,
          'occurrence': occurrence,
          'paidAt': now.toIso8601String(),
          'amount': r.amount,
          'currency': r.currency,
          'title': r.title,
          'category': r.category,
        });
        final history = List<dynamic>.from(
          r.data['completionHistory'] as List<dynamic>? ?? [],
        );
        history.add({'occurrence': occurrence, 'at': now.toIso8601String()});
        final next = r.nextDue();
        final updated = r.copy({
          'status': next == null ? 'completed' : 'active',
          'due': next == null ? r.text('due') : dateText(next),
          'completed': now.toIso8601String(),
          'updated': now.toIso8601String(),
          'completionHistory': history,
          'snoozeUntil': '',
          'snoozeCount': 0,
          'dismissUntil': '',
        });
        await tx.update(
          'records',
          row(updated),
          where: 'id=?',
          whereArgs: [id],
        );
        return true;
      }),
    );
  }

  Future<void> patch(int id, Map<String, dynamic> fields) async {
    final r = await get(id);
    if (r != null) await save(r.copy(fields));
  }

  Future<void> snooze(int id, Duration duration) async {
    final r = await get(id);
    if (r != null)
      await patch(id, {
        'snoozeUntil': DateTime.now().add(duration).toIso8601String(),
        'snoozeCount': r.number('snoozeCount') + 1,
      });
  }

  Future<void> snoozeUntil(int id, DateTime until) async {
    final r = await get(id);
    if (r != null)
      await patch(id, {
        'snoozeUntil': until.toIso8601String(),
        'snoozeCount': r.number('snoozeCount') + 1,
      });
  }

  Future<void> reopen(int id) async {
    await patch(id, {'status': 'active', 'snoozeUntil': ''});
  }

  Future<void> delete(int id) async {
    final r = await get(id);
    await withDatabase(
      (db) => db.transaction((tx) async {
        await tx.delete('records', where: 'id=?', whereArgs: [id]);
      }),
    );
    for (final a in r?.attachments ?? <Map<String, dynamic>>[]) {
      await removeAttachment(a['file'] as String);
    }
  }

  Future<int> duplicate(int id) async {
    final r = await get(id);
    if (r == null) throw StateError('Record missing');
    final attachments = <Map<String, dynamic>>[];
    for (final a in r.attachments) {
      final copied = await importAttachment(
        file(a['file'] as String).path,
        name: a['name'] as String?,
        text: a['text'] as String?,
      );
      attachments.add(copied);
    }
    return save(
      AdminRecord({
        ...r.data,
        'title': '${r.title} copy',
        'created': DateTime.now().toIso8601String(),
        'completed': '',
        'completionHistory': <dynamic>[],
        'status': 'active',
        'attachments': attachments,
      }),
    );
  }

  Future<List<Map<String, Object?>>> payments() => withDatabase(
    (db) => db.query('payments', orderBy: 'paidAt DESC, id DESC'),
  );
  Future<Map<String, dynamic>> settings() async {
    final rows = await withDatabase((db) => db.query('settings'));
    return {
      for (final r in rows)
        r['key'] as String: jsonDecode(r['value'] as String),
    };
  }

  Future<void> setting(String key, dynamic value) async {
    await withDatabase(
      (db) => db.insert('settings', {
        'key': key,
        'value': jsonEncode(value),
      }, conflictAlgorithm: ConflictAlgorithm.replace),
    );
  }

  File file(String name) {
    if (p.basename(name) != name || name.contains('..'))
      throw ArgumentError('Invalid attachment path');
    return File(p.join(root.path, 'files', name));
  }

  Future<Map<String, dynamic>> importAttachment(
    String source, {
    String? name,
    String? text,
  }) async {
    final original = File(source);
    final length = await original.length();
    if (length > 25 * 1024 * 1024)
      throw ArgumentError('Attachment exceeds 25 MB');
    final ext = p.extension(source).toLowerCase();
    if (!['.png', '.jpg', '.jpeg', '.webp', '.heic', '.pdf'].contains(ext))
      throw ArgumentError('Use an image or PDF');
    final filename =
        '${DateTime.now().microsecondsSinceEpoch}_${length.toRadixString(16)}$ext';
    final destination = file(filename);
    await destination.parent.create(recursive: true);
    await original.copy(destination.path);
    return {
      'file': filename,
      'name': name ?? p.basename(source),
      'text': text ?? '',
      'size': length,
    };
  }

  Future<void> removeAttachment(String name) async {
    final f = file(name);
    if (await f.exists()) await f.delete();
  }

  Future<Map<String, dynamic>> exportData() async {
    final rs = await records();
    final files = <String, String>{};
    for (final r in rs) {
      for (final a in r.attachments) {
        final name = a['file'] as String;
        files[name] = base64Encode(await file(name).readAsBytes());
      }
    }
    return {
      'format': 1,
      'records': rs.map((r) => {'id': r.id, 'data': r.data}).toList(),
      'payments': await payments(),
      'settings': await settings(),
      'files': files,
    };
  }

  Future<void> restore(Map<String, dynamic> backup) async {
    if (backup['format'] != 1) throw ArgumentError('Unsupported backup format');
    final rs = (backup['records'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final ps = (backup['payments'] as List<dynamic>)
        .map((e) => Map<String, Object?>.from(e as Map))
        .toList();
    final st = Map<String, dynamic>.from(backup['settings'] as Map);
    final files = Map<String, dynamic>.from(backup['files'] as Map);
    final ids = <int>{};
    final staged = <String, File>{};
    final written = <File>[];
    final prefix = DateTime.now().microsecondsSinceEpoch.toString();
    final mapping = <String, String>{};
    try {
      for (final entry in files.entries) {
        file(entry.key);
        final bytes = base64Decode(entry.value as String);
        if (bytes.length > 25 * 1024 * 1024)
          throw ArgumentError('Backup attachment too large');
        final name = 'restore_${prefix}_${entry.key}';
        final destination = file(name);
        await destination.parent.create(recursive: true);
        await destination.writeAsBytes(bytes, flush: true);
        staged[entry.key] = destination;
        written.add(destination);
        mapping[entry.key] = name;
      }
      for (final r in rs) {
        final id = r['id'] as int;
        if (id <= 0 || !ids.add(id)) throw ArgumentError('Duplicate record id');
        final data = Map<String, dynamic>.from(r['data'] as Map);
        final record = AdminRecord(data, id: id);
        if (record.title.trim().isEmpty ||
            (record.text('due').isNotEmpty && record.due == null))
          throw ArgumentError('Invalid record');
        final attachments = record.attachments;
        for (final a in attachments) {
          final key = a['file'] as String;
          if (!staged.containsKey(key))
            throw ArgumentError('Missing attachment');
          a['file'] = mapping[key];
        }
        data['attachments'] = attachments;
        r['data'] = data;
      }
      for (final payment in ps) {
        if (payment['amount'] != null && payment['amount'] is! int)
          throw ArgumentError('Invalid payment');
        if (DateTime.tryParse(payment['paidAt'] as String) == null)
          throw ArgumentError('Invalid payment date');
      }
      await withDatabase(
        (db) => db.transaction((tx) async {
          await tx.delete('records');
          await tx.delete('payments');
          await tx.delete('settings');
          for (final r in rs) {
            final record = AdminRecord(
              Map<String, dynamic>.from(r['data'] as Map),
              id: r['id'] as int,
            );
            await tx.insert('records', {'id': record.id, ...row(record)});
          }
          for (final payment in ps) {
            await tx.insert('payments', payment);
          }
          for (final e in st.entries) {
            await tx.insert('settings', {
              'key': e.key,
              'value': jsonEncode(e.value),
            });
          }
          // A backup made by an older version can carry sample rows.
          await purgeSampleData(tx);
        }),
      );
    } catch (_) {
      for (final f in written) {
        if (await f.exists()) await f.delete();
      }
      rethrow;
    }
    await cleanupFiles();
  }

  Future<void> cleanupFiles() async {
    final retained = (await records())
        .expand((r) => r.attachments)
        .map((a) => a['file'])
        .toSet();
    final dir = Directory(p.join(root.path, 'files'));
    if (await dir.exists()) {
      for (final f in dir.listSync().whereType<File>()) {
        if (!retained.contains(p.basename(f.path))) await f.delete();
      }
    }
  }

  Future<void> clear() async {
    await withDatabase(
      (db) => db.transaction((tx) async {
        await tx.delete('records');
        await tx.delete('payments');
        await tx.delete('settings');
      }),
    );
    await cleanupFiles();
  }
}
