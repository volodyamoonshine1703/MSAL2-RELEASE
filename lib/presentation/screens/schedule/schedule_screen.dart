import '../../../core/providers.dart';
// lib/presentation/screens/schedule/schedule_screen.dart
// Navigation: МЭШ-style week strip with day circles

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/local_db_service.dart';
import '../../../data/services/cross_ref_service.dart';

import '../../../data/models/schedule_model.dart';
import '../homework/homework_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../../../core/providers/scaffold_provider.dart';

DateTime _monday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));
bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// ── Providers ──────────────────────────────────────────────────────────────────

final _selectedWeekProvider =
    StateProvider<DateTime>((ref) => _monday(DateTime.now()));

final _selectedDayProvider =
    StateProvider<DateTime>((ref) => DateTime.now());

final calendarModeProvider = StateProvider<bool>((ref) => false);

final _selectedMonthProvider =
    StateProvider<DateTime>((ref) => DateTime(DateTime.now().year, DateTime.now().month));

final _scheduleWeekProvider =
    StreamProvider.family<List<ScheduleDay>, DateTime>((ref, monday) {
  return ref.read(apiServiceProvider).getScheduleWeekStream(monday);
});

/// Fetches all weeks of a month for calendar mode
final _scheduleMonthProvider =
    FutureProvider.family<List<ScheduleDay>, DateTime>((ref, month) async {
  final firstDay = DateTime(month.year, month.month, 1);
  final lastDay = DateTime(month.year, month.month + 1, 0);
  // Fetch all weeks that overlap with this month
  var mon = _monday(firstDay);
  final allDays = <ScheduleDay>[];
  final seen = <String>{};
  while (mon.isBefore(lastDay.add(const Duration(days: 1)))) {
    try {
      final week = await ref.read(apiServiceProvider).getScheduleWeek(mon);
      for (final d in week) {
        if (!seen.contains(d.title)) {
          seen.add(d.title);
          allDays.add(d);
        }
      }
    } catch (_) {}
    mon = mon.add(const Duration(days: 7));
  }
  return allDays;
});

// ── Screen ─────────────────────────────────────────────────────────────────────

class ScheduleScreen extends ConsumerWidget {
  const ScheduleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCalendar = ref.watch(calendarModeProvider);
    if (isCalendar) return const _CalendarModeView();
    return const _WeekModeView();
  }
}

class _WeekModeView extends ConsumerWidget {
  const _WeekModeView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monday   = ref.watch(_selectedWeekProvider);
    final selDay   = ref.watch(_selectedDayProvider);
    final schedAsync = ref.watch(_scheduleWeekProvider(monday));

    return GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -300) {
            final newDay = selDay.add(const Duration(days: 1));
            ref.read(_selectedDayProvider.notifier).state = newDay;
            ref.read(_selectedWeekProvider.notifier).state = _monday(newDay);
          } else if (details.primaryVelocity! > 300) {
            final newDay = selDay.subtract(const Duration(days: 1));
            ref.read(_selectedDayProvider.notifier).state = newDay;
            ref.read(_selectedWeekProvider.notifier).state = _monday(newDay);
          }
        },
        child: Column(
          children: [
            _ScheduleHeader(monday: monday, selectedDay: selDay, ref: ref,
                schedAsync: schedAsync),
            Expanded(
              child: RefreshIndicator(
                color: AppTheme.accent,
                onRefresh: () async {
                  ref.invalidate(_scheduleWeekProvider(monday));
                  await Future.delayed(const Duration(milliseconds: 500));
                },
                child: schedAsync.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: AppTheme.accent)),
                  error: (e, _) => _ErrorView(
                      error: e.toString(),
                      onRetry: () => ref.invalidate(_scheduleWeekProvider(monday))),
                  data: (days) {
                    final fmt  = DateFormat('yyyy-MM-dd');
                    final key  = fmt.format(selDay);
                    final day  = days.firstWhere(
                        (d) => d.title == key,
                        orElse: () => ScheduleDay(title: key, data: const []));
                    return _DayView(day: day, selectedDate: selDay);
                  },
                ),
              ),
            ),
          ],
        ),
      );
  }
}

// ── Calendar Mode ─────────────────────────────────────────────────────────────

class _CalendarModeView extends ConsumerWidget {
  const _CalendarModeView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(_selectedMonthProvider);
    final selDay = ref.watch(_selectedDayProvider);
    final monthAsync = ref.watch(_scheduleMonthProvider(month));

