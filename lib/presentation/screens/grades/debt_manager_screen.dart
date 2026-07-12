import '../../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/presentation/screens/grades/debt_manager_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/grade_model.dart';
import '../../../data/models/schedule_model.dart';
import '../../../data/models/chat_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/local_db_service.dart';
import '../../../data/services/ai_service.dart';
import '../../../data/models/consultation_model.dart';

final _inFmt  = DateFormat('dd.MM.yyyy');
final _outFmt = DateFormat('d MMMM yyyy', 'ru_RU');

String _fmtDate(String raw) {
  try { return _outFmt.format(_inFmt.parseStrict(raw)); } catch (_) {}
  try { return _outFmt.format(DateTime.parse(raw)); } catch (_) {}
  return raw;
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

// ── Screen ────────────────────────────────────────────────────────────────────

class DebtManagerScreen extends ConsumerStatefulWidget {
  final List<ProgressItem> items;
  const DebtManagerScreen({super.key, required this.items});

  @override
  ConsumerState<DebtManagerScreen> createState() => _DebtManagerScreenState();
}

class _DebtManagerScreenState extends ConsumerState<DebtManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  final Map<String, String>   _notes     = {};
  final Map<String, DateTime> _deadlines = {};

  List<ProgressItem> get _debtItems =>
      widget.items.where((i) => i.hasDebt).toList();

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 1, vsync: this);
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    final allDeadlines = await ref.read(localDbServiceProvider).getAllDebtDeadlines();
    for (final item in widget.items) {
      final note =
          await ref.read(localDbServiceProvider).getProgressNote(item.disciplineId);
      if (mounted) {
        setState(() {
          if (note != null) _notes[item.disciplineId] = note;
          if (allDeadlines.containsKey(item.disciplineId)) {
            _deadlines[item.disciplineId] = allDeadlines[item.disciplineId]!;
          }
        });
      }
    }
  }

  Future<void> _pickDeadline(ProgressItem item) async {
    final now     = DateTime.now();
    final initial = _deadlines[item.disciplineId] ??
        now.add(const Duration(days: 7));
    final picked  = await showDatePicker(
      context: context,
      initialDate: initial.isAfter(now)
          ? initial
          : now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 2),
      locale: const Locale('ru'),
    );
    if (picked != null) {
      await ref.read(localDbServiceProvider)
          .saveDebtDeadline(item.disciplineId, picked);
      if (mounted) setState(() => _deadlines[item.disciplineId] = picked);
    }
  }

  Future<void> _clearDeadline(ProgressItem item) async {
    await ref.read(localDbServiceProvider).clearDebtDeadline(item.disciplineId);
    if (mounted) setState(() => _deadlines.remove(item.disciplineId));
  }

  void _editNote(ProgressItem item) {
    final ctrl = TextEditingController(text: _notes[item.disciplineId] ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [
            Expanded(
                child: Text(item.discipline,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14))),
            IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textMuted),
                onPressed: () => Navigator.pop(context)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            maxLines: 4,
            autofocus: true,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: const InputDecoration(
                hintText: 'Тема отработки, дата, детали...'),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                await ref.read(localDbServiceProvider)
                    .saveProgressNote(item.disciplineId, ctrl.text.trim());
                setState(
                    () => _notes[item.disciplineId] = ctrl.text.trim());
                if (mounted) Navigator.pop(context);
              },
              child: const Text('Сохранить'),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Задолженности'),
        backgroundColor: AppTheme.bgDark,
        bottom: TabBar(
          controller: _tabs,
          labelColor: AppTheme.accent,
          unselectedLabelColor: AppTheme.textMuted,
          indicatorColor: AppTheme.accent,
          tabs: [
            Tab(text: 'Двойки (${_debtItems.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          // ── Tab 1: Двойки ──────────────────────────────────────────────
          _debtItems.isEmpty
              ? _EmptyState(
                  icon: Icons.check_circle_outline,
                  text: 'Двоек нет!',
                  color: AppTheme.success)
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _debtItems.length,
                  itemBuilder: (_, i) {
                    final item = _debtItems[i];
                    return _DebtCard(
                      item: item,
                      note: _notes[item.disciplineId],
                      deadline: _deadlines[item.disciplineId],
                      onEditNote: () => _editNote(item),
                      onPickDeadline: () => _pickDeadline(item),
                      onClearDeadline: () => _clearDeadline(item),
                    );
                  }),


        ],
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends ConsumerWidget {
  final IconData icon;
  final String text;
  final Color color;
  const _EmptyState(
      {required this.icon, required this.text, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: color, size: 56),
          const SizedBox(height: 16),
          Text(text,
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 16)),
        ]),
      );
}

