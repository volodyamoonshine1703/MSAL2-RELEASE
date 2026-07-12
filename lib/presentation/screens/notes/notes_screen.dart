import '../../../core/providers.dart';
// lib/presentation/screens/notes/notes_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/local_db_service.dart';
import '../../../data/services/api_service.dart';
import '../../../data/models/grade_model.dart';
import '../../../data/models/homework_model.dart';
import '../homework/homework_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../../../core/providers/scaffold_provider.dart';

// ── Notes Screen with 3 tabs ─────────────────────────────────────────────────

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key});
  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Заметки'),
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
            Tab(icon: Icon(Icons.warning_amber_rounded, size: 18), text: 'Долги'),
            Tab(icon: Icon(Icons.assignment_outlined, size: 18), text: 'ДЗ'),
            Tab(icon: Icon(Icons.schedule_outlined, size: 18), text: 'Расп.'),
            Tab(icon: Icon(Icons.note_alt_outlined, size: 18), text: 'Общие'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _DebtNotesTab(ref: ref),
          _HomeworkTab(ref: ref),
          const _RoutineTab(),
          const _GeneralNotesTab(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 1: Debt Notes
// ═══════════════════════════════════════════════════════════════════════════════

class _DebtNotesTab extends ConsumerWidget {
  final WidgetRef ref;
  const _DebtNotesTab({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressAsync = ref.watch(progressWithLessonsProvider);
    return progressAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppTheme.textMuted))),
      data: (items) {
        final debts = items.where((i) => i.hasDebt).toList();
        if (debts.isEmpty) {
          return _EmptyState(icon: Icons.check_circle_outline, text: 'Задолженностей нет!', color: AppTheme.success);
        }
        return _DebtNotesList(items: debts);
      },
    );
  }
}

class _DebtNotesList extends ConsumerStatefulWidget {
  final List<ProgressItem> items;
  const _DebtNotesList({required this.items});
  @override
  ConsumerState<_DebtNotesList> createState() => _DebtNotesListState();
}

class _DebtNotesListState extends ConsumerState<_DebtNotesList> {
  final Map<String, String> _notes = {};
  final Map<String, DateTime> _deadlines = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final dl = await ref.read(localDbServiceProvider).getAllDebtDeadlines();
    for (final item in widget.items) {
      final n = await ref.read(localDbServiceProvider).getProgressNote(item.disciplineId);
      if (mounted) setState(() {
        if (n != null) _notes[item.disciplineId] = n;
        if (dl.containsKey(item.disciplineId)) _deadlines[item.disciplineId] = dl[item.disciplineId]!;
      });
    }
  }

  void _editNote(ProgressItem item) {
    final ctrl = TextEditingController(text: _notes[item.disciplineId] ?? '');
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(child: Text(item.discipline, style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14))),
            IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted), onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 12),
          TextField(controller: ctrl, maxLines: 4, autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(hintText: 'Тема отработки, дата, детали...')),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () async {
              await ref.read(localDbServiceProvider).saveProgressNote(item.disciplineId, ctrl.text.trim());
              setState(() => _notes[item.disciplineId] = ctrl.text.trim());
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Сохранить'),
          )),
        ]),
      ),
    );
  }

  Future<void> _pickDeadline(ProgressItem item) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context, initialDate: _deadlines[item.disciplineId] ?? now.add(const Duration(days: 7)),
      firstDate: now, lastDate: DateTime(now.year + 2), locale: const Locale('ru'),
    );
    if (picked != null) {
      await ref.read(localDbServiceProvider).saveDebtDeadline(item.disciplineId, picked);
      if (mounted) setState(() => _deadlines[item.disciplineId] = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.items.length,
      itemBuilder: (_, i) {
        final item = widget.items[i];
        final note = _notes[item.disciplineId];
        final dl = _deadlines[item.disciplineId];
        return _DebtNoteCard(item: item, note: note, deadline: dl,
          onEditNote: () => _editNote(item), onPickDeadline: () => _pickDeadline(item));
      },
    );
  }
}

