import '../../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/presentation/screens/grades/admission_manager_screen.dart
//
// Shows disciplines where the student has no admission (access=false).
// For each discipline, displays a breakdown of lesson types from the schedule:
//   - Лекции: passed / total (remaining)
//   - Семинары: passed / total (remaining)
//   - Практики: passed / total (remaining)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/grade_model.dart';
import '../../../data/models/schedule_model.dart';
import '../../../data/services/api_service.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class AdmissionManagerScreen extends ConsumerStatefulWidget {
  final List<ProgressItem> noAccessItems;
  final List<ProgressItem> allItems;
  const AdmissionManagerScreen({
    super.key,
    required this.noAccessItems,
    required this.allItems,
  });

  @override
  ConsumerState<AdmissionManagerScreen> createState() => _AdmissionManagerScreenState();
}

class _AdmissionManagerScreenState extends ConsumerState<AdmissionManagerScreen> {
  bool _loading = true;
  // disciplineId → _DisciplineBreakdown
  Map<String, _DisciplineBreakdown> _breakdowns = {};

  @override
  void initState() {
    super.initState();
    _loadScheduleBreakdown();
  }

  DateTime _semesterStart() {
    final now = DateTime.now();
    return now.month >= 9 ? DateTime(now.year, 9, 1) : DateTime(now.year, 2, 1);
  }

  DateTime _semesterEnd() {
    final now = DateTime.now();
    return now.month >= 9
        ? DateTime(now.year + 1, 1, 31)
        : DateTime(now.year, 6, 30);
  }

  /// Loads all schedule weeks for the semester and counts lesson types per discipline.
  Future<void> _loadScheduleBreakdown() async {
    try {
      final start = _semesterStart();
      final end = _semesterEnd();
      final now = DateTime.now();
      final serverFmt = DateFormat('dd.MM.yyyy');

      // Collect all discipline IDs we care about
      final targetIds = widget.noAccessItems.map((i) => i.disciplineId).toSet();

      // disciplineId → { type → { total, passed } }
      final data = <String, Map<String, _TypeCount>>{};

      // Fetch all schedule weeks from semester start to end
      DateTime current = start.subtract(Duration(days: start.weekday - 1)); // Monday
      final limit = end.add(const Duration(days: 7));

      while (current.isBefore(limit)) {
        try {
          final days = await ref.read(apiServiceProvider).getScheduleWeek(current);
          for (final day in days) {
            for (final lesson in day.data) {
              if (!targetIds.contains(lesson.disciplineId)) continue;

              final typeLabel = lesson.typeLabel;
              final dt = lesson.lessonDate ?? day.date;
              final isPast = dt.isBefore(now) || _sameDay(dt, now);

              data.putIfAbsent(lesson.disciplineId, () => {});
              data[lesson.disciplineId]!
                  .putIfAbsent(typeLabel, () => _TypeCount());
              data[lesson.disciplineId]![typeLabel]!.total++;
              if (isPast) {
                data[lesson.disciplineId]![typeLabel]!.passed++;
              }
            }
          }
        } catch (_) {}
        current = current.add(const Duration(days: 7));
      }

      // Now cross-reference with progress data for attendance
      final breakdowns = <String, _DisciplineBreakdown>{};
      for (final item in widget.noAccessItems) {
        final typeCounts = data[item.disciplineId] ?? {};
        // For attendance stats from progress data
        final attended = item.attended;
        final missed = item.effectiveMissed;

        breakdowns[item.disciplineId] = _DisciplineBreakdown(
          item: item,
          typeCounts: typeCounts,
          attendedTotal: attended,
          missedTotal: missed,
        );
      }

      if (mounted) {
        setState(() {
          _breakdowns = breakdowns;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Менеджер недопусков'),
        backgroundColor: AppTheme.bgDark,
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppTheme.accent))
          : widget.noAccessItems.isEmpty
              ? _buildEmpty()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: widget.noAccessItems.length,
                  itemBuilder: (_, i) {
                    final item = widget.noAccessItems[i];
                    final breakdown = _breakdowns[item.disciplineId];
                    return _AdmissionCard(
                      item: item,
                      breakdown: breakdown,
                    );
                  },
                ),
    );
  }

  Widget _buildEmpty() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.verified_rounded,
              color: AppTheme.success.withOpacity(0.7), size: 56),
          const SizedBox(height: 16),
          const Text('Все допуски получены!',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
          const SizedBox(height: 8),
          const Text('У вас нет предметов без допуска',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        ]),
      );
}

// ── Data classes ──────────────────────────────────────────────────────────────

class _TypeCount {
  int total = 0;
  int passed = 0;
  int get remaining => (total - passed).clamp(0, 999);
}

class _DisciplineBreakdown {
  final ProgressItem item;
  final Map<String, _TypeCount> typeCounts;
  final int attendedTotal;
  final int missedTotal;

  const _DisciplineBreakdown({
    required this.item,
    required this.typeCounts,
    required this.attendedTotal,
    required this.missedTotal,
  });

  int get totalLessons =>
      typeCounts.values.fold(0, (sum, tc) => sum + tc.total);
  int get passedLessons =>
      typeCounts.values.fold(0, (sum, tc) => sum + tc.passed);
  int get remainingLessons =>
      typeCounts.values.fold(0, (sum, tc) => sum + tc.remaining);
}

