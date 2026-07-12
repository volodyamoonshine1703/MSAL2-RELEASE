import '../../../core/providers.dart';
// lib/presentation/screens/grades/grades_screen.dart
// Grades UI: МЭШ-style subject cards with avg grade, arrow, progress bar

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/api_service.dart';
import '../../../data/models/grade_model.dart';
import 'discipline_detail_screen.dart';
import 'debt_manager_screen.dart';
import '../../../core/providers/scaffold_provider.dart';

// ── Period selector ────────────────────────────────────────────────────────────

// Period: null = current semester; non-null = specific month/year
// We store a DateTime? where only year+month matter

DateTime _semesterStart() {
  final now = DateTime.now();
  return now.month >= 9
      ? DateTime(now.year, 9, 1)
      : DateTime(now.year, 2, 1);
}

// ── Providers ─────────────────────────────────────────────────────────────────

/// null = current semester, non-null = specific month
final _selectedMonthProvider = StateProvider<DateTime?>((_) => null);

final gradesProvider = FutureProvider<List<ProgressItem>>((ref) async {
  return ref.read(apiServiceProvider).getProgressWithLessons();
});

final _recordbookProvider = FutureProvider<List<RecordEntry>>((ref) async {
  return ref.read(apiServiceProvider).getRecordbook();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class GradesScreen extends ConsumerStatefulWidget {
  const GradesScreen({super.key});
  @override
  ConsumerState<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends ConsumerState<GradesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progressAsync = ref.watch(gradesProvider);
    final recordAsync   = ref.watch(_recordbookProvider);
    final selectedMonth = ref.watch(_selectedMonthProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Успеваемость'),
        backgroundColor: AppTheme.bgDark,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
        ),
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.accent,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Оценки'),
            Tab(text: 'Зачётная книжка'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () {
              ref.refresh(gradesProvider);
              ref.refresh(_recordbookProvider);
            },
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Grades tab ─────────────────────────────────────────────────
          progressAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent)),
            error: (e, _) => _ErrorView(
                error: e.toString(),
                onRetry: () => ref.refresh(gradesProvider)),
            data: (items) => _GradesTab(items: items, selectedMonth: selectedMonth, ref: ref),
          ),
          // ── Record book tab ────────────────────────────────────────────
          recordAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: AppTheme.accent)),
            error: (e, _) => _ErrorView(
                error: e.toString(),
                onRetry: () => ref.refresh(_recordbookProvider)),
            data: (entries) => _RecordbookTab(entries: entries),
          ),
        ],
      ),
    );
  }
}

// ── Grades Tab ─────────────────────────────────────────────────────────────────

class _GradesTab extends ConsumerWidget {
  final List<ProgressItem> items;
  final DateTime? selectedMonth; // null = semester
  final WidgetRef ref;

