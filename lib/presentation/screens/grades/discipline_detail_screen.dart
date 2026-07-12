import '../../../core/providers.dart';
// lib/presentation/screens/grades/discipline_detail_screen.dart
//
// Lecture attendance:
//   - Lectures are taken ONLY from the schedule (GET /schedule?from=...&to=...)
//   - Manual attendance confirmation stored in local DB (immutable after confirm)
//   - Unconfirmed past lectures → counted as missed
//   - All other attendance (practice, seminar) → from server countGrape/flawGrape

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/grade_model.dart';
import '../../../data/models/schedule_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/local_db_service.dart';

final _inFmt    = DateFormat('dd.MM.yyyy');
final _longFmt  = DateFormat('d MMMM yyyy', 'ru_RU');
final _shortFmt = DateFormat('d MMM', 'ru_RU');

String _fmtLong(String raw) {
  try { return _longFmt.format(_inFmt.parseStrict(raw)); } catch (_) {}
  try { return _longFmt.format(DateTime.parse(raw)); } catch (_) {}
  return raw;
}

String _fmtShort(String raw) {
  try { return _shortFmt.format(_inFmt.parseStrict(raw)); } catch (_) {}
  try { return _shortFmt.format(DateTime.parse(raw)); } catch (_) {}
  return raw;
}

Color _gradeColor(int g) {
  switch (g) {
    case 5:  return AppTheme.success;
    case 4:  return const Color(0xFF7CB9E8);
    case 3:  return AppTheme.warning;
    case 2:  return AppTheme.error;
    default: return AppTheme.textMuted;
  }
}

// ── Remaining practice/seminar from schedule ──────────────────────────────────

class _ScheduleSummary {
  final int practicePast, practiceLeft;
  final int seminarPast,  seminarLeft;
  const _ScheduleSummary({
    required this.practicePast,  required this.practiceLeft,
    required this.seminarPast,   required this.seminarLeft,
  });
}

final _scheduleSummaryProvider =
    FutureProvider.family<_ScheduleSummary, String>((ref, disciplineId) async {
  final now   = _semesterStart().subtract(const Duration(days: 1));
  final end   = DateTime.now().month >= 9
      ? DateTime(DateTime.now().year + 1, 1, 31)
      : DateTime(DateTime.now().year, 8, 31); // through exam period
  final today = DateTime.now();

  int practicePast = 0, practiceLeft = 0;
  int seminarPast  = 0, seminarLeft  = 0;

  var current = _semesterStart().subtract(
      Duration(days: _semesterStart().weekday - 1));
  while (current.isBefore(end)) {
    try {
      final days = await ref.read(apiServiceProvider).getScheduleWeek(current);
      for (final day in days) {
        for (final lesson in day.data) {
          if (lesson.disciplineId != disciplineId) continue;
          final dt = lesson.lessonDate ?? day.date;
          if (lesson.isPractice) {
            dt.isBefore(today) ? practicePast++ : practiceLeft++;
          } else if (lesson.isSeminar) {
            dt.isBefore(today) ? seminarPast++ : seminarLeft++;
          }
        }
      }
    } catch (_) {}
    current = current.add(const Duration(days: 7));
  }
  return _ScheduleSummary(
    practicePast:  practicePast,  practiceLeft: practiceLeft,
    seminarPast:   seminarPast,   seminarLeft:  seminarLeft,
  );
});

DateTime _semesterStart() {
  final now = DateTime.now();
  return now.month >= 9 ? DateTime(now.year, 9, 1) : DateTime(now.year, 2, 1);
}

// ── Lecture data from schedule ─────────────────────────────────────────────────

class _LectureInfo {
  final DateTime date;
  final String dateKey; // 'dd.MM.yyyy'
  final bool isPast;
  final bool? attended; // null = not confirmed yet

  const _LectureInfo({
    required this.date,
    required this.dateKey,
    required this.isPast,
    this.attended,
  });
}

// ── Provider: lectures from schedule for a discipline ──────────────────────────