    return GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! < -300) {
            final newDay = selDay.add(const Duration(days: 1));
            ref.read(_selectedDayProvider.notifier).state = newDay;
            ref.read(_selectedMonthProvider.notifier).state =
                DateTime(newDay.year, newDay.month);
          } else if (details.primaryVelocity! > 300) {
            final newDay = selDay.subtract(const Duration(days: 1));
            ref.read(_selectedDayProvider.notifier).state = newDay;
            ref.read(_selectedMonthProvider.notifier).state =
                DateTime(newDay.year, newDay.month);
          }
        },
        child: Column(children: [
          _CalendarHeader(month: month, ref: ref),
          _MonthGrid(month: month, selDay: selDay, ref: ref, monthAsync: monthAsync),
          const Divider(height: 1, color: AppTheme.divider),
          // Lessons for selected day
          Expanded(
            child: monthAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
              error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppTheme.textMuted))),
              data: (days) {
                final fmt = DateFormat('yyyy-MM-dd');
                final key = fmt.format(selDay);
                final day = days.firstWhere((d) => d.title == key,
                    orElse: () => ScheduleDay(title: key, data: const []));
                return _DayView(day: day, selectedDate: selDay);
              },
            ),
          ),
        ]),
      );
  }
}

class _CalendarHeader extends ConsumerWidget {
  final DateTime month;
  final WidgetRef ref;
  const _CalendarHeader({required this.month, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final label = DateFormat('LLLL yyyy', 'ru_RU').format(month);
    final labelStr = label[0].toUpperCase() + label.substring(1);

    return Container(
      color: AppTheme.bgCard,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 16, 10),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppTheme.textSecondary),
              onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
            ),
            if (!Platform.isAndroid && !Platform.isIOS)
              GestureDetector(
                onTap: () => ref.read(_selectedMonthProvider.notifier).state =
                    DateTime(month.year, month.month - 1),
                child: const Icon(Icons.chevron_left, color: AppTheme.textSecondary, size: 22),
              ),
            Expanded(
              child: GestureDetector(
                onTap: () {
                  final now = DateTime.now();
                  ref.read(_selectedMonthProvider.notifier).state = DateTime(now.year, now.month);
                  ref.read(_selectedDayProvider.notifier).state = now;
                },
                child: Text(labelStr, style: const TextStyle(
                  color: AppTheme.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
              ),
            ),
            if (!Platform.isAndroid && !Platform.isIOS)
              GestureDetector(
                onTap: () => ref.read(_selectedMonthProvider.notifier).state =
                    DateTime(month.year, month.month + 1),
                child: const Icon(Icons.chevron_right, color: AppTheme.textSecondary, size: 22),
              ),
            const SizedBox(width: 8),

          ]),
        ),
      ),
    );
  }
}

class _MonthGrid extends ConsumerWidget {
  final DateTime month;
  final DateTime selDay;
  final WidgetRef ref;
  final AsyncValue<List<ScheduleDay>> monthAsync;
  const _MonthGrid({required this.month, required this.selDay, required this.ref, required this.monthAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final firstOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    // Monday=1, so offset = (weekday - 1)
    final startOffset = firstOfMonth.weekday - 1;

    // Collect dates with lessons
    final withLessons = <String>{};
    monthAsync.whenData((list) {
      for (final d in list) {
        if (d.data.isNotEmpty) withLessons.add(d.title);
      }
    });

    final fmt = DateFormat('yyyy-MM-dd');
    const labels = ['пн.', 'вт.', 'ср.', 'чт.', 'пт.', 'сб.', 'вс.'];

    return Container(
      color: AppTheme.bgCard,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(children: [
        // Weekday labels
        Row(children: labels.map((l) => Expanded(
          child: Center(child: Text(l, style: TextStyle(
            color: l == 'сб.' || l == 'вс.' ? AppTheme.error : AppTheme.textMuted,
            fontSize: 11, fontWeight: FontWeight.w500))),
        )).toList()),
        const SizedBox(height: 6),
        // Calendar grid
        ...List.generate(6, (week) {
          return Row(children: List.generate(7, (dow) {
            final dayIndex = week * 7 + dow - startOffset + 1;
            if (dayIndex < 1 || dayIndex > daysInMonth) {
              return const Expanded(child: SizedBox(height: 38));
            }
            final date = DateTime(month.year, month.month, dayIndex);
            final isToday = _sameDay(date, today);
            final isSel = _sameDay(date, selDay);
            final hasLessons = withLessons.contains(fmt.format(date));

            return Expanded(
              child: GestureDetector(
                onTap: () => ref.read(_selectedDayProvider.notifier).state = date,
                child: Container(
                  height: 38,
                  alignment: Alignment.center,
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: isSel ? AppTheme.accent
                            : isToday ? AppTheme.accent.withOpacity(0.15)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text('$dayIndex', style: TextStyle(
                        color: isSel ? Colors.white
                            : isToday ? AppTheme.accent
                            : dow >= 5 ? AppTheme.error
                            : AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: isSel || isToday ? FontWeight.w700 : FontWeight.w400,
                      )),
                    ),
                    Container(
                      width: 4, height: 4,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: hasLessons ? AppTheme.error : Colors.transparent,
                      ),
                    ),
                  ]),
                ),
              ),
            );
          }));
        }),
      ]),
    );
  }
}