  const _GradesTab({
    required this.items,
    required this.selectedMonth,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final from = selectedMonth != null
        ? DateTime(selectedMonth!.year, selectedMonth!.month, 1)
        : _semesterStart();
    final to = selectedMonth != null
        ? DateTime(selectedMonth!.year, selectedMonth!.month + 1, 0)
        : DateTime.now();

    final filtered = items
        .map((item) => item.lessons.isNotEmpty
            ? item.filteredByPeriod(from, to)
            : item)
        .toList();

    final debts = filtered.where((i) => i.hasDebt).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _PeriodSelector(selectedMonth: selectedMonth, ref: ref),
        const SizedBox(height: 16),

        if (debts.isNotEmpty) ...[
          _DebtBanner(debts: debts, allItems: items),
          const SizedBox(height: 14),
        ],

        ...filtered.map((item) => _SubjectCard(item: item)),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ── Period selector ──────────────────────────────────────────────────────────

class _PeriodSelector extends ConsumerWidget {
  final DateTime? selectedMonth;
  final WidgetRef ref;
  const _PeriodSelector({required this.selectedMonth, required this.ref});

  Future<void> _pickMonth(BuildContext context) async {
    final now = DateTime.now();
    // Build list of months from Sep 2023 to current
    final months = <DateTime>[];
    var d = DateTime(2023, 9);
    while (!d.isAfter(now)) {
      months.insert(0, d);
      d = DateTime(d.year, d.month + 1);
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.55),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(height: 12),
            Container(width: 36, height: 4,
                decoration: BoxDecoration(color: AppTheme.divider,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Align(alignment: Alignment.centerLeft,
                  child: Text('Выберите месяц',
                      style: TextStyle(color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w600, fontSize: 15))),
            ),
            const SizedBox(height: 8),
            Flexible(child: SingleChildScrollView(child: Column(
              children: months.map((m) {
                final isSel = selectedMonth?.year == m.year &&
                    selectedMonth?.month == m.month;
                final label = _monthLabel(m);
                return ListTile(
                  title: Text(label, style: TextStyle(
                      color: isSel ? AppTheme.accent : AppTheme.textPrimary,
                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14)),
                  trailing: isSel ? const Icon(Icons.check_rounded,
                      color: AppTheme.accent, size: 18) : null,
                  onTap: () {
                    ref.read(_selectedMonthProvider.notifier).state = m;
                    Navigator.pop(ctx);
                  },
                );
              }).toList(),
            ))),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  String _monthLabel(DateTime m) {
    const months = ['', 'Январь', 'Февраль', 'Март', 'Апрель', 'Май', 'Июнь',
        'Июль', 'Август', 'Сентябрь', 'Октябрь', 'Ноябрь', 'Декабрь'];
    return '${months[m.month]} ${m.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSemester = selectedMonth == null;
    return Row(children: [
      _Pill(
        label: 'Семестр',
        selected: isSemester,
        onTap: () => ref.read(_selectedMonthProvider.notifier).state = null,
      ),
      const SizedBox(width: 8),
      _Pill(
        label: selectedMonth != null
            ? _monthLabel(selectedMonth!)
            : 'По месяцу',
        selected: !isSemester,
        icon: Icons.calendar_month_outlined,
        onTap: () => _pickMonth(context),
      ),
    ]);
  }
}

class _Pill extends ConsumerWidget {
  final String label;
  final bool selected;
  final IconData? icon;
  final VoidCallback onTap;
  const _Pill({required this.label, required this.selected,
      this.icon, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    onTap: onTap,
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accent : AppTheme.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? AppTheme.accent : AppTheme.divider),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: 14,
              color: selected ? Colors.white : AppTheme.textSecondary),
          const SizedBox(width: 4),
        ],
        Text(label, style: TextStyle(
          color: selected ? Colors.white : AppTheme.textSecondary,
          fontSize: 13,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        )),
      ]),
    ),
  );
}

// ── Debt banner ───────────────────────────────────────────────────────────────

class _DebtBanner extends ConsumerWidget {
  final List<ProgressItem> debts;
  final List<ProgressItem> allItems;
  const _DebtBanner({required this.debts, required this.allItems});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = debts.fold(0, (s, d) => s + d.debtCount);
    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => DebtManagerScreen(items: allItems))),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.error.withOpacity(0.35)),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10)),
            alignment: Alignment.center,
            child: const Text('2',
                style: TextStyle(color: AppTheme.error,
                    fontSize: 20, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Задолженности: $count двоек',
                  style: const TextStyle(color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(
                debts.map((d) => d.discipline).take(2).join(', ') +
                    (debts.length > 2 ? ' и др.' : ''),
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const Icon(Icons.chevron_right, color: AppTheme.textMuted),
        ]),
      ),
    );
  }
}

// ── Subject Card ──────────────────────────────────────────────────────────────

class _SubjectCard extends ConsumerWidget {
  final ProgressItem item;
  const _SubjectCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final avg  = item.averageGrade;
    final rate = item.attendanceRate;
    final dist = item.gradeDistribution;