final _lecturesProvider = FutureProvider.family<List<_LectureInfo>, String>(
  (ref, disciplineId) async {
    final now   = DateTime.now();
    final start = _semesterStart();

    // Collect all weeks from semester start to now+4 weeks (upcoming)
    final lectures = <_LectureInfo>[];
    var current = start.subtract(Duration(days: start.weekday - 1));
    final limit = now.add(const Duration(days: 28));

    while (current.isBefore(limit)) {
      try {
        final days = await ref.read(apiServiceProvider).getScheduleWeek(current);
        for (final day in days) {
          for (final lesson in day.data) {
            if (lesson.disciplineId != disciplineId) continue;
            if (!lesson.isLecture) continue;

            final lessonDt = lesson.lessonDate ?? day.date;
            final dateKey  = DateFormat('dd.MM.yyyy').format(lessonDt);
            final isPast   = lessonDt.isBefore(now);

            // Load attendance from DB
            final attended = isPast
                ? await ref.read(localDbServiceProvider)
                    .getLectureAttendance(disciplineId, dateKey)
                : null;

            lectures.add(_LectureInfo(
              date:     lessonDt,
              dateKey:  dateKey,
              isPast:   isPast,
              attended: attended,
            ));
          }
        }
      } catch (_) {}
      current = current.add(const Duration(days: 7));
    }

    // Deduplicate by date
    final seen = <String>{};
    final unique = <_LectureInfo>[];
    for (final l in lectures) {
      if (seen.add(l.dateKey)) unique.add(l);
    }
    unique.sort((a, b) => a.date.compareTo(b.date));
    return unique;
  },
);

// ── Main screen ────────────────────────────────────────────────────────────────

class DisciplineDetailScreen extends ConsumerWidget {
  final ProgressItem item;
  const DisciplineDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lecturesAsync = ref.watch(_lecturesProvider(item.disciplineId));

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: Text(item.discipline, maxLines: 2,
            style: const TextStyle(fontSize: 15)),
        backgroundColor: AppTheme.bgDark,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, size: 20),
            tooltip: 'Обновить',
            onPressed: () => ref.refresh(_lecturesProvider(item.disciplineId)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Average grade card
          if (item.universityModules != null) ...[
            _UniversityBarsCard(item: item),
            const SizedBox(height: 14),
          ] else if (item.averageGrade > 0) ...[
            _AvgGradeCard(avg: item.averageGrade, dist: item.gradeDistribution),
            const SizedBox(height: 14),
          ],

          // Combined attendance card: server data + manual lecture confirmations
          lecturesAsync.when(
            loading: () => item.countTotal > 0 ? Column(children: [
              _AttendanceCard(
                total: item.countTotal,
                missed: item.missedTotal,
                lectureExtra: 0,
                label: 'Посещаемость',
              ),
              const SizedBox(height: 14),
            ]) : const SizedBox.shrink(),
            error: (_, __) => item.countTotal > 0 ? Column(children: [
              _AttendanceCard(
                total: item.countTotal,
                missed: item.missedTotal,
                lectureExtra: 0,
                label: 'Посещаемость',
              ),
              const SizedBox(height: 14),
            ]) : const SizedBox.shrink(),
            data: (lectures) {
              // Count manually confirmed lecture misses
              final pastLectures = lectures.where((l) => l.isPast).toList();
              final confirmedMissed = pastLectures.where((l) => l.attended == false).length;
              // Unconfirmed past lectures also count as missed
              final unconfirmedMissed = pastLectures.where((l) => l.attended == null).length;
              final lectureMissedTotal = confirmedMissed + unconfirmedMissed;
              return Column(children: [
                if (item.countTotal > 0) ...[
                  _AttendanceCard(
                    total: item.countTotal + pastLectures.length,
                    missed: item.missedTotal + lectureMissedTotal,
                    lectureExtra: lectureMissedTotal,
                    label: 'Посещаемость',
                  ),
                  const SizedBox(height: 14),
                ],

                // Lecture attendance detail
                if (lectures.isEmpty) const SizedBox.shrink()
                else
                _LectureAttendanceCard(
                  disciplineId: item.disciplineId,
                  lectures: lectures,
                  onConfirmed: () =>
                      ref.refresh(_lecturesProvider(item.disciplineId)),
                ),
                const SizedBox(height: 14),
              ]);
            },
          ),

          // Debt
          if (item.hasDebt) ...[
            _DebtCard(item: item),
            const SizedBox(height: 14),
          ],

          // Per-lesson grades list (from /progress/details)
          if (item.universityModules != null) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Модули (БАРС)',
                  style: TextStyle(color: AppTheme.textSecondary,
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            ...item.universityModules!.map((m) => _UniversityModuleCard(module: m)),
          ] else if (item.lessons.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text('Все занятия (из дневника)',
                  style: TextStyle(color: AppTheme.textSecondary,
                      fontSize: 12, fontWeight: FontWeight.w600)),
            ),
            ...item.lessons.reversed.map((l) => _LessonRow(lesson: l)),
          ],

          const SizedBox(height: 30),
        ],
      ),
    );
  }
}

