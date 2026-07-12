// lib/data/models/grade_model.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ── Date helpers ──────────────────────────────────────────────────────────────
// Server returns dates as "10.02.2026" (dd.MM.yyyy).
// DateTime.tryParse() returns null for this format → every month/period filter
// would silently produce 0 results. Always use _parseServerDate().

final _serverDateFmt = DateFormat('dd.MM.yyyy');

DateTime? _parseServerDate(String raw) {
  if (raw.isEmpty) return null;
  try {
    return _serverDateFmt.parseStrict(raw);
  } catch (_) {
    return DateTime.tryParse(raw); // ISO fallback
  }
}

// ── Per-lesson entry ──────────────────────────────────────────────────────────
// Exact shape returned by /progress/details:
// { "date":"10.02.2026", "teacher":"...", "turnout":false,
//   "lateness":false, "subgroup":1, "ratings":[2,2,0,0,0] }
//
// IMPORTANT: There is NO "lessonType" field — the server does not return it.
// Zeros in ratings are empty slots, not actual grades.

class LessonGrade {
  final String date;      // "10.02.2026"
  final String teacher;
  final bool turnout;     // true = student attended
  final bool lateness;
  final int subgroup;
  final List<int> grades; // non-zero only
  final String? status;   // "Неявка", "Недопуск" etc.

  const LessonGrade({
    required this.date,
    required this.teacher,
    required this.turnout,
    required this.lateness,
    required this.subgroup,
    required this.grades,
    this.status,
  });

  factory LessonGrade.fromJson(Map<String, dynamic> j) {
    final rawRatings = j['ratings'] ?? j['grades'] ?? [];
    final List<int> grades = [];
    String? status;

    if (rawRatings is List) {
      for (final r in rawRatings) {
        if (r is int) {
          if (r > 0) grades.add(r);
        } else if (r is String) {
          final val = int.tryParse(r);
          if (val != null) {
            if (val > 0) grades.add(val);
          } else if (r.isNotEmpty && r != '0') {
            status = r; // "Неявка", "НД" etc.
          }
        }
      }
    }

    return LessonGrade(
      date:     (j['date']    ?? '').toString(),
      teacher:  (j['teacher'] ?? '').toString(),
      turnout:  _parseBool(j['turnout']),
      lateness: _parseBool(j['lateness']),
      subgroup: int.tryParse(j['subgroup']?.toString() ?? '0') ?? 0,
      grades:   grades,
      status:   status,
    );
  }

  /// University-format lesson item from /progress/details modules→themes→items
  /// Fields: {date, professor, ball, missed, missedBall}
  factory LessonGrade.fromUniversityItem(Map<String, dynamic> j) {
    final ball = int.tryParse(j['ball']?.toString() ?? '0') ?? 0;
    final missed = int.tryParse(j['missed']?.toString() ?? '0') ?? 0;
    final grades = ball > 0 ? [ball] : <int>[];

    return LessonGrade(
      date:     (j['date'] ?? '').toString(),
      teacher:  (j['professor'] ?? '').toString(),
      turnout:  missed == 0,      // missed=1 means absent
      lateness: false,
      subgroup: 0,
      grades:   grades,
      status:   missed > 0 ? 'Пропуск' : null,
    );
  }

  static bool _parseBool(dynamic v) {
    if (v is bool)   return v;
    if (v is int)    return v != 0;
    if (v is String) {
      final s = v.toLowerCase();
      return s == 'true' || s == '1' || s == 'присутствие';
    }
    return false;
  }

  /// Parsed DateTime using server format dd.MM.yyyy.
  DateTime? get dateTime => _parseServerDate(date);

  /// True when this lesson has at least one grade of 2 (задолженность).
  bool get hasDebt => grades.any((g) => g == 2);

  Color gradeColor(int g) {
    switch (g) {
      case 5:  return const Color(0xFF4CAF82);
      case 4:  return const Color(0xFF7CB9E8);
      case 3:  return const Color(0xFFFFB547);
      case 2:  return const Color(0xFFFF5C7C);
      default: return const Color(0xFF5E5178);
    }
  }
}