    return GestureDetector(
      onTap: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => DisciplineDetailScreen(item: item))),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: item.hasDebt
                  ? AppTheme.error.withOpacity(0.4)
                  : item.access
                      ? AppTheme.success.withOpacity(0.4)
                      : AppTheme.warning.withOpacity(0.5),
              width: item.access && !item.hasDebt ? 1.5 : 1.0),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.discipline,
                  style: const TextStyle(color: AppTheme.textPrimary,
                      fontSize: 15, fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text('Курс ${item.course}, семестр ${item.semester}',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            ])),
            const SizedBox(width: 12),
            if (item.universityModules != null)
              _BarsBadge(score: item.barsScore, hasDebt: item.hasDebt)
            else if (avg > 0) 
              _AvgBadge(avg: avg, hasDebt: item.hasDebt),
          ]),

          if (dist.isNotEmpty && item.universityModules == null) ...[
            const SizedBox(height: 10),
            _GradePillsRow(distribution: dist),
          ],

          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: item.universityModules != null
                  ? rate // For university, just show attendance rate in the bar
                  : (avg > 0 ? (avg / 5.0).clamp(0.0, 1.0) : rate),
              backgroundColor: AppTheme.bgSurface,
              valueColor: AlwaysStoppedAnimation<Color>(_barColor(avg, rate, isUniversity: item.universityModules != null)),
              minHeight: 7,
            ),
          ),

          if (item.universityModules == null) ...[
            const SizedBox(height: 5),
            Text(
              _goalText(avg, item.allGrades) ?? '',
              style: TextStyle(
                color: _goalText(avg, item.allGrades)?.contains('достигнута') == true
                    ? AppTheme.success
                    : AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ],

          // ── Admission status chip ──────────────────────────────────────
          const SizedBox(height: 8),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: item.access
                    ? AppTheme.success.withOpacity(0.1)
                    : AppTheme.warning.withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: item.access
                        ? AppTheme.success.withOpacity(0.35)
                        : AppTheme.warning.withOpacity(0.4)),
              ),
              child: Text(
                item.access ? '✓ Допуск' : '✗ Нет допуска',
                style: TextStyle(
                  color: item.access ? AppTheme.success : AppTheme.warning,
                  fontSize: 10, fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!item.access && item.debtReport.isNotEmpty) ...[
              const SizedBox(width: 6),
              Flexible(child: Text(
                _admissionHint(item.debtReport),
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                overflow: TextOverflow.ellipsis,
              )),
            ],
          ]),
        ]),
      ),
    );
  }

  /// Extract "не хватает N оценок" from debtReport
  String _admissionHint(String report) {
    final match = RegExp(r'[Нн]е хватает (\d+)').firstMatch(report);
    if (match != null) return 'нужно ещё ${match.group(1)} оценок';
    // Trim long reports
    return report.length > 50 ? report.substring(0, 50) : report;
  }

  String? _goalText(double avg, List<int> grades) {
    if (grades.isEmpty) return null;
    // Допуск: нужна средняя >= 2.5 (хотя бы тройки)
    if (avg >= 4.5) return '✓ Отлично — цель достигнута';
    // Calculate 5s needed for next grade threshold
    final targets = <int>[4, 5];
    for (final target in targets) {
      if (avg < target - 0.5) {
        final sum = grades.reduce((a, b) => a + b);
        int need = 0;
        while (need < 20) {
          need++;
          final newAvg = (sum + need * 5) / (grades.length + need);
          if (newAvg >= target - 0.5) break;
        }
        final word = need == 1 ? 'оценка' : need < 5 ? 'оценки' : 'оценок';
        return 'ещё $need $word пятёрок до $target';
      }
    }
    return null;
  }

  Color _barColor(double avg, double rate, {bool isUniversity = false}) {
            if (isUniversity) return rate > 0.75 ? AppTheme.accent : AppTheme.warning;
    if (avg >= 4.5) return AppTheme.success;
    if (avg >= 3.5) return const Color(0xFF7CB9E8);
    if (avg >= 2.5) return AppTheme.warning;
    if (avg > 0)    return AppTheme.error;
    return rate > 0.75 ? AppTheme.accent : AppTheme.warning;
  }
}

