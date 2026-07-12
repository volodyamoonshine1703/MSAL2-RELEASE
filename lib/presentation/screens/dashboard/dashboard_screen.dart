import '../../../core/providers.dart';
// lib/presentation/screens/dashboard/dashboard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/api_service.dart';
import '../../../data/models/schedule_model.dart';
import '../../../data/models/grade_model.dart';
import '../grades/grades_screen.dart';
import '../grades/debt_manager_screen.dart';
import '../grades/admission_manager_screen.dart';
import '../plan/recovery_plan_screen.dart';
import '../../../core/providers/scaffold_provider.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

final todayScheduleProvider = FutureProvider<List<ScheduleLesson>>((ref) async {
  final days = await ref.read(apiServiceProvider).getToday();
  return days.isEmpty ? [] : days.first.data;
});

final progressWithLessonsProvider = FutureProvider<List<ProgressItem>>((ref) async {
  return ref.read(apiServiceProvider).getProgressWithLessons();
});

/// Fetches student info (rating, etc) - only relevant for University LK.
final studentInfoProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getStudentInfo();
});

/// Selected month for attendance stats. Defaults to current month.
final attendanceMonthProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month);
});

// ── Screen ────────────────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user          = ref.read(authServiceProvider).currentUser;
    final todayAsync    = ref.watch(todayScheduleProvider);
    final progressAsync = ref.watch(progressWithLessonsProvider);
    final selMonth      = ref.watch(attendanceMonthProvider);

    return RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.bgCard,
        onRefresh: () async {
          ref.refresh(todayScheduleProvider);
          ref.refresh(progressWithLessonsProvider);
          ref.refresh(studentInfoProvider);
        },
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context, ref, user?.name ?? ''),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const SizedBox(height: 16),

                  // ── Stats row ──────────────────────────────────────────
                  progressAsync.when(
                    loading: () => const _StatsRowShimmer(),
                    error: (e, _) => _ErrorCard(
                      message: e.toString(),
                      onRetry: () => ref.refresh(progressWithLessonsProvider),
                    ),
                    data: (items) => _QuickStatsRow(
                      items: items,
                      selectedMonth: selMonth,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Debt banner ────────────────────────────────────────
                  progressAsync.maybeWhen(
                    data: (items) {
                      final debts   = items.where((i) => i.hasDebt).toList();
                      final noAccess = items.where((i) => !i.access).toList();
                      if (debts.isEmpty && noAccess.isEmpty) return const SizedBox.shrink();
                      return Column(
                        children: [
                          if (debts.isNotEmpty) ...[
                            _DebtAlertCard(debts: debts, allItems: items),
                            const SizedBox(height: 10),
                          ],
                          if (noAccess.isNotEmpty) ...[
                            _AdmissionAlertCard(noAccess: noAccess, allItems: items),
                            const SizedBox(height: 10),
                          ],
                          if (debts.isNotEmpty || noAccess.isNotEmpty) ...[
                            if (user?.isInstitute == true)
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(builder: (_) => const RecoveryPlanScreen()));
                                  },
                                  icon: const Icon(Icons.auto_awesome),
                                  label: const Text('Сформировать план спасения', style: TextStyle(fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppTheme.accent.withOpacity(0.15),
                                    foregroundColor: AppTheme.accent,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      side: BorderSide(color: AppTheme.accent.withOpacity(0.3)),
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 10),
                          ],
                        ],
                      );
                    },
                    orElse: () => const SizedBox.shrink(),
                  ),

                  // ── Today ──────────────────────────────────────────────
                  _SectionHeader(
                    title: 'Сегодня',
                    subtitle: DateFormat('EEEE, d MMMM', 'ru_RU').format(DateTime.now()),
                  ),
                  const SizedBox(height: 12),

                  todayAsync.when(
                    loading: () => const _LessonCardShimmer(),
                    error: (e, _) => _ErrorCard(
                      message: e.toString(),
                      onRetry: () => ref.refresh(todayScheduleProvider),
                    ),
                    data: (lessons) => lessons.isEmpty
                        ? const _EmptyDay()
                        : Column(
                            children: lessons
                                .map((l) => _LessonCard(lesson: l))
                                .toList()),
                  ),
                  const SizedBox(height: 80),
                ]),
              ),
            ),
          ],
        ),
      );
  }

  SliverAppBar _buildAppBar(BuildContext context, WidgetRef ref, String name) {
    final parts     = name.trim().split(' ');
    final firstName = parts.length > 1 ? parts[1] : (name.isNotEmpty ? name : 'Студент');
    final h         = DateTime.now().hour;
    final greeting  = h < 12 ? 'Доброе утро' : h < 17 ? 'Добрый день' : 'Добрый вечер';
    
    final infoAsync = ref.watch(studentInfoProvider);

    return SliverAppBar(
      expandedHeight: 100,
      pinned: true,
      backgroundColor: AppTheme.bgDark,
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded),
        onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.fromLTRB(56, 0, 20, 16),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(greeting,
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w400)),
                Text(firstName,
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
              ],
            ),
            infoAsync.maybeWhen(
              data: (info) {
                final rating = info['reting']; // Msal API spells it "reting"
                if (rating == null) return const SizedBox.shrink();
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded, color: AppTheme.accent, size: 14),
                      const SizedBox(width: 4),
                      Text(
                        rating.toString(),
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}


// ── Stats row ─────────────────────────────────────────────────────────────────

class _QuickStatsRow extends ConsumerWidget {
  final List<ProgressItem> items;
  final DateTime selectedMonth;

  const _QuickStatsRow({
    required this.items,
    required this.selectedMonth,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Debts — count disciplines where any lesson has grade == 2
    final debtCount = items.where((i) => i.hasDebt).length;

    // Monthly attendance from per-lesson data
    final summary = MonthAttendanceSummary.fromProgress(
        items, selectedMonth.year, selectedMonth.month);

    final monthLabel = _monthName(selectedMonth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _StatCard(
                icon:  Icons.warning_amber_rounded,
                value: '$debtCount',
                label: 'Задолженности',
                color: debtCount > 0 ? AppTheme.error : AppTheme.success,
              )),
              const SizedBox(width: 10),
              Expanded(child: GestureDetector(
                onTap: () => _showAttendanceDetail(context, items, selectedMonth),
                child: _StatCard(
                  icon:     Icons.event_busy_outlined,
                  value:    summary.hasLessonData ? '${summary.missedLessons}' : '—',
                  label:    'Пропусков',
                  color:    summary.missedLessons > 3 ? AppTheme.warning : AppTheme.textSecondary,
                  sublabel: monthLabel,
                  detail:   _missedDetail(items, selectedMonth),
                  trailing: const Icon(Icons.expand_more, color: AppTheme.textMuted, size: 14),
                ),
              )),
            ]
          ),
        ),
        if (!summary.hasLessonData)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Нет данных о занятиях за этот месяц',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10),
            ),
          ),
      ],
    );
  }

  String? _missedDetail(List<ProgressItem> items, DateTime m) {
    final missed = items.where((item) =>
      item.lessonsForMonth(m.year, m.month).any((l) => !l.turnout)
    ).map((item) {
      final name = item.discipline;
      return name.length > 18 ? '${name.substring(0, 18)}…' : name;
    }).take(3).toList();
    if (missed.isEmpty) return null;
    return missed.join(', ');
  }

  String _monthName(DateTime d) {
    final s = DateFormat('LLLL', 'ru_RU').format(d);
    return s[0].toUpperCase() + s.substring(1);
  }

  void _showAttendanceDetail(
      BuildContext context, List<ProgressItem> items, DateTime month) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _AttendanceDetailSheet(
        items: items,
        initialMonth: month,
      ),
    );
  }
}