// ── Discipline progress ───────────────────────────────────────────────────────

class ProgressItem {
  final String discipline;
  final String disciplineId;
  final String course;
  final String semester;
  final bool access;

  /// Semester-wide totals from /progress (used as fallback when lesson data absent).
  final int countTotal;
  final int missedTotal;

  final String debtReport;

  /// Per-lesson data from /progress/details. Empty until ApiService._fetchLessons runs.
  final List<LessonGrade> lessons;
  final List<UniversityModule>? universityModules;

  String? personalNote;

  ProgressItem({
    required this.discipline,
    required this.disciplineId,
    required this.course,
    required this.semester,
    required this.access,
    required this.countTotal,
    required this.missedTotal,
    required this.debtReport,
    required this.lessons,
    this.universityModules,
    this.personalNote,
  });

  factory ProgressItem.fromJson(Map<String, dynamic> j) {
    final rawLessons = j['lessons'];
    final lessons = rawLessons is List
        ? rawLessons
            .where((e) => e is Map)
            .map((e) => LessonGrade.fromJson(
                e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map)))
            .toList()
        : <LessonGrade>[];

    // countGrape = TOTAL across all lesson types (lectures+practice+seminars)
    // flawGrape  = TOTAL missed across all types
    // countPractice / flawPractice = SUBSET of the above for practices only
    // → Use countGrape/flawGrape directly; do NOT add countPractice (double-counting)
    final countTotal = _toInt(j['countGrape']   ?? j['countLecture']);
    final missedTotal = _toInt(j['flawGrape']   ?? j['flawLecture']);