// ── BARS Badge ────────────────────────────────────────────────────────────────
class _BarsBadge extends ConsumerWidget {
  final double score;
  final bool hasDebt;
  const _BarsBadge({required this.score, required this.hasDebt});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = hasDebt ? AppTheme.error : AppTheme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.star_rounded, color: AppTheme.accent, size: 16),
        const SizedBox(width: 4),
        Text(score.toStringAsFixed(2),
            style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.w700)),
      ]),
    );
  }
}

// ── Average badge ─────────────────────────────────────────────────────────────

class _AvgBadge extends ConsumerWidget {
  final double avg;
  final bool hasDebt;
  const _AvgBadge({required this.avg, required this.hasDebt});

  Color get _color {
    if (hasDebt)    return AppTheme.error;
    if (avg >= 4.5) return AppTheme.success;
    if (avg >= 3.5) return const Color(0xFF7CB9E8);
    if (avg >= 2.5) return AppTheme.warning;
    return AppTheme.error;
  }

  IconData get _arrow {
    if (avg >= 4.5) return Icons.arrow_drop_up;
    if (avg <= 2.5) return Icons.arrow_drop_down;
    return Icons.remove;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: _color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _color.withOpacity(0.25)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(_arrow, color: _color, size: 18),
      const SizedBox(width: 2),
      Text(avg.toStringAsFixed(2),
          style: TextStyle(color: _color, fontSize: 16, fontWeight: FontWeight.w700)),
    ]),
  );
}

// ── Grade pills ───────────────────────────────────────────────────────────────

class _GradePillsRow extends ConsumerWidget {
  final Map<int, int> distribution;
  const _GradePillsRow({required this.distribution});

  static Color _color(int g) {
    switch (g) {
      case 5:  return AppTheme.success;
      case 4:  return const Color(0xFF7CB9E8);
      case 3:  return AppTheme.warning;
      case 2:  return AppTheme.error;
      default: return AppTheme.textMuted;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // МЭШ style: ONE box per grade value, count as subscript bottom-right
    final sorted = distribution.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: sorted.map((e) {
          final g = e.key;
          final count = e.value;
          final c = _color(g);
          return Container(
            width: 46,
            height: 46,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.withOpacity(0.55), width: 1.5),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Text('$g',
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700)),
                if (count > 1)
                  Positioned(
                    bottom: 4, right: 5,
                    child: Text('$count',
                        style: TextStyle(
                            color: c,
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Record book tab ───────────────────────────────────────────────────────────

class _RecordbookTab extends ConsumerWidget {
  final List<RecordEntry> entries;
  const _RecordbookTab({required this.entries});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (entries.isEmpty) {
      return const Center(
          child: Text('Нет данных',
              style: TextStyle(color: AppTheme.textSecondary)));
    }

    final grouped = <String, List<RecordEntry>>{};
    for (final e in entries) {
      final k = 'Курс ${e.course}, семестр ${e.semester}';
      grouped.putIfAbsent(k, () => []).add(e);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final g in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(g.key,
                style: const TextStyle(color: AppTheme.accent,
                    fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          ...g.value.map((e) => _RecordRow(entry: e)),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 20),
      ],
    );
  }
}

class _RecordRow extends ConsumerWidget {
  final RecordEntry entry;
  const _RecordRow({required this.entry});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    margin: const EdgeInsets.only(bottom: 6),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.divider)),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(entry.discipline,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
        const SizedBox(height: 2),
        Text(entry.type,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ])),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: entry.gradeColor.withOpacity(0.15),
            borderRadius: BorderRadius.circular(8)),
        child: Text(entry.grade,
            style: TextStyle(color: entry.gradeColor,
                fontSize: 11, fontWeight: FontWeight.w600)),
      ),
    ]),
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
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.cloud_off_rounded, color: AppTheme.textMuted, size: 52),
        const SizedBox(height: 16),
        const Text('Ошибка загрузки',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
        const SizedBox(height: 8),
        Text(error,
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
            textAlign: TextAlign.center, maxLines: 3,
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Повторить'),
        ),
      ]),
    ),
  );
}