// ── МЭШ Header: month title + week strip ─────────────────────────────────────

class _ScheduleHeader extends ConsumerWidget {
  final DateTime monday;
  final DateTime selectedDay;
  final WidgetRef ref;
  final AsyncValue<List<ScheduleDay>> schedAsync;

  const _ScheduleHeader({
    required this.monday,
    required this.selectedDay,
    required this.ref,
    required this.schedAsync,
  });

  static const _weekDayLabels = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateTime.now();
    final days  = List.generate(7, (i) => monday.add(Duration(days: i)));
    final month = DateFormat('LLLL yyyy', 'ru_RU').format(monday);
    final monthStr = month[0].toUpperCase() + month.substring(1);

    // Collect dates that have lessons (for dot indicator)
    final withLessons = <String>{};
    schedAsync.whenData((list) {
      for (final d in list) {
        if (d.data.isNotEmpty) withLessons.add(d.title);
      }
    });

    return Container(
      color: AppTheme.bgCard,
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          // Title row
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 16, 4),
            child: Row(children: [
              IconButton(
                icon: const Icon(Icons.menu_rounded, color: AppTheme.textSecondary),
                onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
              ),
              // Show chevrons only on desktop (mobile uses swipe gestures)
              if (!Platform.isAndroid && !Platform.isIOS)
                GestureDetector(
                  onTap: () {
                    ref.read(_selectedWeekProvider.notifier).state =
                        monday.subtract(const Duration(days: 7));
                    ref.read(_selectedDayProvider.notifier).state =
                        selectedDay.subtract(const Duration(days: 7));
                  },
                  child: const Icon(Icons.chevron_left,
                      color: AppTheme.textSecondary, size: 22),
                ),
              if (!Platform.isAndroid && !Platform.isIOS)
                const SizedBox(width: 6),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Jump to current week
                    final now = DateTime.now();
                    ref.read(_selectedWeekProvider.notifier).state =
                        _monday(now);
                    ref.read(_selectedDayProvider.notifier).state = now;
                  },
                  child: Text(
                    monthStr,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (!Platform.isAndroid && !Platform.isIOS)
                GestureDetector(
                  onTap: () {
                    ref.read(_selectedWeekProvider.notifier).state =
                        monday.add(const Duration(days: 7));
                    ref.read(_selectedDayProvider.notifier).state =
                        selectedDay.add(const Duration(days: 7));
                  },
                  child: const Icon(Icons.chevron_right,
                      color: AppTheme.textSecondary, size: 22),
                ),
              const SizedBox(width: 8),

              if (!Platform.isAndroid && !Platform.isIOS) ...
              [
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => ref.refresh(_scheduleWeekProvider(monday)),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.refresh_outlined,
                        color: AppTheme.textSecondary, size: 20),
                  ),
                ),
              ],
            ]),
          ),

          // Week day strip
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
            child: Row(
              children: List.generate(7, (i) {
                final day     = days[i];
                final isToday = _sameDay(day, today);
                final isSel   = _sameDay(day, selectedDay);
                final fmt     = DateFormat('yyyy-MM-dd');
                final hasLessons = withLessons.contains(fmt.format(day));

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      ref.read(_selectedDayProvider.notifier).state = day;
                    },
                    child: Column(children: [
                      // Day label
                      Text(
                        _weekDayLabels[i],
                        style: TextStyle(
                          color: isSel
                              ? AppTheme.accent
                              : isToday
                                  ? AppTheme.neon
                                  : AppTheme.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Day circle
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: isSel
                              ? AppTheme.accent
                              : isToday
                                  ? AppTheme.accent.withOpacity(0.15)
                                  : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${day.day}',
                          style: TextStyle(
                            color: isSel
                                ? Colors.white
                                : isToday
                                    ? AppTheme.accent
                                    : day.weekday == 7
                                        ? AppTheme.error
                                        : AppTheme.textPrimary,
                            fontSize: 15,
                            fontWeight: isSel || isToday
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      // Dot if has lessons
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasLessons
                              ? (isSel ? Colors.white : AppTheme.accent)
                              : Colors.transparent,
                        ),
                      ),
                    ]),
                  ),
                );
              }),
            ),
          ),
          Divider(height: 1, color: AppTheme.divider),
        ]),
      ),
    );
  }
}