// ── Average grade card ─────────────────────────────────────────────────────────

class _AvgGradeCard extends ConsumerWidget {
  final double avg;
  final Map<int, int> dist;
  const _AvgGradeCard({required this.avg, required this.dist});

  Color get _avgColor {
    if (avg >= 4.5) return AppTheme.success;
    if (avg >= 3.5) return const Color(0xFF7CB9E8);
    if (avg >= 2.5) return AppTheme.warning;
    return AppTheme.error;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sorted = dist.entries.toList()..sort((a, b) => b.key.compareTo(a.key));
    final total  = dist.values.fold(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Оценки за семестр',
            style: TextStyle(color: AppTheme.textSecondary,
                fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(avg.toStringAsFixed(2),
                style: TextStyle(color: _avgColor, fontSize: 36,
                    fontWeight: FontWeight.w800)),
            Text('средний балл',
                style: TextStyle(color: _avgColor.withOpacity(0.7), fontSize: 11)),
          ]),
          const SizedBox(width: 20),
          Expanded(child: Column(
            children: sorted.map((e) {
              final c    = _gradeColor(e.key);
              final frac = total > 0 ? e.value / total : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Container(
                    width: 20, height: 20, alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: c.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(5)),
                    child: Text('${e.key}',
                        style: TextStyle(color: c, fontSize: 11,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: frac,
                      backgroundColor: AppTheme.bgSurface,
                      valueColor: AlwaysStoppedAnimation<Color>(c),
                      minHeight: 8,
                    ),
                  )),
                  const SizedBox(width: 6),
                  Text('${e.value}',
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 11)),
                ]),
              );
            }).toList(),
          )),
        ]),
      ]),
    );
  }
}

// ── General attendance card ────────────────────────────────────────────────────

class _AttendanceCard extends ConsumerWidget {
  final int total, missed, lectureExtra;
  final String label;
  const _AttendanceCard({
    required this.total,
    required this.missed,
    this.lectureExtra = 0,
    required this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attended = total - missed;
    final rate     = total > 0 ? attended / total : 1.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label,
              style: const TextStyle(color: AppTheme.textSecondary,
                  fontSize: 11, fontWeight: FontWeight.w600)),
          const Spacer(),
          Text('${(rate * 100).round()}%',
              style: TextStyle(
                color: rate > 0.75 ? AppTheme.accent
                    : rate > 0.5 ? AppTheme.warning : AppTheme.error,
                fontSize: 13, fontWeight: FontWeight.w700,
              )),
        ]),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: rate,
            backgroundColor: AppTheme.bgSurface,
            valueColor: AlwaysStoppedAnimation<Color>(
              rate > 0.75 ? AppTheme.accent
                  : rate > 0.5 ? AppTheme.warning : AppTheme.error),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 8),
        Row(children: [
          _Stat('Всего',     '$total',    AppTheme.textSecondary),
          const SizedBox(width: 12),
          _Stat('Посещено',  '$attended', AppTheme.accent),
          const SizedBox(width: 12),
          _Stat('Пропущено', '$missed',   AppTheme.error),
        ]),
        if (lectureExtra > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.school_outlined, color: AppTheme.warning, size: 13),
              const SizedBox(width: 6),
              Text('в т.ч. $lectureExtra пропуск(а) лекций (ручные + неотмеченные)',
                  style: const TextStyle(color: AppTheme.warning, fontSize: 10)),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Lecture attendance card (from schedule) ────────────────────────────────────

class _LectureAttendanceCard extends ConsumerStatefulWidget {
  final String disciplineId;
  final List<_LectureInfo> lectures;
  final VoidCallback onConfirmed;

  const _LectureAttendanceCard({
    required this.disciplineId,
    required this.lectures,
    required this.onConfirmed,
  });