class _StatCard extends ConsumerWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final String? sublabel;
  final String? detail;   // e.g. missed discipline names
  final Widget? trailing;

  const _StatCard({
    required this.icon, required this.value,
    required this.label, required this.color,
    this.sublabel, this.detail, this.trailing,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, color: color, size: 18),
        const Spacer(),
        if (trailing != null) trailing!,
      ]),
      const SizedBox(height: 8),
      Text(value,
          style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w700)),
      const SizedBox(height: 2),
      Text(label,
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
      if (sublabel != null)
        Text(sublabel!,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
      if (detail != null) ...[
        const SizedBox(height: 3),
        Text(detail!,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 9),
            maxLines: 2,
            overflow: TextOverflow.ellipsis),
      ],
    ]),
  );
}

// ── Error card ────────────────────────────────────────────────────────────────

class _ErrorCard extends ConsumerWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  String get _friendly {
    final m = message.toLowerCase();
    if (m.contains('handshake') || m.contains('certificate')) return 'Ошибка SSL-сертификата';
    if (m.contains('socketexception') || m.contains('refused') || m.contains('network'))
      return 'Нет подключения к lk.msal.ru';
    if (m.contains('timeout'))   return 'Сервер не отвечает';
    if (m.contains('401') || m.contains('403')) return 'Сессия истекла — войдите снова';
    if (m.contains('404'))       return 'Эндпоинт не найден (API изменился)';
    if (m.contains('500'))       return 'Внутренняя ошибка сервера МГЮА';
    return 'Ошибка загрузки';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.error.withOpacity(0.3))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.cloud_off_rounded, color: AppTheme.error, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(_friendly,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
      ]),
      Padding(
        padding: const EdgeInsets.only(top: 4, left: 26),
        child: Text(message,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
            maxLines: 2, overflow: TextOverflow.ellipsis),
      ),
      const SizedBox(height: 10),
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 15),
          label: const Text('Повторить'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.accent,
            side: BorderSide(color: AppTheme.accent.withOpacity(0.4)),
            padding: const EdgeInsets.symmetric(vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    ]),
  );
}

