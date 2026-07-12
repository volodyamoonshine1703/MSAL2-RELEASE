import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/data/services/local_db_service.dart

import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import '../models/homework_model.dart';
import '../../core/utils/log.dart' as logger;

class LocalDbService {
  final Ref ref;
  LocalDbService(this.ref);
  Database? _db;

  Future<void> init() async {
    if (Platform.isWindows || Platform.isLinux) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, 'msal_plus_v2.db'),
      version: 9, // v9 adds myprepod_cache table
      onCreate: _create,
      onUpgrade: _upgrade,
    );
  }

  Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE homework (
        lessonId TEXT PRIMARY KEY,
        discipline TEXT NOT NULL,
        date TEXT NOT NULL,
        serverText TEXT,
        localText TEXT,
        localFilePaths TEXT DEFAULT '',
        isLocalOverwrite INTEGER DEFAULT 0,
        deadline TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE progress_notes (
        disciplineId TEXT PRIMARY KEY,
        personalNote TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE schedule_cache (
        weekKey TEXT PRIMARY KEY,
        jsonData TEXT NOT NULL,
        cachedAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE progress_cache (
        cacheKey TEXT PRIMARY KEY,
        jsonData TEXT NOT NULL,
        cachedAt INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE privacy_settings (
        key TEXT PRIMARY KEY,
        value INTEGER NOT NULL DEFAULT 1
      )
    ''');
    await db.insert('privacy_settings', {'key': 'show_photo', 'value': 1});
    await db.insert('privacy_settings', {'key': 'show_email', 'value': 1});
    await db.insert('privacy_settings', {'key': 'show_phone', 'value': 1});
    await db.execute('''
      CREATE TABLE debt_deadlines (
        disciplineId TEXT PRIMARY KEY,
        deadline     TEXT NOT NULL,
        note         TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE lecture_attendance (
        disciplineId TEXT NOT NULL,
        lessonDate   TEXT NOT NULL,
        lessonId     TEXT NOT NULL,
        attended     INTEGER NOT NULL,
        confirmedAt  TEXT NOT NULL,
        PRIMARY KEY (disciplineId, lessonDate)
      )
    ''');
    await db.execute('''
      CREATE TABLE manual_attendance (
        disciplineId TEXT NOT NULL,
        lessonDate   TEXT NOT NULL,
        isMissed     INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY (disciplineId, lessonDate)
      )
    ''');
    await db.execute('''
      CREATE TABLE daily_routine (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        timeSlot   TEXT NOT NULL,
        title      TEXT NOT NULL,
        note       TEXT DEFAULT '',
        dayOfWeek  INTEGER NOT NULL DEFAULT 0,
        sortOrder  INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE general_notes (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        title      TEXT NOT NULL,
        content    TEXT DEFAULT '',
        color      INTEGER DEFAULT 0,
        createdAt  TEXT NOT NULL,
        updatedAt  TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE myprepod_cache (
        teacher_name TEXT PRIMARY KEY,
        rating TEXT NOT NULL,
        reviews TEXT DEFAULT '[]',
        cachedAt INTEGER NOT NULL
      )
    ''');
  }

  Future<void> _upgrade(Database db, int oldVersion, int newVersion) async {
    // v1 → v2: add privacy_settings table
    if (oldVersion < 2) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS privacy_settings (
            key TEXT PRIMARY KEY,
            value INTEGER NOT NULL DEFAULT 1
          )
        ''');
        await db.insert('privacy_settings', {'key': 'show_photo', 'value': 1},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('privacy_settings', {'key': 'show_email', 'value': 1},
            conflictAlgorithm: ConflictAlgorithm.ignore);
        await db.insert('privacy_settings', {'key': 'show_phone', 'value': 1},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
    }

    // v2 → v3: add missing deadline column to homework table
    if (oldVersion < 3) {
      try {
        await db.execute('ALTER TABLE homework ADD COLUMN deadline TEXT');
      } catch (_) {}
      try {
        await db.execute('ALTER TABLE homework ADD COLUMN serverText TEXT');
      } catch (_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS admission_manager (
          disciplineId TEXT PRIMARY KEY,
          points       INTEGER NOT NULL DEFAULT 0,
          required     INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 4) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS manual_attendance (
          disciplineId TEXT NOT NULL,
          lessonDate   TEXT NOT NULL,
          isMissed     INTEGER NOT NULL DEFAULT 1,
          PRIMARY KEY (disciplineId, lessonDate)
        )
      ''');
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS lecture_attendance (
          disciplineId TEXT NOT NULL,
          lessonDate   TEXT NOT NULL,
          lessonId     TEXT NOT NULL,
          attended     INTEGER NOT NULL,
          confirmedAt  TEXT NOT NULL,
          PRIMARY KEY (disciplineId, lessonDate)
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS debt_deadlines (
          disciplineId TEXT PRIMARY KEY,
          deadline     TEXT NOT NULL,
          note         TEXT
        )
      ''');
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS daily_routine (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          timeSlot   TEXT NOT NULL,
          title      TEXT NOT NULL,
          note       TEXT DEFAULT '',
          dayOfWeek  INTEGER NOT NULL DEFAULT 0,
          sortOrder  INTEGER NOT NULL DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS general_notes (
          id         INTEGER PRIMARY KEY AUTOINCREMENT,
          title      TEXT NOT NULL,
          content    TEXT DEFAULT '',
          color      INTEGER DEFAULT 0,
          createdAt  TEXT NOT NULL,
          updatedAt  TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 9) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS myprepod_cache (
          teacher_name TEXT PRIMARY KEY,
          rating TEXT NOT NULL,
          reviews TEXT DEFAULT '[]',
          cachedAt INTEGER NOT NULL
        )
      ''');
    }
  }

  Database get db {
    assert(_db != null, 'LocalDbService not initialized');
    return _db!;
  }

  // ── Homework ──────────────────────────────────────────────────────────────

  Future<HomeworkModel?> getLocalHomework(String lessonId) async {
    final rows = await db.query('homework', where: 'lessonId = ?', whereArgs: [lessonId]);
    if (rows.isEmpty) return null;
    return HomeworkModel.fromLocalJson(Map<String, dynamic>.from(rows.first));
  }

  Future<List<HomeworkModel>> getAllHomework() async {
    final rows = await db.query('homework', orderBy: 'deadline ASC, date ASC');
    return rows
        .map((r) => HomeworkModel.fromLocalJson(Map<String, dynamic>.from(r)))
        .toList();
  }

  Future<void> saveLocalHomework(HomeworkModel hw) async {
    await db.insert('homework', hw.toLocalJson(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteHomework(String lessonId) async {
    await db.delete('homework', where: 'lessonId = ?', whereArgs: [lessonId]);
  }

  // ── Progress Notes ────────────────────────────────────────────────────────

  Future<String?> getProgressNote(String disciplineId) async {
    final rows = await db.query('progress_notes',
        where: 'disciplineId = ?', whereArgs: [disciplineId]);
    if (rows.isEmpty) return null;
    return rows.first['personalNote'] as String?;
  }

  Future<void> saveProgressNote(String disciplineId, String note) async {
    await db.insert(
      'progress_notes',
      {'disciplineId': disciplineId, 'personalNote': note},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteProgressNote(String disciplineId) async {
    await db.delete('progress_notes',
        where: 'disciplineId = ?', whereArgs: [disciplineId]);
  }

  // ── Privacy Settings ──────────────────────────────────────────────────────

  Future<Map<String, bool>> getPrivacySettings() async {
    final rows = await db.query('privacy_settings');
    final map = <String, bool>{};
    for (final r in rows) {
      map[r['key'] as String] = (r['value'] as int) == 1;
    }
    return {
      'show_photo': map['show_photo'] ?? true,
      'show_email': map['show_email'] ?? true,
      'show_phone': map['show_phone'] ?? true,
    };
  }

  Future<void> setPrivacySetting(String key, bool value) async {
    await db.insert(
      'privacy_settings',
      {'key': key, 'value': value ? 1 : 0},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Cache ─────────────────────────────────────────────────────────────────

  Future<String?> getCache(String table, String key,
      {Duration maxAge = const Duration(hours: 1)}) async {
    final pk = table == 'schedule_cache' ? 'weekKey' : 'cacheKey';
    final rows = await db.query(table, where: '$pk = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;
    final cachedAtRaw = rows.first['cachedAt'];
    if (cachedAtRaw == null) return null;
    final cachedAt = cachedAtRaw is int ? cachedAtRaw : int.tryParse(cachedAtRaw.toString()) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch - cachedAt > maxAge.inMilliseconds)
      return null;
    final jsonData = rows.first['jsonData'];
    return jsonData is String ? jsonData : jsonData?.toString();
  }

  Future<void> setCache(String table, String key, String json) async {
    final pk = table == 'schedule_cache' ? 'weekKey' : 'cacheKey';
    await db.insert(
      table,
      {pk: key, 'jsonData': json, 'cachedAt': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // ── Myprepod Cache ────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getMyprepodCache(String teacherName,
      {Duration maxAge = const Duration(days: 30)}) async {
    final rows = await db.query('myprepod_cache',
        where: 'teacher_name = ?', whereArgs: [teacherName]);
    if (rows.isEmpty) return null;
    final cachedAt = rows.first['cachedAt'] as int;
    if (DateTime.now().millisecondsSinceEpoch - cachedAt > maxAge.inMilliseconds) {
      return null;
    }
    return rows.first;
  }

  Future<void> setMyprepodCache(
      String teacherName, String rating, String reviewsJson) async {
    await db.insert(
      'myprepod_cache',
      {
        'teacher_name': teacherName,
        'rating': rating,
        'reviews': reviewsJson,
        'cachedAt': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Clears ALL user-specific cached data. Called on logout / account switch.
  Future<void> clearAllCaches() async {
    const tables = [
      'schedule_cache',
      'progress_cache',
      'homework',
      'lecture_attendance',
      'manual_attendance',
      'debt_deadlines',
      'progress_notes',
    ];
    for (final t in tables) {
      try {
        await db.delete(t);
      } catch (_) {}
    }
    logger.log('[LocalDB] All user caches cleared');
  }

  List<String> _parseList(String raw) {
    try {
      return raw
          .replaceAll('[', '').replaceAll(']', '')
          .split(',').map((e) => e.trim())
          .where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }
  // ── Lecture attendance (immutable once confirmed) ──────────────────────────

  Future<bool?> getLectureAttendance(String disciplineId, String lessonDate) async {
    final rows = await db.query(
      'lecture_attendance',
      where: 'disciplineId = ? AND lessonDate = ?',
      whereArgs: [disciplineId, lessonDate],
    );
    if (rows.isEmpty) return null;
    return (rows.first['attended'] as int) == 1;
  }

  /// Returns all confirmed records for a discipline.
  /// Key: lessonDate, Value: attended (true/false)
  Future<Map<String, bool>> getLectureAttendanceForDiscipline(String disciplineId) async {
    final rows = await db.query(
      'lecture_attendance',
      where: 'disciplineId = ?',
      whereArgs: [disciplineId],
    );
    return { for (final r in rows) r['lessonDate'] as String: (r['attended'] as int) == 1 };
  }

  /// Confirms attendance once — ignores if already confirmed (immutable).
  Future<bool> confirmLectureAttendance({
    required String disciplineId,
    required String lessonDate,
    required String lessonId,
    required bool attended,
  }) async {
    // Immutable: do nothing if already confirmed
    final existing = await getLectureAttendance(disciplineId, lessonDate);
    if (existing != null) return false; // already confirmed

    await db.insert('lecture_attendance', {
      'disciplineId': disciplineId,
      'lessonDate':   lessonDate,
      'lessonId':     lessonId,
      'attended':     attended ? 1 : 0,
      'confirmedAt':  DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return true;
  }

  Future<List<Map<String, dynamic>>> getAllLectureAttendance() async {
    return db.query('lecture_attendance');
  }

  Future<void> insertLectureAttendanceFromSync(Map<String, dynamic> record) async {
    // Only insert if not already confirmed locally (remote can't override local)
    final existing = await getLectureAttendance(
      record['disciplineId'] as String,
      record['lessonDate'] as String,
    );
    if (existing != null) return;
    await db.insert('lecture_attendance', {
      'disciplineId': record['disciplineId'],
      'lessonDate':   record['lessonDate'],
      'lessonId':     record['lessonId'] ?? '',
      'attended':     record['attended'],
      'confirmedAt':  record['confirmedAt'],
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  // ── Manual attendance ──────────────────────────────────────────────────────

  /// Returns set of lesson dates that user manually marked as missed.
  Future<Set<String>> getManualMissedDates(String disciplineId) async {
    final rows = await db.query(
      'manual_attendance',
      where: 'disciplineId = ? AND isMissed = 1',
      whereArgs: [disciplineId],
    );
    return rows.map((r) => r['lessonDate'] as String).toSet();
  }

  /// Returns set of lesson dates that user manually marked as attended.
  Future<Set<String>> getManualAttendedDates(String disciplineId) async {
    final rows = await db.query(
      'manual_attendance',
      where: 'disciplineId = ? AND isMissed = 0',
      whereArgs: [disciplineId],
    );
    return rows.map((r) => r['lessonDate'] as String).toSet();
  }

  Future<bool?> getManualAttendance(String disciplineId, String lessonDate) async {
    final rows = await db.query(
      'manual_attendance',
      where: 'disciplineId = ? AND lessonDate = ?',
      whereArgs: [disciplineId, lessonDate],
    );
    if (rows.isEmpty) return null;
    return (rows.first['isMissed'] as int) == 1 ? false : true;
  }

  Future<void> setManualAttendance(String disciplineId, String lessonDate, bool attended) async {
    await db.insert(
      'manual_attendance',
      {'disciplineId': disciplineId, 'lessonDate': lessonDate, 'isMissed': attended ? 0 : 1},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearManualAttendance(String disciplineId, String lessonDate) async {
    await db.delete(
      'manual_attendance',
      where: 'disciplineId = ? AND lessonDate = ?',
      whereArgs: [disciplineId, lessonDate],
    );
  }

  // ── Debt deadlines ─────────────────────────────────────────────────────────

  Future<DateTime?> getDebtDeadline(String disciplineId) async {
    final rows = await db.query('debt_deadlines',
        where: 'disciplineId = ?', whereArgs: [disciplineId]);
    if (rows.isEmpty) return null;
    final s = rows.first['deadline'] as String?;
    return s != null ? DateTime.tryParse(s) : null;
  }

  Future<void> saveDebtDeadline(String disciplineId, DateTime deadline) async {
    await db.insert(
      'debt_deadlines',
      {'disciplineId': disciplineId, 'deadline': deadline.toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> clearDebtDeadline(String disciplineId) async {
    await db.delete('debt_deadlines',
        where: 'disciplineId = ?', whereArgs: [disciplineId]);
  }

  Future<Map<String, DateTime>> getAllDebtDeadlines() async {
    final rows = await db.query('debt_deadlines');
    final result = <String, DateTime>{};
    for (final r in rows) {
      final dt = DateTime.tryParse(r['deadline'] as String? ?? '');
      if (dt != null) result[r['disciplineId'] as String] = dt;
    }
    return result;
  }

  // ── Daily Routine ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getDailyRoutine(int dayOfWeek) async {
    return db.query('daily_routine',
        where: 'dayOfWeek = ?', whereArgs: [dayOfWeek],
        orderBy: 'sortOrder ASC, timeSlot ASC');
  }

  Future<List<Map<String, dynamic>>> getAllRoutineItems() async {
    return db.query('daily_routine', orderBy: 'dayOfWeek ASC, sortOrder ASC, timeSlot ASC');
  }

  Future<int> addRoutineItem({
    required String timeSlot,
    required String title,
    String note = '',
    required int dayOfWeek,
    int sortOrder = 0,
  }) async {
    return db.insert('daily_routine', {
      'timeSlot': timeSlot,
      'title': title,
      'note': note,
      'dayOfWeek': dayOfWeek,
      'sortOrder': sortOrder,
    });
  }

  Future<void> updateRoutineItem(int id, {
    String? timeSlot,
    String? title,
    String? note,
    int? dayOfWeek,
    int? sortOrder,
  }) async {
    final updates = <String, dynamic>{};
    if (timeSlot != null) updates['timeSlot'] = timeSlot;
    if (title != null) updates['title'] = title;
    if (note != null) updates['note'] = note;
    if (dayOfWeek != null) updates['dayOfWeek'] = dayOfWeek;
    if (sortOrder != null) updates['sortOrder'] = sortOrder;
    if (updates.isEmpty) return;
    await db.update('daily_routine', updates,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteRoutineItem(int id) async {
    await db.delete('daily_routine', where: 'id = ?', whereArgs: [id]);
  }

  // ── General Notes ──────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getAllGeneralNotes() async {
    return db.query('general_notes', orderBy: 'updatedAt DESC');
  }

  Future<int> addGeneralNote({
    required String title,
    String content = '',
    int color = 0,
  }) async {
    final now = DateTime.now().toIso8601String();
    return db.insert('general_notes', {
      'title': title,
      'content': content,
      'color': color,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> updateGeneralNote(int id, {
    String? title,
    String? content,
    int? color,
  }) async {
    final updates = <String, dynamic>{
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (title != null) updates['title'] = title;
    if (content != null) updates['content'] = content;
    if (color != null) updates['color'] = color;
    await db.update('general_notes', updates,
        where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteGeneralNote(int id) async {
    await db.delete('general_notes', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> searchGeneralNotes(String query) async {
    return db.query('general_notes',
      where: 'title LIKE ? OR content LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'updatedAt DESC',
    );
  }
}
