import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/data/services/cross_ref_service.dart
//
// Cross-references /progress/details with schedule to determine lesson type.
// Supports new lesson categories: lecture, practice, seminar, courseDesign, attestation.
// Attestation subtype (зачёт / экзамен) is derived from schedule lesson type string
// and duration (exam ≥ 2h30m, credit otherwise).
//
// Manual attendance confirmation (immutable, one-time) is only allowed for LECTURES.
// Unconfirmed past lectures count as missed automatically.

import 'package:intl/intl.dart';
import '../models/grade_model.dart';
import '../models/schedule_model.dart';
import 'api_service.dart';
import 'local_db_service.dart';

final _inFmt = DateFormat('dd.MM.yyyy');

DateTime? _parseDdMmYyyy(String s) {
  try { return _inFmt.parseStrict(s); } catch (_) {}
  return DateTime.tryParse(s);
}

// ── Lesson categories ─────────────────────────────────────────────────────────

enum LessonCategory {
  lecture,        // Лекция
  practice,       // Практика / Лабораторная
  seminar,        // Семинар
  courseDesign,   // Курсовое проектирование
  attestation,    // Зачёт / Экзамен
  other,
  unknown,
}

extension LessonCategoryExt on LessonCategory {
  String get label {
    switch (this) {
      case LessonCategory.lecture:      return 'Лекция';
      case LessonCategory.practice:     return 'Практика';
      case LessonCategory.seminar:      return 'Семинар';
      case LessonCategory.courseDesign: return 'Курсовое проектирование';
      case LessonCategory.attestation:  return 'Аттестация';
      case LessonCategory.other:        return 'Другое';
      case LessonCategory.unknown:      return 'Неизвестно';
    }
  }

  bool get isManualAttendanceAllowed => this == LessonCategory.lecture;
}

// ── Attestation subtype ───────────────────────────────────────────────────────

enum AttestationType { exam, credit }

extension AttestationTypeExt on AttestationType {
  String get label => this == AttestationType.exam ? 'Экзамен' : 'Зачёт';
  /// Duration in minutes
  int get durationMinutes => this == AttestationType.exam ? 180 : 90;
  String get durationLabel => this == AttestationType.exam ? '3 часа' : '1.5 часа';
}

AttestationType _detectAttestationType(String rawType, {String? start, String? end}) {
  final t = rawType.toLowerCase();
  if (t.contains('экзам')) return AttestationType.exam;
  if (t.contains('зачёт') || t.contains('зачет')) return AttestationType.credit;

  // Fallback: try to determine from lesson duration
  if (start != null && end != null) {
    try {
      final s = _parseTimeStr(start);
      final e = _parseTimeStr(end);
      if (s != null && e != null) {
        final diff = e.difference(s).inMinutes;
        return diff >= 150 ? AttestationType.exam : AttestationType.credit;
      }
    } catch (_) {}
  }
  // Default to exam (safer overestimate)
  return AttestationType.exam;
}

DateTime? _parseTimeStr(String s) {
  if (s.contains('T')) return DateTime.tryParse(s)?.toLocal();
  if (s.contains(' ') && s.contains('.')) {
    final parts = s.split(' ');
    if (parts.length >= 2) {
      final dp = parts.first.split('.');
      final tp = parts.last.split(':');
      if (dp.length == 3 && tp.length >= 2) {
        return DateTime(
          int.parse(dp[2]), int.parse(dp[1]), int.parse(dp[0]),
          int.parse(tp[0]), int.parse(tp[1]),
        );
      }
    }
  }
  return null;
}

LessonCategory _classifyType(String type) {
  final t = type.toLowerCase();
  if (t.contains('лекц'))                                           return LessonCategory.lecture;
  if (t.contains('практ') || t.contains('лаб'))                    return LessonCategory.practice;
  if (t.contains('семин'))                                          return LessonCategory.seminar;
  if (t.contains('курсов') || t.contains('проектир'))              return LessonCategory.courseDesign;
  if (t.contains('экзам') || t.contains('зачёт') || t.contains('зачет') || t.contains('аттест')) {
    return LessonCategory.attestation;
  }
  if (t.isNotEmpty) return LessonCategory.other;
  return LessonCategory.unknown;
}

// ── Enriched lesson ───────────────────────────────────────────────────────────