class _DebtNoteCard extends ConsumerWidget {
  final ProgressItem item;
  final String? note;
  final DateTime? deadline;
  final VoidCallback onEditNote;
  final VoidCallback onPickDeadline;
  const _DebtNoteCard({required this.item, this.note, this.deadline, required this.onEditNote, required this.onPickDeadline});

  static final _inFmt = DateFormat('dd.MM.yyyy');
  static final _outFmt = DateFormat('d MMMM yyyy, EE', 'ru_RU');

  String _fmtDate(String raw) {
    try { return _outFmt.format(_inFmt.parseStrict(raw)); } catch (_) {}
    try { return _outFmt.format(DateTime.parse(raw)); } catch (_) {}
    return raw;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final daysLeft = deadline?.difference(DateTime.now()).inDays;
    final isOverdue = daysLeft != null && daysLeft < 0;
    final dlColor = isOverdue ? AppTheme.error : (daysLeft != null && daysLeft <= 2) ? AppTheme.warning : AppTheme.success;
    final debtLessons = item.debtLessons;
    final debtCount = item.debtCount;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.error.withOpacity(0.25))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [AppTheme.error.withOpacity(0.08), Colors.transparent],
              begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.error.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.warning_rounded, color: AppTheme.error, size: 14),
                const SizedBox(width: 4),
                Text('$debtCount', style: const TextStyle(color: AppTheme.error, fontSize: 16, fontWeight: FontWeight.w800)),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.discipline, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                maxLines: 2, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(_debtSuffix(debtCount), style: TextStyle(color: AppTheme.error.withOpacity(0.8), fontSize: 11)),
            ])),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // ── Debt lessons list ──
            if (debtLessons.isNotEmpty) ...[
              const Text('Даты двоек:', style: TextStyle(color: AppTheme.textMuted, fontSize: 11, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              ...debtLessons.map((l) {
                final twosCount = l.grades.where((g) => g == 2).length;
                return Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.error.withOpacity(0.12)),
                  ),
                  child: Row(children: [
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.15), shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded, size: 12, color: AppTheme.error),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_fmtDate(l.date),
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12, fontWeight: FontWeight.w500))),
                    // Show each "2" as a chip
                    ...List.generate(twosCount, (_) => Container(
                      margin: const EdgeInsets.only(left: 4),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.18), borderRadius: BorderRadius.circular(5)),
                      child: const Text('2', style: TextStyle(color: AppTheme.error, fontSize: 11, fontWeight: FontWeight.w700)),
                    )),
                  ]),
                );
              }),
              const SizedBox(height: 8),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(8)),
                child: const Row(children: [
                  Icon(Icons.info_outline, color: AppTheme.textMuted, size: 14),
                  SizedBox(width: 8),
                  Text('Детали занятий не загружены', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                ]),
              ),
              const SizedBox(height: 8),
            ],

            // ── Deadline ──
            GestureDetector(
              onTap: onPickDeadline,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(color: deadline != null ? dlColor.withOpacity(0.07) : AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(10), border: Border.all(color: deadline != null ? dlColor.withOpacity(0.3) : AppTheme.divider)),
                child: Row(children: [
                  Icon(Icons.calendar_today_outlined, size: 14, color: deadline != null ? dlColor : AppTheme.accent),
                  const SizedBox(width: 8),
                  Text(deadline != null
                    ? (isOverdue ? 'Просрочено — ${DateFormat('d.MM.yyyy').format(deadline!)}'
                      : 'Дедлайн: ${DateFormat('d.MM.yyyy').format(deadline!)} (${daysLeft! + 1} дн.)')
                    : 'Установить дедлайн',
                    style: TextStyle(color: deadline != null ? dlColor : AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(height: 8),

            // ── Note ──
            GestureDetector(
              onTap: onEditNote,
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: note?.isNotEmpty == true ? AppTheme.accent.withOpacity(0.06) : AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: note?.isNotEmpty == true ? AppTheme.accent.withOpacity(0.2) : AppTheme.divider)),
                child: Row(children: [
                  Icon(note?.isNotEmpty == true ? Icons.edit_note : Icons.add_circle_outline, color: AppTheme.accent, size: 15),
                  const SizedBox(width: 8),
                  Expanded(child: Text(note?.isNotEmpty == true ? note! : 'Добавить заметку...',
                    style: TextStyle(color: note?.isNotEmpty == true ? AppTheme.textPrimary : AppTheme.textMuted, fontSize: 12,
                      fontStyle: note?.isNotEmpty == true ? FontStyle.normal : FontStyle.italic),
                    maxLines: 3, overflow: TextOverflow.ellipsis)),
                ]),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  static String _debtSuffix(int n) {
    final word = n % 10 == 1 && n % 100 != 11 ? 'двойка'
        : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 10 || n % 100 >= 20)) ? 'двойки' : 'двоек';
    return '$n $word';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 2: Homework (reuses HomeworkListScreen content)
// ═══════════════════════════════════════════════════════════════════════════════

class _HomeworkTab extends ConsumerWidget {
  final WidgetRef ref;
  const _HomeworkTab({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hwAsync = ref.watch(allHomeworkProvider);
    return hwAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppTheme.textSecondary))),
      data: (all) {
        final active = all.where((h) => !h.isEmpty).toList();
        if (active.isEmpty) {
          return _EmptyState(icon: Icons.assignment_outlined, text: 'Нет домашних заданий', color: AppTheme.textMuted,
            subtitle: 'Добавляй ДЗ прямо из расписания');
        }
        final overdue = active.where((h) => h.isOverdue).toList();
        final hot = active.where((h) => h.isHot && !h.isOverdue).toList();
        final upcoming = active.where((h) => !h.isHot && !h.isOverdue && h.deadline != null).toList();
        final noDl = active.where((h) => h.deadline == null && !h.isOverdue && !h.isHot).toList();

        return ListView(padding: const EdgeInsets.all(16), children: [
          if (overdue.isNotEmpty) ...[_Hdr('🚨 Просрочено', AppTheme.error), const SizedBox(height: 8),
            ...overdue.map((hw) => _HwCard(hw: hw)), const SizedBox(height: 16)],
          if (hot.isNotEmpty) ...[_Hdr('🔥 Горящие', AppTheme.warning), const SizedBox(height: 8),
            ...hot.map((hw) => _HwCard(hw: hw)), const SizedBox(height: 16)],
          if (upcoming.isNotEmpty) ...[_Hdr('📅 Предстоящие', AppTheme.accent), const SizedBox(height: 8),
            ...upcoming.map((hw) => _HwCard(hw: hw)), const SizedBox(height: 16)],
          if (noDl.isNotEmpty) ...[_Hdr('📝 Без дедлайна', AppTheme.textSecondary), const SizedBox(height: 8),
            ...noDl.map((hw) => _HwCard(hw: hw))],
        ]);
      },
    );
  }
}