  @override
  ConsumerState<_LectureAttendanceCard> createState() => _LectureAttendanceCardState();
}

class _LectureAttendanceCardState extends ConsumerState<_LectureAttendanceCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final now     = DateTime.now();
    final past    = widget.lectures.where((l) => l.isPast).toList();
    final upcoming = widget.lectures.where((l) => !l.isPast).toList();
    final confirmed = past.where((l) => l.attended != null).length;
    final attended  = past.where((l) => l.attended == true).length;
    final missed    = past.where((l) =>
        l.attended == false || (l.attended == null)).length;
    final rate = past.isNotEmpty ? attended / past.length : 1.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppTheme.accent.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(children: [
            const Icon(Icons.school_outlined,
                color: AppTheme.accent, size: 16),
            const SizedBox(width: 8),
            const Text('Лекции (из расписания)',
                style: TextStyle(color: AppTheme.accent,
                    fontSize: 12, fontWeight: FontWeight.w700)),
            const Spacer(),
            Text('${(rate * 100).round()}%',
                style: TextStyle(
                  color: rate > 0.75 ? AppTheme.accent
                      : rate > 0.5 ? AppTheme.warning : AppTheme.error,
                  fontSize: 12, fontWeight: FontWeight.w700)),
            const SizedBox(width: 6),
            Icon(_expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
                color: AppTheme.textMuted, size: 18),
          ]),
        ),
        const SizedBox(height: 10),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: rate,
            backgroundColor: AppTheme.bgSurface,
            valueColor: AlwaysStoppedAnimation<Color>(
              rate > 0.75 ? AppTheme.accent
                  : rate > 0.5 ? AppTheme.warning : AppTheme.error),
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 8),

        // Stats
        Row(children: [
          _Stat('Всего',       '${widget.lectures.length}', AppTheme.textSecondary),
          const SizedBox(width: 12),
          _Stat('Прошло',      '${past.length}',            AppTheme.textSecondary),
          const SizedBox(width: 12),
          _Stat('Посещено',    '$attended',                 AppTheme.success),
          const SizedBox(width: 12),
          _Stat('Пропущено',   '$missed',                   AppTheme.error),
          const SizedBox(width: 12),
          _Stat('Предстоит',   '${upcoming.length}',        AppTheme.textMuted),
        ]),

        // Unconfirmed warning
        if (past.isNotEmpty && confirmed < past.length) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.07),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppTheme.warning.withOpacity(0.25)),
            ),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  color: AppTheme.warning, size: 13),
              const SizedBox(width: 6),
              Expanded(child: Text(
                '${past.length - confirmed} лекций без отметки — засчитаны как пропуски',
                style: const TextStyle(color: AppTheme.warning, fontSize: 10),
              )),
            ]),
          ),
        ],

        // Expanded: list of lectures
        if (_expanded) ...[
          const SizedBox(height: 12),
          const Divider(color: AppTheme.divider, height: 1),
          const SizedBox(height: 8),
          ...widget.lectures.map((l) => _LectureRow(
            info: l,
            disciplineId: widget.disciplineId,
            onConfirmed: widget.onConfirmed,
          )),
        ],
      ]),
    );
  }
}

// ── Lecture row with confirm button ───────────────────────────────────────────

class _LectureRow extends ConsumerStatefulWidget {
  final _LectureInfo info;
  final String disciplineId;
  final VoidCallback onConfirmed;

  const _LectureRow({
    required this.info,
    required this.disciplineId,
    required this.onConfirmed,
  });

  @override
  ConsumerState<_LectureRow> createState() => _LectureRowState();
}

class _LectureRowState extends ConsumerState<_LectureRow> {
  bool _saving = false;