class TypedLesson {
  final LessonGrade lesson;
  final LessonCategory category;
  final String rawType;
  final bool isFuture;
  final AttestationType? attestationType; // non-null only when category == attestation

  /// Lecture attendance confirmation (null = not confirmed yet)
  final bool? lectureAttended;

  const TypedLesson({
    required this.lesson,
    required this.category,
    required this.rawType,
    required this.isFuture,
    this.attestationType,
    this.lectureAttended,
  });

  /// For lectures: use confirmed value; unconfirmed past lecture = missed.
  /// For other types: use server turnout.
  bool get effectiveAttended {
    if (category == LessonCategory.lecture && !isFuture) {
      return lectureAttended ?? false; // unconfirmed = missed
    }
    return lesson.turnout;
  }

  bool get isAbsence      => !isFuture && !effectiveAttended;
  bool get isConfirmed    => lectureAttended != null;
  bool get isLecture      => category == LessonCategory.lecture;
  bool get needsConfirm   => isLecture && !isFuture && !isConfirmed;
}

// ── Category stats ────────────────────────────────────────────────────────────

class CategoryStats {
  final LessonCategory category;
  final String rawType;
  final List<TypedLesson> lessons;
  final List<TypedLesson> absences;

  const CategoryStats({
    required this.category,
    required this.rawType,
    required this.lessons,
    required this.absences,
  });

  int get total    => lessons.length;
  int get missed   => absences.length;
  int get attended => total - missed;
  double get rate  => total > 0 ? attended / total : 1.0;
}

class CrossRefResult {
  final List<TypedLesson> all;
  final Map<LessonCategory, CategoryStats> byCategory;
  final bool scheduleAvailable;

  const CrossRefResult({
    required this.all,
    required this.byCategory,
    required this.scheduleAvailable,
  });

  List<TypedLesson> get pastAbsences    => all.where((l) => l.isAbsence).toList();
  List<TypedLesson> get needsConfirm    => all.where((l) => l.needsConfirm).toList();

  CategoryStats? get lectureStats      => byCategory[LessonCategory.lecture];
  CategoryStats? get practiceStats     => byCategory[LessonCategory.practice];
  CategoryStats? get seminarStats      => byCategory[LessonCategory.seminar];
  CategoryStats? get courseDesignStats => byCategory[LessonCategory.courseDesign];
  CategoryStats? get attestationStats  => byCategory[LessonCategory.attestation];

  /// Missed lectures that were unconfirmed (auto-counted as prогul)
  int get unconfirmedLectureMissed =>
      all.where((l) => l.isLecture && !l.isFuture && l.lectureAttended == null).length;
}

// ── Service ───────────────────────────────────────────────────────────────────

class CrossRefService {
  final Ref ref;
  CrossRefService(this.ref);

  /// Enrich lesson list with type info and lecture attendance from local DB.
  Future<CrossRefResult> enrich(
    ProgressItem item, {
    DateTime? semesterStart,
    // Pass schedule lessons if already fetched (avoids double-fetch)
    Map<String, List<_ScheduleEntry>>? dateTypeMapOverride,
  }) async {
    final now   = DateTime.now();
    final start = semesterStart ?? _semesterStart(now);

    // Load confirmed lecture attendances from DB
    final lectureMap = await ref.read(localDbServiceProvider)
        .getLectureAttendanceForDiscipline(item.disciplineId);

    // Build date → schedule entries map
    Map<String, List<_ScheduleEntry>> dateTypeMap = dateTypeMapOverride ?? {};
    if (dateTypeMapOverride == null) {
      try {
        dateTypeMap = await _buildDateEntryMap(
          disciplineId: item.disciplineId,
          from: start,
          to: now,
        );
      } catch (_) {}
    }

    final typed = <TypedLesson>[];

    for (final lesson in item.lessons) {
      final dt       = _parseDdMmYyyy(lesson.date);
      final isFuture = dt != null && dt.isAfter(now);

      String rawType = '';
      LessonCategory category = LessonCategory.unknown;
      AttestationType? attestType;

      if (dt != null) {
        final key     = _dateKey(dt);
        final entries = dateTypeMap[key];
        if (entries != null && entries.isNotEmpty) {
          _ScheduleEntry entry;
          if (entries.length == 1) {
            entry = entries.first;
          } else {
            final cat = lesson.subgroup == 0
                ? LessonCategory.lecture
                : LessonCategory.practice;
            entry = entries.firstWhere(
              (e) => _classifyType(e.type) == cat,
              orElse: () => entries.first,
            );
          }
          rawType  = entry.type;
          category = _classifyType(rawType);
          if (category == LessonCategory.attestation) {
            attestType = _detectAttestationType(rawType,
                start: entry.start, end: entry.end);
          }
        }
      }

      // Lecture attendance override
      bool? lectureAttended;
      if (category == LessonCategory.lecture && !isFuture) {
        lectureAttended = lectureMap[lesson.date]; // null = not confirmed
      }

      typed.add(TypedLesson(
        lesson:          lesson,
        category:        category,
        rawType:         rawType,
        isFuture:        isFuture,
        attestationType: attestType,
        lectureAttended: lectureAttended,
      ));
    }

    // Build per-category stats (past only)
    final byCategory = <LessonCategory, CategoryStats>{};
    final past = typed.where((l) => !l.isFuture).toList();

    for (final cat in LessonCategory.values) {
      final inCat = past.where((l) => l.category == cat).toList();
      if (inCat.isEmpty) continue;
      byCategory[cat] = CategoryStats(
        category: cat,
        rawType:  inCat.first.rawType,
        lessons:  inCat,
        absences: inCat.where((l) => l.isAbsence).toList(),
      );
    }

    return CrossRefResult(
      all:               typed,
      byCategory:        byCategory,
      scheduleAvailable: dateTypeMap.isNotEmpty,
    );
  }