// ── Debt banner ───────────────────────────────────────────────────────────────

class _DebtAlertCard extends ConsumerWidget {
  final List<ProgressItem> debts;
  final List<ProgressItem> allItems;
  const _DebtAlertCard({required this.debts, required this.allItems});

  String get _suffix {
    final n = debts.length;
    if (n % 10 == 1 && n % 100 != 11) return 'ь';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'и';
    return 'ей';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => DebtManagerScreen(items: allItems))),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.error.withOpacity(0.3))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: AppTheme.error.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
          child: Icon(Icons.warning_rounded, color: AppTheme.error, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('У вас ${debts.length} задолженност$_suffix',
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 3),
          Text(
            debts.map((d) => d.discipline).take(2).join(', ') +
                (debts.length > 2 ? ' и др.' : ''),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        const Icon(Icons.chevron_right, color: AppTheme.textMuted),
      ]),
    ),
  );
}

// ── Admission alert card ──────────────────────────────────────────────────────

class _AdmissionAlertCard extends ConsumerWidget {
  final List<ProgressItem> noAccess;
  final List<ProgressItem> allItems;
  const _AdmissionAlertCard({required this.noAccess, required this.allItems});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onTap: () => Navigator.push(context,
        MaterialPageRoute(builder: (_) => AdmissionManagerScreen(
          noAccessItems: noAccess,
          allItems: allItems,
        ))),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: AppTheme.warning.withOpacity(0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.warning.withOpacity(0.3))),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: AppTheme.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.block_outlined,
              color: AppTheme.warning, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Нет допуска по ${noAccess.length} предмет${_nounSuffix(noAccess.length)}',
              style: const TextStyle(color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w600, fontSize: 14)),
          const SizedBox(height: 3),
          Text(
            noAccess.map((d) => d.discipline).take(2).join(', ') +
                (noAccess.length > 2 ? ' и ещё ${noAccess.length - 2}' : ''),
            style: const TextStyle(
                color: AppTheme.textSecondary, fontSize: 12),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        ])),
        const Icon(Icons.chevron_right, color: AppTheme.textMuted),
      ]),
    ),
  );

  String _nounSuffix(int n) {
    if (n % 10 == 1 && n % 100 != 11) return 'у';
    if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) return 'ам';
    return 'ам';
  }
}