// ── Debt card (grade=2) ────────────────────────────────────────────────────────

class _DebtCard extends ConsumerWidget {
  final ProgressItem item;
  final String? note;
  final DateTime? deadline;
  final VoidCallback onEditNote;
  final VoidCallback onPickDeadline;
  final VoidCallback onClearDeadline;

  const _DebtCard({
    required this.item,
    required this.note,
    this.deadline,
    required this.onEditNote,
    required this.onPickDeadline,
    required this.onClearDeadline,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtLessons = item.debtLessons;
    final debtCount   = item.debtCount;
    final suffix      = debtCount == 1 ? '' : debtCount < 5 ? 'а' : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.error.withOpacity(0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [AppTheme.error.withOpacity(0.08), Colors.transparent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('2',
                  style: TextStyle(
                      color: AppTheme.error,
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
            ),
            const SizedBox(width: 12),
            Expanded(
                child: Text(item.discipline,
                    style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 14))),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppTheme.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('$debtCount раз$suffix',
                  style: const TextStyle(
                      color: AppTheme.error,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (debtLessons.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Занятия с двойкой не загружены.',
                    style:
                        TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              )
            else
              ...debtLessons.take(5).map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      const Icon(Icons.event,
                          size: 13, color: AppTheme.error),
                      const SizedBox(width: 6),
                      Text(_fmtDate(l.date),
                          style: const TextStyle(
                              color: AppTheme.textSecondary, fontSize: 12)),
                      const SizedBox(width: 8),
                      ...l.grades.where((g) => g == 2).map((g) => Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                                color: AppTheme.error.withOpacity(0.18),
                                borderRadius: BorderRadius.circular(5)),
                            child: Text('$g',
                                style: const TextStyle(
                                    color: AppTheme.error,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700)),
                          )),
                    ]),
                  )),

            if (debtLessons.length > 5)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('+ ещё ${debtLessons.length - 5}...',
                    style: const TextStyle(
                        color: AppTheme.textMuted, fontSize: 11)),
              ),

            const SizedBox(height: 8),

            // Deadline
            _DeadlineRow(
              deadline: deadline,
              onPick: onPickDeadline,
              onClear: onClearDeadline,
            ),
            const SizedBox(height: 8),

            // Note
            _NoteRow(note: note, onTap: onEditNote),
            const SizedBox(height: 8),

            // Consultation
            _ConsultationRow(item: item),
          ]),
        ),
      ]),
    );
  }
}

// ── Consultation row ─────────────────────────────────────────────────────────

class _ConsultationRow extends ConsumerWidget {
  final ProgressItem item;
  const _ConsultationRow({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _showConsultationDialog(context, item),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF6366F1).withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
        ),
        child: const Row(children: [
          Icon(Icons.psychology_outlined, color: Color(0xFF6366F1), size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Записаться на консультацию',
              style: TextStyle(
                color: Color(0xFF6366F1),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Icon(Icons.chevron_right, color: Color(0xFF6366F1), size: 16),
        ]),
      ),
    );
  }

  void _showConsultationDialog(BuildContext context, ProgressItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ConsultationSheet(item: item),
    );
  }
}

class _ConsultationSheet extends ConsumerStatefulWidget {
  final ProgressItem item;
  const _ConsultationSheet({required this.item});

  @override
  ConsumerState<_ConsultationSheet> createState() => _ConsultationSheetState();
}

class _ConsultationSheetState extends ConsumerState<_ConsultationSheet> {
  bool _loading = true;
  String _status = 'Загрузка данных...';
  
  List<ConsultationTeacher> _teachers = [];
  List<ConsultationTheme> _themes = [];
  List<ConsultationSlot> _slots = [];
  