    return ProgressItem(
      discipline:   (j['discipline'] ?? j['name'] ?? '').toString(),
      disciplineId: (j['disciplineID'] ?? j['disciplineId'] ?? j['id'] ?? '').toString(),
      course:       (j['course']   ?? '').toString(),
      semester:     (j['semester'] ?? '').toString(),
      access:       j['access'] as bool? ?? true,
      countTotal:   countTotal,
      missedTotal:  missedTotal,
      debtReport:   (j['debtReport'] ?? '').toString(),
      lessons:      lessons,
    );
  }

  /// University-format: discipline from /progress nested structure
  /// {name, guid, professors, type, year, additionalEducation}
  factory ProgressItem.fromUniversityJson(Map<String, dynamic> j, {
    required String course,
    required String semester,
  }) {
    return ProgressItem(
      discipline:   (j['name'] ?? '').toString(),
      disciplineId: (j['guid'] ?? '').toString(),
      course:       course,
      semester:     semester,
      access:       true,
      countTotal:   0,    // will be filled from /progress/details
      missedTotal:  0,
      debtReport:   '',
      lessons:      [],
      universityModules: [],
    );
  }

  static int _toInt(dynamic v) =>
      v == null ? 0 : int.tryParse(v.toString()) ?? 0;

  // ── Attendance ─────────────────────────────────────────────────────────────

  int get effectiveMissed =>
      lessons.isNotEmpty ? lessons.where((l) => !l.turnout).length : missedTotal;

  int get effectiveTotal =>
      lessons.isNotEmpty ? lessons.length : countTotal;

  double get attendanceRate {
    final t = effectiveTotal;
    return t > 0 ? (t - effectiveMissed) / t : 1.0;
  }

  // ── Convenience aliases (used by discipline_detail_screen) ─────────────────
  int get totalClasses  => effectiveTotal;
  int get totalMissed   => effectiveMissed;
  int get attended      => (effectiveTotal - effectiveMissed).clamp(0, 999999);

  // Server does not return per-type (lecture/practice/seminar) breakdowns from
  // /progress/details — we have no way to split them. These return 0 so that
  // the "Осталось занятий" card in discipline_detail_screen is simply hidden.
  int get remainingLecture  => 0;
  int get remainingPractice => 0;
  int get remainingSeminar  => 0;

  // ── Grades ─────────────────────────────────────────────────────────────────

  /// All non-zero grades across all lessons.
  List<int> get allGrades => lessons.expand((l) => l.grades).toList();

  double get averageGrade {
    final gs = allGrades;
    return gs.isEmpty ? 0 : gs.reduce((a, b) => a + b) / gs.length;
  }

  /// { grade → count } e.g. { 5:3, 4:2, 2:1 }
  Map<int, int> get gradeDistribution {
    final map = <int, int>{};
    for (final g in allGrades) map[g] = (map[g] ?? 0) + 1;
    return map;
  }

  // ── BARS Score (University) ────────────────────────────────────────────────

  double get barsScore {
    if (universityModules == null || universityModules!.isEmpty) return 0.0;
    return universityModules!.fold(0.0, (sum, m) => sum + m.mediumScore);
  }

  // ── Debt ───────────────────────────────────────────────────────────────────
  //
  // Fix: ratings [2,2,0,0,0] was always hasDebt=false because:
  //  - Lesson data was never loaded (wrong endpoint /progress/getProgressDetails)
  //  - Even when loaded, zeros were not filtered → no grade==2 found
  // Now: correct endpoint /progress/details is called, zeros stripped.

  bool get hasDebt {
    if (lessons.isNotEmpty) return lessons.any((l) => l.hasDebt);
    // Fallback: debtReport field if lessons not yet loaded
    final dr = debtReport.trim().toLowerCase();
    return dr.isNotEmpty && dr != 'нет' && dr != 'no' && dr != '0' && dr != 'false';
  }

  int get debtCount => allGrades.where((g) => g == 2).length;
  List<LessonGrade> get debtLessons => lessons.where((l) => l.hasDebt).toList();

  List<UniversityModule> get failingModules {
    if (universityModules == null) return [];
    return universityModules!.where((m) => m.lacksAdmission).toList();
  }

  // ── Period / month filtering ───────────────────────────────────────────────

  /// Filter lessons to those within [from, to] range.
  /// Returns a new ProgressItem with updated totals from actual lesson data.
  ProgressItem filteredByPeriod(DateTime from, DateTime to) {
    if (lessons.isEmpty) return this;

    final filtered = lessons.where((l) {
      final dt = l.dateTime;
      if (dt == null) return true; // keep if date unparseable
      return !dt.isBefore(from) && !dt.isAfter(to);
    }).toList();

    return ProgressItem(
      discipline:   discipline,
      disciplineId: disciplineId,
      course:       course,
      semester:     semester,
      access:       access,
      countTotal:   filtered.length,
      missedTotal:  filtered.where((l) => !l.turnout).length,
      debtReport:   debtReport,
      lessons:      filtered,
      universityModules: universityModules,
      personalNote: personalNote,
    );
  }

  List<LessonGrade> lessonsForMonth(int year, int month) {
    final now = DateTime.now();
    return lessons.where((l) {
      final dt = l.dateTime;
      if (dt == null) return false;
      // Exclude future lessons — they haven't happened yet
      if (dt.isAfter(now)) return false;
      return dt.year == year && dt.month == month;
    }).toList();
  }

  int missedForMonth(int year, int month) =>
      lessonsForMonth(year, month).where((l) => !l.turnout).length;

  int totalForMonth(int year, int month) =>
      lessonsForMonth(year, month).length;
}

// ── Cross-discipline monthly summary ─────────────────────────────────────────

class MonthAttendanceSummary {
  final int year;
  final int month;
  final int totalLessons;
  final int missedLessons;
  final bool hasLessonData;

  const MonthAttendanceSummary({
    required this.year,
    required this.month,
    required this.totalLessons,
    required this.missedLessons,
    required this.hasLessonData,
  });

  int    get attended => (totalLessons - missedLessons).clamp(0, totalLessons);
  double get rate     => totalLessons > 0 ? attended / totalLessons : 1.0;

  static MonthAttendanceSummary fromProgress(
      List<ProgressItem> items, int year, int month) {
    int total  = 0;
    int missed = 0;
    bool hasData = false;

    for (final item in items) {
      final ml = item.lessonsForMonth(year, month);
      if (ml.isEmpty) continue;
      hasData = true;
      total  += ml.length;
      missed += ml.where((l) => !l.turnout).length;
    }

    return MonthAttendanceSummary(
      year: year, month: month,
      totalLessons: total, missedLessons: missed,
      hasLessonData: hasData,
    );
  }
}