  // ── Convenience methods used by discipline_detail_screen ────────────────────

  Future<void> markAttended(String disciplineId, String lessonDate) async {
    await ref.read(localDbServiceProvider).setManualAttendance(disciplineId, lessonDate, true);
  }

  Future<void> markMissed(String disciplineId, String lessonDate) async {
    await ref.read(localDbServiceProvider).setManualAttendance(disciplineId, lessonDate, false);
  }

  Future<void> clearOverride(String disciplineId, String lessonDate) async {
    await ref.read(localDbServiceProvider).clearManualAttendance(disciplineId, lessonDate);
  }

  // ── Lecture attendance confirmation ───────────────────────────────────────

  /// Confirms lecture attendance. Returns false if already confirmed (immutable).
  Future<bool> confirmLectureAttendance({
    required String disciplineId,
    required String lessonDate,
    required String lessonId,
    required bool attended,
  }) async {
    return ref.read(localDbServiceProvider).confirmLectureAttendance(
      disciplineId: disciplineId,
      lessonDate:   lessonDate,
      lessonId:     lessonId,
      attended:     attended,
    );
  }

  // ── Schedule fetch ────────────────────────────────────────────────────────

  Future<Map<String, List<_ScheduleEntry>>> _buildDateEntryMap({
    required String disciplineId,
    required DateTime from,
    required DateTime to,
  }) async {
    final map = <String, List<_ScheduleEntry>>{};
    DateTime current = _monday(from);
    final limit = to.add(const Duration(days: 7));

    while (current.isBefore(limit)) {
      try {
        final days = await ref.read(apiServiceProvider).getScheduleWeek(current);
        for (final day in days) {
          for (final lesson in day.data) {
            if (lesson.disciplineId != disciplineId) continue;
            final lessonDt = lesson.lessonDate ?? day.date;
            if (lessonDt.isBefore(from) || lessonDt.isAfter(to)) continue;
            final key = _dateKey(lessonDt);
            map.putIfAbsent(key, () => []);
            final entry = _ScheduleEntry(
                type: lesson.type, start: lesson.start, end: lesson.end);
            if (!map[key]!.any((e) => e.type == entry.type)) {
              map[key]!.add(entry);
            }
          }
        }
      } catch (_) {}
      current = current.add(const Duration(days: 7));
    }
    return map;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static DateTime _semesterStart(DateTime now) {
    if (now.month >= 9) return DateTime(now.year, 9, 1);
    if (now.month >= 2) return DateTime(now.year, 2, 1);
    return DateTime(now.year - 1, 9, 1);
  }

  static String _dateKey(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
      '${dt.day.toString().padLeft(2, '0')}';

  static DateTime _monday(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));
}

class _ScheduleEntry {
  final String type;
  final String start;
  final String end;
  const _ScheduleEntry({required this.type, required this.start, required this.end});
}