  Future<void> _confirm(bool attended) async {
    setState(() => _saving = true);
    await ref.read(localDbServiceProvider).confirmLectureAttendance(
      disciplineId: widget.disciplineId,
      lessonDate:   widget.info.dateKey,
      lessonId:     '',
      attended:     attended,
    );
    widget.onConfirmed();
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final l         = widget.info;
    final confirmed = l.attended != null;
    final isFuture  = !l.isPast;

    Color dotColor;
    if (isFuture)         dotColor = AppTheme.textMuted;
    else if (!confirmed)  dotColor = AppTheme.warning;
    else if (l.attended!) dotColor = AppTheme.success;
    else                  dotColor = AppTheme.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
              shape: BoxShape.circle, color: dotColor)),
        const SizedBox(width: 10),
        SizedBox(
          width: 80,
          child: Text(
            DateFormat('d MMM', 'ru_RU').format(l.date),
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 11)),
        ),
        Expanded(child: Text(
          isFuture
              ? 'Предстоит'
              : confirmed
                  ? (l.attended! ? 'Присутствие ✓' : 'Пропуск ✓')
                  : 'Не отмечено (пропуск)',
          style: TextStyle(
            color: isFuture
                ? AppTheme.textMuted
                : confirmed
                    ? (l.attended! ? AppTheme.success : AppTheme.error)
                    : AppTheme.warning,
            fontSize: 11,
          ),
        )),
        // Confirm buttons — only for past unconfirmed lectures
        if (l.isPast && !confirmed)
          _saving
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppTheme.accent))
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  _ConfirmBtn(
                    icon: Icons.check_rounded,
                    color: AppTheme.success,
                    onTap: () => _confirm(true),
                  ),
                  const SizedBox(width: 4),
                  _ConfirmBtn(
                    icon: Icons.close_rounded,
                    color: AppTheme.error,
                    onTap: () => _confirm(false),
                  ),
                ]),
      ]),
    );
  }
}

class _ConfirmBtn extends ConsumerWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ConfirmBtn({required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 28, height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color, size: 15),
    ),
  );
}

// ── Debt card ──────────────────────────────────────────────────────────────────

class _DebtCard extends ConsumerWidget {
  final ProgressItem item;
  const _DebtCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twos   = item.lessons.where((l) => l.grades.contains(2)).toList();
    final n      = item.debtCount;
    final suffix = n == 1 ? 'ь' : n < 5 ? 'и' : 'ей';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.error.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('«2»',
              style: TextStyle(color: AppTheme.error, fontSize: 18,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text('$n задолженност$suffix',
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 10),
        ...twos.map((l) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            const Icon(Icons.circle, size: 6, color: AppTheme.error),
            const SizedBox(width: 8),
            Text(_fmtLong(l.date),
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(width: 8),
            ...l.grades.where((g) => g == 2).map((g) => Container(
              margin: const EdgeInsets.only(right: 3),
              width: 20, height: 20, alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(5)),
              child: Text('$g', style: const TextStyle(
                  color: AppTheme.error, fontSize: 11,
                  fontWeight: FontWeight.w700)),
            )),
          ]),
        )),
      ]),
    );
  }
}

// ── Per-lesson row (read-only, from /progress/details) ────────────────────────

class _LessonRow extends ConsumerWidget {
  final LessonGrade lesson;
  const _LessonRow({required this.lesson});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMissed = !lesson.turnout;
    final statusText = lesson.status ?? (isMissed ? 'Пропуск' : lesson.lateness ? 'Опоздание' : 'Присутствие');

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: (lesson.hasDebt || lesson.status != null)
                ? AppTheme.error.withOpacity(0.3)
                : isMissed
                    ? AppTheme.error.withOpacity(0.15)
                    : AppTheme.divider,
          )),
      child: Row(children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isMissed || lesson.status != null)
                ? AppTheme.error
                : lesson.lateness
                    ? AppTheme.warning
                    : AppTheme.success,
          )),
        const SizedBox(width: 10),
        SizedBox(
          width: 72,
          child: Text(_fmtShort(lesson.date),
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 11))),
        Expanded(child: Text(
          statusText,
          style: TextStyle(
            color: (isMissed || lesson.status != null) ? AppTheme.error
                : lesson.lateness ? AppTheme.warning : AppTheme.textMuted,
            fontSize: 11,
            fontWeight: lesson.status != null ? FontWeight.w600 : FontWeight.normal,
          ),
        )),
        if (lesson.grades.isNotEmpty)
          Wrap(spacing: 4,
            children: lesson.grades.map((g) {
              final c = _gradeColor(g);
              return Container(
                width: 24, height: 24, alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: c.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('$g',
                    style: TextStyle(color: c, fontSize: 12,
                        fontWeight: FontWeight.w700)),
              );
            }).toList()),
      ]),
    );
  }
}

// ── University BARS Modules ───────────────────────────────────────────────────