  ConsultationTeacher? _selectedTeacher;
  ConsultationTheme? _selectedTheme;
  
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _status = 'Загрузка преподавателей...');
      final teachers = await ref.read(apiServiceProvider).getConsultationTeachers(widget.item.disciplineId);
      
      setState(() => _status = 'Загрузка тем...');
      final themes = await ref.read(apiServiceProvider).getConsultationThemes();
      
      if (!mounted) return;
      setState(() {
        _teachers = teachers;
        _themes = themes;
        
        // Try to pre-select the teacher from the debt lessons
        if (widget.item.debtLessons.isNotEmpty && teachers.isNotEmpty) {
           final lessonTeacher = widget.item.debtLessons.first.teacher;
           final match = teachers.where((t) => lessonTeacher.contains(t.name) || t.name.contains(lessonTeacher)).toList();
           _selectedTeacher = match.isNotEmpty ? match.first : teachers.first;
        } else if (teachers.isNotEmpty) {
           _selectedTeacher = teachers.first;
        }
        
        if (themes.isNotEmpty) _selectedTheme = themes.first;
      });
      
      if (_selectedTeacher != null) {
        await _loadSlots();
      } else {
        setState(() {
          _status = 'Преподаватели не найдены';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _status = 'Ошибка загрузки'; _loading = false; });
    }
  }
  
  Future<void> _loadSlots() async {
    if (_selectedTeacher == null) return;
    setState(() => _loading = true);
    final now = DateTime.now();
    final to = now.add(const Duration(days: 14));
    
    final slots = await ref.read(apiServiceProvider).getConsultationSlots(
      widget.item.disciplineId,
      _selectedTeacher!.id,
      now,
      to
    );
    
    if (mounted) {
      setState(() {
        _slots = slots;
        _loading = false;
      });
    }
  }

  Future<void> _bookSlot(ConsultationSlot slot) async {
    if (_selectedTheme == null) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Выберите тему консультации')));
       return;
    }
    
    setState(() => _loading = true);
    final success = await ref.read(apiServiceProvider).bookConsultation(
      slot, 
      widget.item.disciplineId, 
      widget.item.discipline, 
      _selectedTheme!.id
    );
    
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Вы успешно записаны на консультацию!', style: TextStyle(color: Colors.white)), backgroundColor: AppTheme.success));
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ошибка при записи на консультацию'), backgroundColor: AppTheme.error));
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.school, color: Color(0xFF6366F1), size: 24),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Запись на консультацию',
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700)),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppTheme.textMuted),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const Divider(color: AppTheme.divider, height: 24),
          if (_teachers.isNotEmpty) ...[
             const Text('Преподаватель', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
             const SizedBox(height: 6),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 12),
               decoration: BoxDecoration(
                 color: AppTheme.bgSurface,
                 borderRadius: BorderRadius.circular(10),
                 border: Border.all(color: AppTheme.divider),
               ),
               child: DropdownButtonHideUnderline(
                 child: DropdownButton<ConsultationTeacher>(
                   isExpanded: true,
                   dropdownColor: AppTheme.bgCard,
                   value: _selectedTeacher,
                   icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                   items: _teachers.map((t) => DropdownMenuItem(
                     value: t,
                     child: Text(t.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14)),
                   )).toList(),
                   onChanged: (val) {
                     setState(() => _selectedTeacher = val);
                     _loadSlots();
                   },
                 ),
               ),
             ),
             const SizedBox(height: 16),
          ],
          if (_themes.isNotEmpty) ...[
             const Text('Тема консультации', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
             const SizedBox(height: 6),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 12),
               decoration: BoxDecoration(
                 color: AppTheme.bgSurface,
                 borderRadius: BorderRadius.circular(10),
                 border: Border.all(color: AppTheme.divider),
               ),
               child: DropdownButtonHideUnderline(
                 child: DropdownButton<ConsultationTheme>(
                   isExpanded: true,
                   dropdownColor: AppTheme.bgCard,
                   value: _selectedTheme,
                   icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                   items: _themes.map((t) => DropdownMenuItem(
                     value: t,
                     child: Text(t.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                   )).toList(),
                   onChanged: (val) {
                     setState(() => _selectedTheme = val);
                   },
                 ),
               ),
             ),
             const SizedBox(height: 16),
          ],
          const Text('Доступные слоты (ближайшие 14 дней)', style: TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Color(0xFF6366F1)),
                        const SizedBox(height: 16),
                        Text(_status, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                      ],
                    ),
                  )
                : _slots.isEmpty
                    ? const Center(child: Text('Нет доступных слотов для записи', style: TextStyle(color: AppTheme.textSecondary)))
                    : ListView.builder(
                        itemCount: _slots.length,
                        itemBuilder: (context, index) {
                          final slot = _slots[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            decoration: BoxDecoration(
                              color: slot.isRecord ? AppTheme.success.withOpacity(0.1) : AppTheme.bgSurface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: slot.isRecord ? AppTheme.success.withOpacity(0.3) : AppTheme.divider),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              title: Text('${slot.day} • ${slot.between}', style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600, fontSize: 14)),
                              subtitle: Text('${slot.corps}, ${slot.auditory}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              trailing: slot.isRecord 
                                  ? const Icon(Icons.check_circle, color: AppTheme.success)
                                  : ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: slot.isFree ? const Color(0xFF6366F1) : AppTheme.bgSurface,
                                        foregroundColor: slot.isFree ? Colors.white : AppTheme.textMuted,
                                      ),
                                      onPressed: slot.isFree ? () => _bookSlot(slot) : null,
                                      child: const Text('Записаться'),
                                    ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Deadline row ───────────────────────────────────────────────────────────────

class _DeadlineRow extends ConsumerWidget {
  final DateTime? deadline;
  final VoidCallback onPick;
  final VoidCallback onClear;
  const _DeadlineRow({required this.deadline, required this.onPick, required this.onClear});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (deadline == null) {
      return GestureDetector(
        onTap: onPick,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.divider),
          ),
          child: const Row(children: [
            Icon(Icons.calendar_today_outlined, color: AppTheme.accent, size: 14),
            SizedBox(width: 8),
            Text('Установить дедлайн',
                style: TextStyle(color: AppTheme.accent, fontSize: 12)),
          ]),
        ),
      );
    }
    final now = DateTime.now();
    final isOverdue = deadline!.isBefore(now);
    final daysLeft  = deadline!.difference(now).inDays;
    final color = isOverdue ? AppTheme.error
        : daysLeft <= 2 ? AppTheme.warning : AppTheme.success;
    final label = isOverdue
        ? 'Просрочено — ${deadline!.day}.${deadline!.month}.${deadline!.year}'
        : daysLeft == 0 ? 'Дедлайн сегодня!'
        : daysLeft == 1 ? 'Завтра — ${deadline!.day}.${deadline!.month}'
        : 'Дедлайн: ${deadline!.day}.${deadline!.month}.${deadline!.year} (${ daysLeft + 1} дн.)';

    return Row(children: [
      Expanded(
        child: GestureDetector(
          onTap: onPick,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: color.withOpacity(0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.35)),
            ),
            child: Row(children: [
              Icon(Icons.calendar_today_outlined, color: color, size: 14),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color,
                  fontSize: 12, fontWeight: FontWeight.w600)),
            ]),
          ),
        ),
      ),
      const SizedBox(width: 6),
      GestureDetector(
        onTap: onClear,
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(
            color: AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.divider),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.close, size: 14, color: AppTheme.textMuted),
        ),
      ),
    ]);
  }
}

// ── Note row ───────────────────────────────────────────────────────────────────

class _NoteRow extends ConsumerWidget {
  final String? note;
  final VoidCallback onTap;
  const _NoteRow({required this.note, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (note?.isNotEmpty == true)
                ? AppTheme.accent.withOpacity(0.07)
                : AppTheme.bgSurface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: (note?.isNotEmpty == true)
                    ? AppTheme.accent.withOpacity(0.25)
                    : AppTheme.divider),
          ),
          child: Row(children: [
            Icon(
                (note?.isNotEmpty == true)
                    ? Icons.edit_note
                    : Icons.add_circle_outline,
                color: AppTheme.accent,
                size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                (note?.isNotEmpty == true)
                    ? note!
                    : 'Добавить заметку (тема отработки, детали)',
                style: TextStyle(
                  color: (note?.isNotEmpty == true)
                      ? AppTheme.textPrimary
                      : AppTheme.textMuted,
                  fontSize: 12,
                  fontStyle: (note?.isNotEmpty == true)
                      ? FontStyle.normal
                      : FontStyle.italic,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right,
                color: AppTheme.textMuted, size: 16),
          ]),
        ),
      );
}