// ── Per-discipline card ──────────────────────────────────────────────────────

class _AdmissionCard extends ConsumerWidget {
  final ProgressItem item;
  final _DisciplineBreakdown? breakdown;

  const _AdmissionCard({required this.item, this.breakdown});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rate = item.attendanceRate;
    final rateColor = rate >= 0.8
        ? AppTheme.success
        : rate >= 0.6
            ? AppTheme.warning
            : AppTheme.error;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.warning.withOpacity(0.08),
                  Colors.transparent,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.block_outlined,
                    color: AppTheme.warning, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.discipline,
                          style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              fontSize: 14),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 3),
                      Text('Нет допуска',
                          style: TextStyle(
                              color: AppTheme.warning.withOpacity(0.85),
                              fontSize: 12,
                              fontWeight: FontWeight.w600)),
                    ]),
              ),
              // Attendance rate badge
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: rateColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(children: [
                  Text('${(rate * 100).round()}%',
                      style: TextStyle(
                          color: rateColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800)),
                  Text('явка',
                      style: TextStyle(
                          color: rateColor.withOpacity(0.7),
                          fontSize: 9,
                          fontWeight: FontWeight.w500)),
                ]),
              ),
            ]),
          ),

          // Attendance summary
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(children: [
              _StatChip(
                  label: 'Всего',
                  value: '${item.effectiveTotal}',
                  color: AppTheme.textSecondary),
              const SizedBox(width: 8),
              _StatChip(
                  label: 'Посещено',
                  value: '${item.attended}',
                  color: AppTheme.success),
              const SizedBox(width: 8),
              _StatChip(
                  label: 'Пропущено',
                  value: '${item.effectiveMissed}',
                  color: AppTheme.error),
            ]),
          ),

          // ── Lesson type breakdown ──────────────────────────────────────
          if (breakdown != null &&
              breakdown!.typeCounts.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text('Занятия за семестр',
                  style: TextStyle(
                      color: AppTheme.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Column(
                children: _buildTypeRows(),
              ),
            ),
          ] else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline,
                      color: AppTheme.textMuted.withOpacity(0.6), size: 16),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                        'Данные по типам занятий загружаются из расписания...',
                        style: TextStyle(
                            color: AppTheme.textMuted,
                            fontSize: 11,
                            fontStyle: FontStyle.italic)),
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildTypeRows() {
    if (breakdown == null) return [];

    // Sort types: Лекция, Семинар, Практика first, then others
    final sorted = breakdown!.typeCounts.entries.toList()
      ..sort((a, b) {
        final order = _typeOrder(a.key).compareTo(_typeOrder(b.key));
        if (order != 0) return order;
        return a.key.compareTo(b.key);
      });

    return sorted.map((entry) {
      final type = entry.key;
      final count = entry.value;
      final color = _typeColor(type);
      final progress = count.total > 0 ? count.passed / count.total : 0.0;

      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(_typeIcon(type), color: color, size: 16),
              const SizedBox(width: 8),
              Text(type,
                  style: TextStyle(
                      color: color,
                      fontSize: 13,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${count.passed} / ${count.total}',
                    style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 8),
            // Progress bar
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: color.withOpacity(0.1),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Прошло: ${count.passed}',
                    style: const TextStyle(
                        color: AppTheme.textSecondary, fontSize: 11)),
                Text(
                    count.remaining > 0
                        ? 'Осталось: ${count.remaining}'
                        : 'Все прошли ✓',
                    style: TextStyle(
                        color: count.remaining > 0
                            ? AppTheme.warning
                            : AppTheme.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      );
    }).toList();
  }

  static int _typeOrder(String type) {
    final t = type.toLowerCase();
    if (t.contains('лекц')) return 0;
    if (t.contains('семин')) return 1;
    if (t.contains('практ') || t.contains('лаб')) return 2;
    if (t.contains('курсов') || t.contains('проект')) return 3;
    if (t.contains('экзам')) return 4;
    if (t.contains('зачёт') || t.contains('зачет')) return 5;
    return 6;
  }

  static Color _typeColor(String type) {
    final t = type.toLowerCase();
    if (t.contains('лекц')) return const Color(0xFF9C6FFF);
    if (t.contains('практ') || t.contains('лаб')) return const Color(0xFF4CAF82);
    if (t.contains('семин')) return const Color(0xFF3498DB);
    if (t.contains('курсов') || t.contains('проект'))
      return const Color(0xFF1ABC9C);
    if (t.contains('экзам')) return const Color(0xFFE74C3C);
    if (t.contains('зачёт') || t.contains('зачет'))
      return const Color(0xFFFFB547);
    return const Color(0xFF9B8DB8);
  }

  static IconData _typeIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('лекц')) return Icons.menu_book_rounded;
    if (t.contains('практ') || t.contains('лаб')) return Icons.science_outlined;
    if (t.contains('семин')) return Icons.groups_outlined;
    if (t.contains('курсов') || t.contains('проект'))
      return Icons.design_services_outlined;
    if (t.contains('экзам')) return Icons.quiz_outlined;
    if (t.contains('зачёт') || t.contains('зачет'))
      return Icons.fact_check_outlined;
    return Icons.school_outlined;
  }
}

// ── Small stat chip ──────────────────────────────────────────────────────────

class _StatChip extends ConsumerWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: color.withOpacity(0.7),
                    fontSize: 10,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}