class _UniversityBarsCard extends ConsumerWidget {
  final ProgressItem item;
  const _UniversityBarsCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Текущий результат (БАРС)',
            style: TextStyle(color: AppTheme.textSecondary,
                fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Row(children: [
          Text(item.barsScore.toStringAsFixed(2),
              style: const TextStyle(color: AppTheme.accent, fontSize: 36,
                  fontWeight: FontWeight.w800)),
          const SizedBox(width: 12),
          Expanded(child: Text(
            item.access ? '✓ Допуск' : '✗ Не допущен',
            style: TextStyle(color: item.access ? AppTheme.success : AppTheme.warning,
                fontSize: 14, fontWeight: FontWeight.w600),
          )),
        ]),
        if (item.debtReport.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(item.debtReport,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ],
      ]),
    );
  }
}

class _UniversityModuleCard extends ConsumerStatefulWidget {
  final UniversityModule module;
  const _UniversityModuleCard({required this.module});

  @override
  ConsumerState<_UniversityModuleCard> createState() => _UniversityModuleCardState();
}

class _UniversityModuleCardState extends ConsumerState<_UniversityModuleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(
          title: Text(widget.module.module,
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w600)),
          subtitle: Text('Текущий результат: ${widget.module.mediumScore}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
          trailing: Icon(_expanded ? Icons.expand_less : Icons.expand_more,
              color: AppTheme.textMuted),
          onTap: () => setState(() => _expanded = !_expanded),
        ),
        if (_expanded) ...[
          const Divider(height: 1, color: AppTheme.divider),
          ...widget.module.themes.map((t) => _UniversityThemeItem(theme: t)),
        ],
      ]),
    );
  }
}

class _UniversityThemeItem extends ConsumerWidget {
  final UniversityTheme theme;
  const _UniversityThemeItem({required this.theme});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(theme.theme,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.3))),
          const SizedBox(width: 8),
          Text(theme.access ? 'Допуск' : 'Не допущен',
              style: TextStyle(
                  color: theme.access ? AppTheme.success : AppTheme.error,
                  fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: theme.items.map((i) => _UniversityLessonCell(lesson: i)).toList(),
        ),
      ]),
    );
  }
}

class _UniversityLessonCell extends ConsumerWidget {
  final LessonGrade lesson;
  const _UniversityLessonCell({required this.lesson});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMissed = !lesson.turnout;
    final ball = lesson.grades.isNotEmpty ? lesson.grades.first : 0;
    return Container(
      width: 120,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMissed ? AppTheme.error.withOpacity(0.05) : AppTheme.bgSurface,
        border: Border.all(color: isMissed ? AppTheme.error.withOpacity(0.2) : AppTheme.divider),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(children: [
        Text(_fmtShort(lesson.date),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(lesson.teacher,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        if (isMissed)
          const Text('Пропуск', style: TextStyle(color: AppTheme.error, fontSize: 11, fontWeight: FontWeight.w600))
        else if (ball > 0)
          Text('Балл: $ball', style: const TextStyle(color: AppTheme.success, fontSize: 11, fontWeight: FontWeight.w600))
        else
          const Text('Без оценки', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
      ]),
    );
  }
}


// ── Schedule row widget ──────────────────────────────────────────────────────

class _ScheduleRow extends ConsumerWidget {
  final String label;
  final int past, left;
  const _ScheduleRow({required this.label, required this.past, required this.left});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = past + left;
    final frac  = total > 0 ? past / total : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        SizedBox(width: 64,
          child: Text(label, style: const TextStyle(
              color: AppTheme.textMuted, fontSize: 11))),
        Expanded(child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: frac,
            backgroundColor: AppTheme.bgSurface,
            valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.accent),
            minHeight: 7,
          ),
        )),
        const SizedBox(width: 8),
        Text('$past / $total',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
        if (left > 0) ...[
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('ещё $left',
                style: const TextStyle(color: AppTheme.accent,
                    fontSize: 9, fontWeight: FontWeight.w600)),
          ),
        ],
      ]),
    );
  }
}

// ── Helper stat widget ─────────────────────────────────────────────────────────

class _Stat extends ConsumerWidget {
  final String label, value;
  final Color color;
  const _Stat(this.label, this.value, this.color);

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(children: [
    Text(value, style: TextStyle(color: color, fontSize: 16,
        fontWeight: FontWeight.w700)),
    Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
  ]);
}