// ── Lesson card ───────────────────────────────────────────────────────────────

class _LessonCard extends ConsumerWidget {
  final ScheduleLesson lesson;
  const _LessonCard({required this.lesson});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider)),
    child: Row(children: [
      SizedBox(width: 52, child: Column(children: [
        Text(lesson.startTime,
            style: const TextStyle(color: AppTheme.accent,
                fontSize: 12, fontWeight: FontWeight.w600)),
        Container(width: 1, height: 18, color: AppTheme.divider,
            margin: const EdgeInsets.symmetric(vertical: 3)),
        Text(lesson.endTime,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ])),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(lesson.discipline,
            style: const TextStyle(color: AppTheme.textPrimary,
                fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 5),
        Wrap(spacing: 6, children: [
          _Chip(lesson.type,
              bg: AppTheme.accent.withOpacity(0.15), fg: AppTheme.neon),
          if (lesson.corps.isNotEmpty)
            _Chip(lesson.corps,
                bg: AppTheme.bgSurface, fg: AppTheme.textSecondary),
          if ((lesson.auditory ?? '').isNotEmpty)
            _Chip('ауд. ${lesson.auditory}',
                bg: AppTheme.bgSurface, fg: AppTheme.textSecondary),
        ]),
        const SizedBox(height: 4),
        Text(lesson.teacher,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
            maxLines: 1, overflow: TextOverflow.ellipsis),
      ])),
    ]),
  );
}

class _Chip extends ConsumerWidget {
  final String text; final Color bg; final Color fg;
  const _Chip(this.text, {required this.bg, required this.fg});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
    child: Text(text,
        style: TextStyle(color: fg, fontSize: 10, fontWeight: FontWeight.w500)),
  );
}

// ── Misc helpers ──────────────────────────────────────────────────────────────

class _SectionHeader extends ConsumerWidget {
  final String title; final String? subtitle;
  const _SectionHeader({required this.title, this.subtitle});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(color: AppTheme.textPrimary,
          fontSize: 17, fontWeight: FontWeight.w600)),
      if (subtitle != null)
        Text(subtitle!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
    ],
  );
}

class _EmptyDay extends ConsumerWidget {
  const _EmptyDay();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.all(32), alignment: Alignment.center,
    child: const Column(children: [
      Icon(Icons.wb_sunny_outlined, color: AppTheme.accent, size: 40),
      SizedBox(height: 12),
      Text('Занятий нет',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
    ]),
  );
}

class _LessonCardShimmer extends ConsumerWidget {
  const _LessonCardShimmer();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: List.generate(3, (_) => Container(
      margin: const EdgeInsets.only(bottom: 10), height: 90,
      decoration: BoxDecoration(
          color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14)))),
  );
}

class _StatsRowShimmer extends ConsumerWidget {
  const _StatsRowShimmer();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Row(
    children: List.generate(3, (i) => Expanded(child: Container(
      margin: EdgeInsets.only(left: i > 0 ? 10 : 0), height: 80,
      decoration: BoxDecoration(
          color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14))))),
  );
}

// ── Attendance detail sheet ───────────────────────────────────────────────────

class _AttendanceDetailSheet extends ConsumerStatefulWidget {
  final List<ProgressItem> items;
  final DateTime initialMonth;

  const _AttendanceDetailSheet({
    required this.items,
    required this.initialMonth,
  });

  @override
  ConsumerState<_AttendanceDetailSheet> createState() => _AttendanceDetailSheetState();
}