class _Hdr extends ConsumerWidget {
  final String t; final Color c;
  const _Hdr(this.t, this.c);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(t, style: TextStyle(color: c, fontSize: 14, fontWeight: FontWeight.w700));
}

class _HwCard extends ConsumerWidget {
  final HomeworkModel hw;
  const _HwCard({required this.hw});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOvd = hw.isOverdue;
    final isHot = hw.isHot;
    final bc = isOvd ? AppTheme.error : isHot ? AppTheme.warning : AppTheme.divider;
    return Dismissible(
      key: Key('hw_${hw.lessonId}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(context: context, builder: (_) => AlertDialog(
          backgroundColor: AppTheme.bgCard,
          title: const Text('Удалить ДЗ?', style: TextStyle(color: AppTheme.textPrimary)),
          content: Text(hw.discipline, style: const TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
            TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Удалить', style: TextStyle(color: AppTheme.error))),
          ],
        ));
      },
      onDismissed: (_) async {
        await ref.read(localDbServiceProvider).deleteHomework(hw.lessonId);
      },
      background: Container(
        alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
        child: const Icon(Icons.delete_outline, color: AppTheme.error),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: bc.withOpacity(isOvd || isHot ? 0.4 : 1.0))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(hw.discipline, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontWeight: FontWeight.w600))),
            if (hw.deadline != null) Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: (isOvd ? AppTheme.error : isHot ? AppTheme.warning : AppTheme.accent).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8)),
              child: Text(isOvd ? 'Просрочено' : 'до ${DateFormat('d MMM', 'ru_RU').format(hw.deadline!)}',
                style: TextStyle(color: isOvd ? AppTheme.error : isHot ? AppTheme.warning : AppTheme.accent, fontSize: 10, fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          if (hw.hasServerHomework) Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(color: AppTheme.success.withOpacity(0.12), borderRadius: BorderRadius.circular(4)),
              child: const Text('от препода', style: TextStyle(color: AppTheme.success, fontSize: 9))),
            const SizedBox(width: 6),
            Expanded(child: Text(hw.serverText!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              maxLines: 2, overflow: TextOverflow.ellipsis)),
          ]),
          if (hw.localText?.isNotEmpty == true)
            Text(hw.localText!, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 3: Daily Routine
// ═══════════════════════════════════════════════════════════════════════════════

const _dayNames = ['Пн', 'Вт', 'Ср', 'Чт', 'Пт', 'Сб', 'Вс'];

class _RoutineTab extends ConsumerStatefulWidget {
  const _RoutineTab();
  @override
  ConsumerState<_RoutineTab> createState() => _RoutineTabState();
}

class _RoutineTabState extends ConsumerState<_RoutineTab> {
  int _selectedDay = DateTime.now().weekday - 1; // 0=Mon
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await ref.read(localDbServiceProvider).getDailyRoutine(_selectedDay);
    if (mounted) setState(() { _items = rows; _loading = false; });
  }

  void _switchDay(int d) {
    setState(() { _selectedDay = d; _loading = true; });
    _load();
  }

  Future<void> _addItem() async {
    final result = await _showEditor(context);
    if (result != null) {
      await ref.read(localDbServiceProvider).addRoutineItem(
        timeSlot: result['time']!, title: result['title']!, note: result['note'] ?? '',
        dayOfWeek: _selectedDay, sortOrder: _items.length);
      _load();
    }
  }

  Future<void> _editItem(Map<String, dynamic> item) async {
    final result = await _showEditor(context, time: item['timeSlot'] as String, title: item['title'] as String, note: item['note'] as String? ?? '');
    if (result != null) {
      await ref.read(localDbServiceProvider).updateRoutineItem(item['id'] as int,
        timeSlot: result['time']!, title: result['title']!, note: result['note']);
      _load();
    }
  }

  Future<void> _deleteItem(int id) async {
    await ref.read(localDbServiceProvider).deleteRoutineItem(id);
    _load();
  }

  Future<Map<String, String>?> _showEditor(BuildContext ctx, {String time = '', String title = '', String note = ''}) async {
    final timeCtrl = TextEditingController(text: time);
    final titleCtrl = TextEditingController(text: title);
    final noteCtrl = TextEditingController(text: note);
    return showModalBottomSheet<Map<String, String>>(
      context: ctx, isScrollControlled: true, backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(child: Text('Пункт распорядка', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15))),
            IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            SizedBox(width: 90, child: TextField(controller: timeCtrl,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: const InputDecoration(hintText: '09:00', labelText: 'Время'))),
            const SizedBox(width: 12),
            Expanded(child: TextField(controller: titleCtrl,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              decoration: const InputDecoration(hintText: 'Завтрак', labelText: 'Название'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: noteCtrl, maxLines: 2,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(hintText: 'Доп. заметка (необязательно)', labelText: 'Заметка')),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, {'time': timeCtrl.text.trim(), 'title': titleCtrl.text.trim(), 'note': noteCtrl.text.trim()});
            },
            child: const Text('Сохранить'),
          )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Day selector
      Container(
        height: 50, margin: const EdgeInsets.symmetric(vertical: 8),
        child: ListView.builder(
          scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 7,
          itemBuilder: (_, i) {
            final sel = i == _selectedDay;
            return GestureDetector(
              onTap: () => _switchDay(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 44, margin: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: sel ? AppTheme.accent : AppTheme.bgSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? AppTheme.accent : AppTheme.divider)),
                alignment: Alignment.center,
                child: Text(_dayNames[i], style: TextStyle(
                  color: sel ? Colors.white : AppTheme.textSecondary, fontSize: 13, fontWeight: sel ? FontWeight.w700 : FontWeight.w400)),
              ),
            );
          },
        ),
      ),
      // Items
      Expanded(
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _items.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.event_note_outlined, color: AppTheme.textMuted, size: 48),
                const SizedBox(height: 12),
                Text('Нет пунктов на ${_dayNames[_selectedDay]}', style: const TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: _addItem, icon: const Icon(Icons.add, size: 16), label: const Text('Добавить')),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                itemCount: _items.length,
                itemBuilder: (_, i) {
                  final it = _items[i];
                  return Dismissible(
                    key: ValueKey(it['id']),
                    direction: DismissDirection.endToStart,
                    background: Container(alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.delete_outline, color: AppTheme.error)),
                    onDismissed: (_) => _deleteItem(it['id'] as int),
                    child: GestureDetector(
                      onTap: () => _editItem(it),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.divider)),
                        child: Row(children: [
                          Container(
                            width: 52, padding: const EdgeInsets.symmetric(vertical: 6),
                            decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            alignment: Alignment.center,
                            child: Text((it['timeSlot'] as String).isNotEmpty ? it['timeSlot'] as String : '--:--',
                              style: const TextStyle(color: AppTheme.accent, fontSize: 13, fontWeight: FontWeight.w700)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(it['title'] as String, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
                            if ((it['note'] as String? ?? '').isNotEmpty)
                              Text(it['note'] as String, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                          ])),
                          const Icon(Icons.drag_handle, color: AppTheme.textMuted, size: 18),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
      // FAB area
      if (!_loading && _items.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FloatingActionButton.small(
            backgroundColor: AppTheme.accent,
            onPressed: _addItem,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
    ]);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// TAB 4: General Notes
// ═══════════════════════════════════════════════════════════════════════════════

class _GeneralNotesTab extends ConsumerStatefulWidget {
  const _GeneralNotesTab();
  @override
  ConsumerState<_GeneralNotesTab> createState() => _GeneralNotesTabState();
}

class _GeneralNotesTabState extends ConsumerState<_GeneralNotesTab> {
  List<Map<String, dynamic>> _notes = [];
  bool _loading = true;
  String _searchQuery = '';

  static const _noteColors = [
    Color(0xFF9C6FFF), Color(0xFFFF5C7C), Color(0xFF4CAF82),
    Color(0xFF7CB9E8), Color(0xFFFFB547), Color(0xFFE040FB),
  ];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final rows = _searchQuery.isEmpty
        ? await ref.read(localDbServiceProvider).getAllGeneralNotes()
        : await ref.read(localDbServiceProvider).searchGeneralNotes(_searchQuery);
    if (mounted) setState(() { _notes = rows; _loading = false; });
  }

  Future<void> _addNote() async {
    final result = await _showNoteEditor(context);
    if (result != null) {
      await ref.read(localDbServiceProvider).addGeneralNote(
        title: result['title']!, content: result['content'] ?? '',
        color: int.tryParse(result['color'] ?? '0') ?? 0,
      );
      _load();
    }
  }

  Future<void> _editNote(Map<String, dynamic> note) async {
    final result = await _showNoteEditor(context,
      title: note['title'] as String, content: note['content'] as String? ?? '',
      colorIndex: note['color'] as int? ?? 0,
    );
    if (result != null) {
      await ref.read(localDbServiceProvider).updateGeneralNote(note['id'] as int,
        title: result['title']!, content: result['content'],
        color: int.tryParse(result['color'] ?? '0') ?? 0,
      );
      _load();
    }
  }

  Future<void> _deleteNote(int id) async {
    await ref.read(localDbServiceProvider).deleteGeneralNote(id);
    _load();
  }

  Future<Map<String, String>?> _showNoteEditor(BuildContext ctx,
      {String title = '', String content = '', int colorIndex = 0}) async {
    final titleCtrl = TextEditingController(text: title);
    final contentCtrl = TextEditingController(text: content);
    int selColor = colorIndex;
    return showModalBottomSheet<Map<String, String>>(
      context: ctx, isScrollControlled: true, backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx2, setSt) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            const Expanded(child: Text('Заметка', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 15))),
            IconButton(icon: const Icon(Icons.close, color: AppTheme.textMuted), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 8),
          Row(children: List.generate(_noteColors.length, (i) => GestureDetector(
            onTap: () => setSt(() => selColor = i),
            child: Container(
              width: 28, height: 28, margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: _noteColors[i].withOpacity(0.3), shape: BoxShape.circle,
                border: Border.all(color: selColor == i ? _noteColors[i] : Colors.transparent, width: 2),
              ),
            ),
          ))),
          const SizedBox(height: 12),
          TextField(controller: titleCtrl, autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(hintText: 'Название', labelText: 'Название')),
          const SizedBox(height: 10),
          TextField(controller: contentCtrl, maxLines: 5,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(hintText: 'Содержание...', labelText: 'Содержание')),
          const SizedBox(height: 14),
          SizedBox(width: double.infinity, child: ElevatedButton(
            onPressed: () {
              if (titleCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, {'title': titleCtrl.text.trim(), 'content': contentCtrl.text.trim(), 'color': '$selColor'});
            },
            child: const Text('Сохранить'),
          )),
        ]),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      // Search bar
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Поиск заметок...',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            prefixIcon: const Icon(Icons.search, color: AppTheme.textMuted, size: 18),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.divider)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppTheme.divider)),
            filled: true, fillColor: AppTheme.bgSurface,
          ),
          onChanged: (q) { _searchQuery = q; _load(); },
        ),
      ),
      Expanded(
        child: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.accent))
          : _notes.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.note_alt_outlined, color: AppTheme.textMuted, size: 48),
                const SizedBox(height: 12),
                Text(_searchQuery.isEmpty ? 'Нет заметок' : 'Ничего не найдено',
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                if (_searchQuery.isEmpty) ...[
                  const SizedBox(height: 16),
                  ElevatedButton.icon(onPressed: _addNote, icon: const Icon(Icons.add, size: 16), label: const Text('Добавить')),
                ],
              ]))
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                itemCount: _notes.length,
                itemBuilder: (_, i) {
                  final n = _notes[i];
                  final ci = (n['color'] as int? ?? 0).clamp(0, _noteColors.length - 1);
                  final c = _noteColors[ci];
                  final updatedAt = DateTime.tryParse(n['updatedAt'] as String? ?? '');
                  return Dismissible(
                    key: ValueKey(n['id']),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) async => await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                      backgroundColor: AppTheme.bgCard,
                      title: const Text('Удалить заметку?', style: TextStyle(color: AppTheme.textPrimary)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
                        TextButton(onPressed: () => Navigator.pop(context, true), child: Text('Удалить', style: TextStyle(color: AppTheme.error))),
                      ],
                    )),
                    onDismissed: (_) => _deleteNote(n['id'] as int),
                    background: Container(
                      alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20),
                      decoration: BoxDecoration(color: AppTheme.error.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.delete_outline, color: AppTheme.error),
                    ),
                    child: GestureDetector(
                      onTap: () => _editNote(n),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.withOpacity(0.3)),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(n['title'] as String, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
                              maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (updatedAt != null) Text(DateFormat('d MMM', 'ru_RU').format(updatedAt),
                              style: const TextStyle(color: AppTheme.textMuted, fontSize: 10)),
                          ]),
                          if ((n['content'] as String? ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(n['content'] as String, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                          ],
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
      if (!_loading && _notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: FloatingActionButton.small(
            backgroundColor: AppTheme.accent,
            onPressed: _addNote,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
    ]);
  }
}

// ── Shared empty state ────────────────────────────────────────────────────────

class _EmptyState extends ConsumerWidget {
  final IconData icon; final String text; final Color color; final String? subtitle;
  const _EmptyState({required this.icon, required this.text, required this.color, this.subtitle});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    Icon(icon, color: color, size: 52),
    const SizedBox(height: 14),
    Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
    if (subtitle != null) ...[const SizedBox(height: 6), Text(subtitle!, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))],
  ]));
}