// ── Record book entry ─────────────────────────────────────────────────────────

class RecordEntry {
  final String course, semester, grade, discipline, teacher, type;
  final int points;

  const RecordEntry({
    required this.course, required this.semester, required this.grade,
    required this.points, required this.discipline,
    required this.teacher, required this.type,
  });

  factory RecordEntry.fromJson(Map<String, dynamic> j) => RecordEntry(
    course:     (j['course']     ?? '').toString(),
    semester:   (j['semester']   ?? '').toString(),
    grade:      (j['grade']      ?? '').toString(),
    points:     int.tryParse(j['points']?.toString() ?? '0') ?? 0,
    discipline: (j['discipline'] ?? '').toString(),
    teacher:    (j['teacher']    ?? '').toString(),
    type:       (j['type']       ?? '').toString(),
  );

  Color get gradeColor {
    switch (grade.toLowerCase()) {
      case 'отлично':              return const Color(0xFF4CAF82);
      case 'хорошо':               return const Color(0xFF7CB9E8);
      case 'удовлетворительно':    return const Color(0xFFFFB547);
      case 'неудовлетворительно':  return const Color(0xFFFF5C7C);
      case 'зачёт': case 'зачет':  return const Color(0xFF4CAF82);
      case 'незачёт': case 'незачет': return const Color(0xFFFF5C7C);
      default:                     return const Color(0xFF9C6FFF);
    }
  }
}

// ── University BARS Modules ───────────────────────────────────────────────────

class UniversityModule {
  final String module;
  final double mediumScore;
  final List<UniversityTheme> themes;

  const UniversityModule({
    required this.module,
    required this.mediumScore,
    required this.themes,
  });

  factory UniversityModule.fromJson(Map<String, dynamic> j) {
    return UniversityModule(
      module: (j['module'] ?? '').toString(),
      mediumScore: double.tryParse(j['mediumScore']?.toString() ?? '0') ?? 0.0,
      themes: (j['themes'] as List?)
              ?.whereType<Map>()
              .map((e) => UniversityTheme.fromJson(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }

  int get totalClasses => themes.expand((t) => t.items).length;
  int get missedClasses => themes.expand((t) => t.items).where((i) => !i.turnout).length;
  int get attendedClasses => totalClasses - missedClasses;
  int get positiveGradesCount => themes.expand((t) => t.items).expand((i) => i.grades).where((g) => g >= 3).length;

  int get requiredPositiveGrades {
    final t = totalClasses;
    if (t < 2) return 1;
    if (t <= 4) return 2;
    if (t <= 8) return 3;
    return 4;
  }

  bool get lacksAdmission {
    if (totalClasses == 0) return false;
    final attendanceFails = attendedClasses <= (totalClasses / 2);
    final gradesFail = positiveGradesCount < requiredPositiveGrades;
    return attendanceFails || gradesFail;
  }

  String get admissionStatus {
    if (totalClasses == 0) return "Нет данных";
    final List<String> issues = [];
    if (attendedClasses <= (totalClasses / 2)) {
      issues.add("Посещаемость: $attendedClasses/$totalClasses (нужно >50%)");
    }
    if (positiveGradesCount < requiredPositiveGrades) {
      issues.add("Оценки: $positiveGradesCount из $requiredPositiveGrades");
    }
    if (issues.isEmpty) return "Допуск есть";
    return issues.join(', ');
  }
}

class UniversityTheme {
  final String theme;
  final bool access;
  final List<LessonGrade> items;

  const UniversityTheme({
    required this.theme,
    required this.access,
    required this.items,
  });

  factory UniversityTheme.fromJson(Map<String, dynamic> j) {
    return UniversityTheme(
      theme: (j['theme'] ?? '').toString(),
      access: j['access'] == 1 || j['access'] == true || j['access']?.toString().toLowerCase() == 'true',
      items: (j['items'] as List?)
              ?.whereType<Map>()
              .map((e) => LessonGrade.fromUniversityItem(Map<String, dynamic>.from(e)))
              .toList() ??
          [],
    );
  }
}