class _AttendanceDetailSheetState extends ConsumerState<_AttendanceDetailSheet>
    with SingleTickerProviderStateMixin {
  late DateTime _selectedMonth;
  final Set<String> _expandedDisciplines = {};
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  /// Map: "disciplineId|dd.MM.yyyy" → lesson type label (e.g. "Лекция")
  Map<String, String> _lessonTypes = {};
  bool _typesLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedMonth = widget.initialMonth;
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();
    _loadLessonTypes();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  /// Loads schedule for the selected month to extract lesson types.
  Future<void> _loadLessonTypes() async {
    setState(() => _typesLoading = true);
    try {
      final month = _selectedMonth;
      final firstDay = DateTime(month.year, month.month, 1);
      final lastDay = DateTime(month.year, month.month + 1, 0);
      // Monday of the week containing the first day
      DateTime current = firstDay.subtract(Duration(days: firstDay.weekday - 1));
      final limit = lastDay.add(const Duration(days: 7));

      final types = <String, String>{};
      final serverDateFmt = DateFormat('dd.MM.yyyy');

      while (current.isBefore(limit)) {
        try {
          final days = await ref.read(apiServiceProvider).getScheduleWeek(current);
          for (final day in days) {
            for (final lesson in day.data) {
              final dt = lesson.lessonDate ?? day.date;
              final dateKey = serverDateFmt.format(dt);
              final key = '${lesson.disciplineId}|$dateKey';
              types[key] = lesson.typeLabel;
            }
          }
        } catch (_) {}
        current = current.add(const Duration(days: 7));
      }

      if (mounted) {
        setState(() {
          _lessonTypes = types;
          _typesLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _typesLoading = false);
    }
  }

  /// Lookup lesson type for a given discipline + lesson date.
  String? _typeFor(String disciplineId, String lessonDate) {
    return _lessonTypes['$disciplineId|$lessonDate'];
  }

  @override
  Widget build(BuildContext context) {
    final summary = MonthAttendanceSummary.fromProgress(
        widget.items, _selectedMonth.year, _selectedMonth.month);

    // Build per-discipline data for the selected month
    final disciplineData = <_DisciplineAttendance>[];
    for (final item in widget.items) {
      final monthLessons =
          item.lessonsForMonth(_selectedMonth.year, _selectedMonth.month);
      if (monthLessons.isEmpty) continue;
      final missed = monthLessons.where((l) => !l.turnout).toList();
      final attended = monthLessons.where((l) => l.turnout).toList();
      disciplineData.add(_DisciplineAttendance(
        discipline: item.discipline,
        disciplineId: item.disciplineId,
        totalLessons: monthLessons.length,
        missedLessons: missed,
        attendedLessons: attended,
      ));
    }

    // Sort: disciplines with most misses first
    disciplineData.sort((a, b) =>
        b.missedLessons.length.compareTo(a.missedLessons.length));

    return FadeTransition(
      opacity: _fadeAnim,
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: AppTheme.bgCard,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.calendar_month_rounded,
                          color: AppTheme.accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Посещаемость',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded,
                          color: AppTheme.textMuted, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: AppTheme.bgSurface,
                        padding: const EdgeInsets.all(6),
                      ),
                    ),
                  ],
                ),
              ),

              // Month selector
              SizedBox(
                height: 40,
                child: _MonthSelector(
                  selected: _selectedMonth,
                  onChanged: (m) {
                    setState(() {
                      _selectedMonth = m;
                      _expandedDisciplines.clear();
                    });
                    _loadLessonTypes();
                  },
                ),
              ),

              const SizedBox(height: 10),

              // Summary bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _AttendanceSummaryBar(summary: summary),
              ),

              const SizedBox(height: 12),
              const Divider(color: AppTheme.divider, height: 1),

              // Discipline list
              Expanded(
                child: disciplineData.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_rounded,
                                color: AppTheme.textMuted.withOpacity(0.5),
                                size: 48),
                            const SizedBox(height: 12),
                            const Text(
                              'Нет данных за этот месяц',
                              style: TextStyle(
                                  color: AppTheme.textMuted, fontSize: 14),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: disciplineData.length,
                        itemBuilder: (ctx, i) {
                          final d = disciplineData[i];
                          final isExpanded =
                              _expandedDisciplines.contains(d.discipline);
                          return _DisciplineAttendanceTile(
                            data: d,
                            lessonTypes: _lessonTypes,
                            isExpanded: isExpanded,
                            onToggle: () {
                              setState(() {
                                if (isExpanded) {
                                  _expandedDisciplines.remove(d.discipline);
                                } else {
                                  _expandedDisciplines.add(d.discipline);
                                }
                              });
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Data class for per-discipline attendance ──────────────────────────────────

class _DisciplineAttendance {
  final String discipline;
  final String disciplineId;
  final int totalLessons;
  final List<LessonGrade> missedLessons;
  final List<LessonGrade> attendedLessons;

  const _DisciplineAttendance({
    required this.discipline,
    required this.disciplineId,
    required this.totalLessons,
    required this.missedLessons,
    required this.attendedLessons,
  });

  double get rate => totalLessons > 0
      ? attendedLessons.length / totalLessons
      : 1.0;
}

// ── Horizontal month selector ─────────────────────────────────────────────────

class _MonthSelector extends ConsumerWidget {
  final DateTime selected;
  final ValueChanged<DateTime> onChanged;

  const _MonthSelector({
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final months = List.generate(12, (i) => DateTime(now.year, now.month - i));

    // Scroll to show selected month
    final selectedIndex =
        months.indexWhere((m) => m.year == selected.year && m.month == selected.month);

    final scrollCtrl = ScrollController(
      initialScrollOffset: (selectedIndex.clamp(0, 11)) * 110.0,
    );

    return ListView.builder(
      controller: scrollCtrl,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: months.length,
      itemBuilder: (ctx, i) {
        final m = months[i];
        final isSel = m.year == selected.year && m.month == selected.month;
        final raw = DateFormat('LLLL', 'ru_RU').format(m);
        final label = raw[0].toUpperCase() + raw.substring(1);
        final yearLabel = m.year != now.year ? ' ${m.year}' : '';

        return Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () => onChanged(m),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: isSel
                    ? AppTheme.accent.withOpacity(0.15)
                    : AppTheme.bgSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSel
                      ? AppTheme.accent.withOpacity(0.5)
                      : AppTheme.divider,
                ),
              ),
              child: Center(
                child: Text(
                  '$label$yearLabel',
                  style: TextStyle(
                    color: isSel ? AppTheme.accent : AppTheme.textSecondary,
                    fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Summary bar ───────────────────────────────────────────────────────────────

class _AttendanceSummaryBar extends ConsumerWidget {
  final MonthAttendanceSummary summary;
  const _AttendanceSummaryBar({required this.summary});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!summary.hasLessonData) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text('Нет данных о занятиях',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
        ),
      );
    }

    final rate = summary.rate;
    final rateColor = rate >= 0.8
        ? AppTheme.success
        : rate >= 0.6
            ? AppTheme.warning
            : AppTheme.error;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          // Attendance rate circle
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    value: rate,
                    strokeWidth: 4,
                    color: rateColor,
                    backgroundColor: rateColor.withOpacity(0.15),
                  ),
                ),
                Text(
                  '${(rate * 100).round()}%',
                  style: TextStyle(
                    color: rateColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MiniStat(
                      icon: Icons.check_circle_outline,
                      color: AppTheme.success,
                      value: '${summary.attended}',
                      label: 'посещено',
                    ),
                    const SizedBox(width: 20),
                    _MiniStat(
                      icon: Icons.cancel_outlined,
                      color: AppTheme.error,
                      value: '${summary.missedLessons}',
                      label: 'пропущено',
                    ),
                    const SizedBox(width: 20),
                    _MiniStat(
                      icon: Icons.calendar_today_outlined,
                      color: AppTheme.textSecondary,
                      value: '${summary.totalLessons}',
                      label: 'всего',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends ConsumerWidget {
  final IconData icon;
  final Color color;
  final String value;
  final String label;

  const _MiniStat({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(value,
                style: TextStyle(
                    color: color, fontSize: 15, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 9)),
      ],
    );
  }
}

// ── Discipline attendance tile (expandable) ──────────────────────────────────

class _DisciplineAttendanceTile extends ConsumerWidget {
  final _DisciplineAttendance data;
  final Map<String, String> lessonTypes;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _DisciplineAttendanceTile({
    required this.data,
    required this.lessonTypes,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMisses = data.missedLessons.isNotEmpty;
    final rateColor = data.rate >= 0.8
        ? AppTheme.success
        : data.rate >= 0.6
            ? AppTheme.warning
            : AppTheme.error;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: hasMisses
            ? AppTheme.error.withOpacity(0.04)
            : AppTheme.success.withOpacity(0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasMisses
              ? AppTheme.error.withOpacity(0.15)
              : AppTheme.success.withOpacity(0.15),
        ),
      ),
      child: Column(
        children: [
          // Header
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Rate indicator
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: rateColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '${(data.rate * 100).round()}%',
                      style: TextStyle(
                        color: rateColor,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data.discipline,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          hasMisses
                              ? 'Пропущено ${data.missedLessons.length} из ${data.totalLessons}'
                              : 'Все ${data.totalLessons} посещены ✓',
                          style: TextStyle(
                            color: hasMisses
                                ? AppTheme.error.withOpacity(0.8)
                                : AppTheme.success.withOpacity(0.8),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.expand_more_rounded,
                      color: AppTheme.textMuted,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Expanded detail
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildLessonList(),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonList() {
    // Combine all lessons sorted by date
    final allLessons = <LessonGrade>[
      ...data.missedLessons,
      ...data.attendedLessons,
    ];
    allLessons.sort((a, b) {
      final da = a.dateTime;
      final db = b.dateTime;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      return da.compareTo(db);
    });

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.bgDark.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          // Column headers
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: const [
                SizedBox(width: 32),
                Expanded(
                  flex: 3,
                  child: Text('Дата',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
                Expanded(
                  flex: 2,
                  child: Text('Оценки',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
                SizedBox(
                  width: 60,
                  child: Text('Статус',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 10,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
          ...allLessons.map((l) => _LessonRow(
            lesson: l,
            lessonType: lessonTypes['${data.disciplineId}|${l.date}'],
          )),
        ],
      ),
    );
  }
}

// ── Single lesson row ─────────────────────────────────────────────────────────

class _LessonRow extends ConsumerWidget {
  final LessonGrade lesson;
  final String? lessonType;
  const _LessonRow({required this.lesson, this.lessonType});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMissed = !lesson.turnout;
    final dt = lesson.dateTime;
    final dateStr = dt != null
        ? DateFormat('d MMM, EE', 'ru_RU').format(dt)
        : lesson.date;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.divider.withOpacity(0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: isMissed
                  ? AppTheme.error.withOpacity(0.15)
                  : AppTheme.success.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isMissed ? Icons.close_rounded : Icons.check_rounded,
              size: 12,
              color: isMissed ? AppTheme.error : AppTheme.success,
            ),
          ),
          // Date + type
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  dateStr,
                  style: TextStyle(
                    color: isMissed
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight:
                        isMissed ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
                if (lessonType != null) ...[
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: _typeColor(lessonType!).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      lessonType!,
                      style: TextStyle(
                        color: _typeColor(lessonType!),
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Grades
          Expanded(
            flex: 2,
            child: lesson.grades.isEmpty
                ? Text('—',
                    style: TextStyle(
                        color: AppTheme.textMuted, fontSize: 11))
                : Wrap(
                    spacing: 4,
                    children: lesson.grades.map((g) {
                      return Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: lesson.gradeColor(g).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$g',
                          style: TextStyle(
                            color: lesson.gradeColor(g),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
          // Status label
          SizedBox(
            width: 60,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isMissed
                      ? AppTheme.error.withOpacity(0.12)
                      : AppTheme.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isMissed ? 'Н/Б' : '✓',
                  style: TextStyle(
                    color: isMissed ? AppTheme.error : AppTheme.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _typeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('лекц'))                          return const Color(0xFF6B3FA0);
    if (t.contains('практ') || t.contains('лаб'))   return const Color(0xFF2D7A4F);
    if (t.contains('семин'))                          return const Color(0xFF1A5276);
    if (t.contains('курсов') || t.contains('проект')) return const Color(0xFF1A4A5C);
    if (t.contains('экзам'))                          return const Color(0xFF8B2500);
    if (t.contains('зачёт') || t.contains('зачет'))  return const Color(0xFF5C3D00);
    return const Color(0xFF4A3060);
  }
}