// ── Day view ───────────────────────────────────────────────────────────────────

class _DayView extends ConsumerWidget {
  final ScheduleDay day;
  final DateTime selectedDate;

  const _DayView({required this.day, required this.selectedDate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (day.data.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.event_available_outlined,
              color: AppTheme.textMuted, size: 48),
          const SizedBox(height: 12),
          Text(
            _isWeekend(selectedDate)
                ? 'Выходной день'
                : 'Занятий нет',
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 16),
          ),
        ]),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 80),
      itemCount: day.data.length,
      itemBuilder: (_, i) => _LessonCard(
        lesson: day.data[i],
        number: i + 1,
      ),
    );
  }

  bool _isWeekend(DateTime d) => d.weekday >= 6;
}

// ── Lesson Card — МЭШ style ────────────────────────────────────────────────────

class _LessonCard extends ConsumerWidget {
  final ScheduleLesson lesson;
  final int number;

  const _LessonCard({required this.lesson, required this.number});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showLessonDetail(context, ref),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.divider),
        ),
        child: IntrinsicHeight(
          child: Row(children: [
            // Left accent stripe
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: lesson.typeColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                ),
              ),
            ),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Row 1: lesson number + time + room
                    Row(children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: lesson.typeColor.withOpacity(0.18),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$number',
                          style: TextStyle(
                            color: lesson.typeColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${lesson.startTime} — ${lesson.endTime}',
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Room — wrapped in Flexible to prevent overflow
                      if (lesson.corps.isNotEmpty || lesson.auditory != null)
                        Flexible(
                          child: Text(
                            [
                              if (lesson.corps.isNotEmpty) lesson.corps,
                              if (lesson.auditory?.isNotEmpty == true)
                                'ауд. ${lesson.auditory}',
                            ].join(', '),
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 11),
                            textAlign: TextAlign.right,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                    ]),
                    const SizedBox(height: 6),

                    // Row 2: discipline name
                    Text(
                      lesson.discipline,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),

                    // Row 3: teacher + type badge
                    Row(children: [
                      Expanded(
                        child: Text(
                          lesson.teacher,
                          style: const TextStyle(
                              color: AppTheme.textMuted, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: lesson.typeColor.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            lesson.typeLabel,
                            style: TextStyle(
                              color: lesson.typeColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  void _showLessonDetail(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _LessonDetailSheet(lesson: lesson, ref: ref),
    );
  }
}

// ── Lesson Detail Bottom Sheet ────────────────────────────────────────────────

class _LessonDetailSheet extends ConsumerStatefulWidget {
  final ScheduleLesson lesson;
  final WidgetRef ref;

  const _LessonDetailSheet({required this.lesson, required this.ref});

  @override
  ConsumerState<_LessonDetailSheet> createState() => _LessonDetailSheetState();
}

class _LessonDetailSheetState extends ConsumerState<_LessonDetailSheet> {
  bool? _lectureAttended;
  bool? _selectedAttendance;
  bool _attendanceConfirmed = false;
  bool _attendanceLoading = true;
  bool _saving = false;

  bool get _isLecture => widget.lesson.type.toLowerCase().contains('лекц');

  /// Parse end time from lesson and check if the lesson has ended
  bool get _lessonEnded {
    try {
      final now = DateTime.now();
      final lessonDate = widget.lesson.lessonDate ?? now;
      final endStr = widget.lesson.endTime; // "HH:mm"
      if (endStr == '--:--' || endStr.length < 5) return false;
      final parts = endStr.split(':');
      final endDt = DateTime(
        lessonDate.year, lessonDate.month, lessonDate.day,
        int.parse(parts[0]), int.parse(parts[1]),
      );
      return now.isAfter(endDt);
    } catch (_) {
      return false;
    }
  }

  /// Check if lesson is happening today
  bool get _isToday {
    final now = DateTime.now();
    final ld = widget.lesson.lessonDate;
    if (ld == null) return false;
    return ld.year == now.year && ld.month == now.month && ld.day == now.day;
  }

  @override
  void initState() {
    super.initState();
    if (_isLecture) {
      _loadAttendance();
    } else {
      _attendanceLoading = false;
    }
  }

  Future<void> _loadAttendance() async {
    final lessonDate = widget.lesson.day;
    final result = await ref.read(localDbServiceProvider).getLectureAttendance(
      widget.lesson.disciplineId, lessonDate,
    );
    if (mounted) {
      setState(() {
        _lectureAttended = result;
        _attendanceConfirmed = result != null;
        _attendanceLoading = false;

        // Auto-mark missed if lesson ended and not confirmed
        if (_lessonEnded && result == null) {
          _autoMarkMissed();
        }
      });
    }
  }

  Future<void> _autoMarkMissed() async {
    try {
      await ref.read(crossRefServiceProvider).confirmLectureAttendance(
        disciplineId: widget.lesson.disciplineId,
        lessonDate: widget.lesson.day,
        lessonId: widget.lesson.id,
        attended: false,
      );

      if (mounted) {
        setState(() {
          _lectureAttended = false;
          _attendanceConfirmed = true;
        });
        // Refresh dashboard attendance stats
        widget.ref.refresh(progressWithLessonsProvider);
      }
    } catch (_) {}
  }

  Future<void> _confirmAttendance() async {
    if (_selectedAttendance == null) return;
    setState(() => _saving = true);
    try {
      final confirmed = await ref.read(crossRefServiceProvider).confirmLectureAttendance(
        disciplineId: widget.lesson.disciplineId,
        lessonDate: widget.lesson.day,
        lessonId: widget.lesson.id,
        attended: _selectedAttendance!,
      );
      if (confirmed) {

      }
      if (mounted) {
        setState(() {
          _lectureAttended = _selectedAttendance;
          _attendanceConfirmed = true;
          _saving = false;
        });
        // Refresh dashboard attendance stats
        widget.ref.refresh(progressWithLessonsProvider);
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.lesson;
    final dateStr = lesson.day.isNotEmpty
        ? (DateTime.tryParse(lesson.day) != null
            ? DateFormat('d MMMM yyyy, EEEE', 'ru_RU')
                .format(DateTime.parse(lesson.day))
            : lesson.day)
        : '';

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 20, offset: Offset(0, -4)),
          ],
        ),
        child: ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 16),
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Lesson info header
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: lesson.typeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(
                  _isLecture ? Icons.menu_book_rounded : Icons.school_outlined,
                  color: lesson.typeColor, size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(lesson.discipline,
                    style: const TextStyle(color: AppTheme.textPrimary,
                        fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text('${lesson.startTime} — ${lesson.endTime}  •  ${lesson.typeLabel}',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                ],
              )),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded, color: AppTheme.textMuted, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: AppTheme.bgSurface,
                  padding: const EdgeInsets.all(6),
                ),
              ),
            ]),
            const SizedBox(height: 8),

            // Teacher + room + date
            Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(children: [
                _InfoRow(Icons.person_outline, 'Преподаватель', lesson.teacher),
                if (lesson.corps.isNotEmpty || lesson.auditory != null) ...[
                  const Divider(color: AppTheme.divider, height: 16),
                  _InfoRow(Icons.location_on_outlined, 'Аудитория', [
                    if (lesson.corps.isNotEmpty) lesson.corps,
                    if (lesson.auditory?.isNotEmpty == true) 'ауд. ${lesson.auditory}',
                  ].join(', ')),
                ],
                if (dateStr.isNotEmpty) ...[
                  const Divider(color: AppTheme.divider, height: 16),
                  _InfoRow(Icons.calendar_today_outlined, 'Дата', dateStr),
                ],
              ]),
            ),
            const SizedBox(height: 16),

            // ── Lecture attendance block ──────────────────────────────────
            if (_isLecture) ...[
              _buildAttendanceBlock(),
              const SizedBox(height: 16),
            ],

            // ── Homework block ───────────────────────────────────────────
            if (lesson.id.isNotEmpty) ...[
              const Text('Домашнее задание',
                style: TextStyle(color: AppTheme.textSecondary,
                    fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
              const SizedBox(height: 8),
              HomeworkCard(lesson: lesson),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAttendanceBlock() {
    if (_attendanceLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(
          child: SizedBox(width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent)),
        ),
      );
    }

    // Already confirmed — show read-only result
    if (_attendanceConfirmed && _lectureAttended != null) {
      final attended = _lectureAttended!;
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: (attended ? AppTheme.success : AppTheme.error).withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: (attended ? AppTheme.success : AppTheme.error).withOpacity(0.3)),
        ),
        child: Row(children: [
          Icon(attended ? Icons.check_circle_rounded : Icons.cancel_rounded,
              color: attended ? AppTheme.success : AppTheme.error, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(attended ? 'Вы присутствовали на лекции' : 'Неявка на лекцию',
                style: TextStyle(
                  color: attended ? AppTheme.success : AppTheme.error,
                  fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(attended
                ? 'Явка подтверждена'
                : _lessonEnded
                    ? 'Лекция закончилась — автоматическая неявка'
                    : 'Явка подтверждена',
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ])),
        ]),
      );
    }

    // Lesson already ended and not confirmed — shouldn't normally reach here
    // because _loadAttendance auto-marks, but just in case:
    if (_lessonEnded) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.error.withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.timer_off_outlined, color: AppTheme.error, size: 24),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Время отметки истекло',
                style: TextStyle(color: AppTheme.error,
                    fontSize: 14, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            const Text('Лекция закончилась — засчитано как неявка',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          ])),
        ]),
      );
    }

    // Not yet confirmed, lesson still ongoing — show choice
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.fact_check_outlined, color: AppTheme.accent, size: 20),
          const SizedBox(width: 8),
          const Text('Отметить присутствие',
              style: TextStyle(color: AppTheme.accent,
                  fontSize: 14, fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 4),
        const Text(
          'Подтвердите, были ли вы на лекции. После подтверждения изменить нельзя.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: _AttendanceChoiceBtn(
            label: 'Присутствовал',
            icon: Icons.check_rounded,
            color: AppTheme.success,
            selected: _selectedAttendance == true,
            onTap: () => setState(() => _selectedAttendance = true),
          )),
          const SizedBox(width: 10),
          Expanded(child: _AttendanceChoiceBtn(
            label: 'Отсутствовал',
            icon: Icons.close_rounded,
            color: AppTheme.error,
            selected: _selectedAttendance == false,
            onTap: () => setState(() => _selectedAttendance = false),
          )),
        ]),
        if (_selectedAttendance != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _confirmAttendance,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: _saving
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Подтвердить',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ]),
    );
  }
}

// ── Info row helper ───────────────────────────────────────────────────────────

class _InfoRow extends ConsumerWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(children: [
    Icon(icon, color: AppTheme.textMuted, size: 16),
    const SizedBox(width: 8),
    Text('$label: ', style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
    Expanded(child: Text(value,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
        overflow: TextOverflow.ellipsis)),
  ]);
}

// ── Attendance choice button ──────────────────────────────────────────────────

class _AttendanceChoiceBtn extends ConsumerWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _AttendanceChoiceBtn({
    required this.label, required this.icon,
    required this.color, required this.selected, required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.15) : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: selected ? color : AppTheme.divider,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: selected ? color : AppTheme.textMuted, size: 22),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: selected ? color : AppTheme.textMuted,
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400)),
      ]),
    ),
  );
}

// ── Error view ─────────────────────────────────────────────────────────────────

class _ErrorView extends ConsumerWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  color: AppTheme.textMuted, size: 52),
              const SizedBox(height: 16),
              const Text('Не удалось загрузить расписание',
                  style: TextStyle(
                      color: AppTheme.textSecondary, fontSize: 15),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(error,
                  style: const TextStyle(
                      color: AppTheme.textMuted, fontSize: 11),
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
}

