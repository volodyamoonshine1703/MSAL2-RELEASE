import '../../../core/providers.dart';
// lib/presentation/screens/homework/homework_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/local_db_service.dart';
import '../../../data/models/schedule_model.dart';
import '../../../data/models/homework_model.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/notification_service.dart';

// ── Providers ──────────────────────────────────────────────────────────────────

final allHomeworkProvider = FutureProvider<List<HomeworkModel>>((ref) async {
  return ref.read(localDbServiceProvider).getAllHomework();
});

final homeworkForLessonProvider =
    FutureProvider.family<HomeworkModel, ScheduleLesson>((ref, lesson) async {
  final db = ref.read(localDbServiceProvider);
  final local = await db.getLocalHomework(lesson.id);
  if (local != null && local.isLocalOverwrite) return local;

  HomeworkModel? server;
  if (lesson.homeworkId != null && lesson.homeworkId!.isNotEmpty) {
    final data = await ref.read(apiServiceProvider)
        .getHomework(lesson.id, lesson.discipline, lesson.day);
    if (data != null) {
      server = HomeworkModel.fromJson(data, lesson.id, lesson.discipline, lesson.day);
    }
  }
  // If lesson already has homework text embedded
  if (server == null && lesson.homeworkText != null) {
    server = HomeworkModel(
      lessonId: lesson.id,
      discipline: lesson.discipline,
      date: lesson.day,
      serverText: lesson.homeworkText,
    );
  }

  final base = server ??
      HomeworkModel(lessonId: lesson.id, discipline: lesson.discipline, date: lesson.day);
  if (local != null) {
    base.localText = local.localText;
    base.localFilePaths = local.localFilePaths;
    base.deadline = local.deadline;
  }
  return base;
});

// ── Inline card shown in schedule ──────────────────────────────────────────────

class HomeworkCard extends ConsumerWidget {
  final ScheduleLesson lesson;
  const HomeworkCard({super.key, required this.lesson});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hwAsync = ref.watch(homeworkForLessonProvider(lesson));
    return hwAsync.when(
      loading: () => const _Skeleton(),
      error: (_, __) => const SizedBox.shrink(),
      data: (hw) => _InlineCard(hw: hw, lesson: lesson, ref: ref),
    );
  }
}

class _InlineCard extends ConsumerWidget {
  final HomeworkModel hw;
  final ScheduleLesson lesson;
  final WidgetRef ref;
  const _InlineCard({required this.hw, required this.lesson, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasServer = hw.hasServerHomework;
    final hasLocal = hw.localText?.isNotEmpty == true;
    final hasAny = hasServer || hasLocal;
    final deadline = hw.deadline;
    final isHot = hw.isHot;
    final isOverdue = hw.isOverdue;

    return GestureDetector(
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(
          builder: (_) => HomeworkEditorScreen(hw: hw, lesson: lesson,
              onSaved: () => ref.refresh(homeworkForLessonProvider(lesson))),
        ));
      },
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isOverdue
              ? AppTheme.error.withOpacity(0.08)
              : isHot
                  ? AppTheme.warning.withOpacity(0.08)
                  : hasAny
                      ? AppTheme.accent.withOpacity(0.07)
                      : AppTheme.bgSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isOverdue
                ? AppTheme.error.withOpacity(0.4)
                : isHot
                    ? AppTheme.warning.withOpacity(0.4)
                    : hasAny
                        ? AppTheme.accent.withOpacity(0.25)
                        : AppTheme.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              // Server HW badge
              if (hasServer) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4)),
                  child: const Text('ДЗ от препода',
                      style: TextStyle(color: AppTheme.success, fontSize: 9,
                          fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
              ],
              Icon(
                isOverdue ? Icons.alarm_off : isHot ? Icons.local_fire_department : 
                hasAny ? Icons.assignment_turned_in_outlined : Icons.add_circle_outline,
                color: isOverdue ? AppTheme.error : isHot ? AppTheme.warning :
                hasAny ? AppTheme.accent : AppTheme.textMuted,
                size: 14,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hw.effectiveText.isNotEmpty
                      ? hw.effectiveText
                      : hasServer
                          ? hw.serverText!
                          : 'Добавить домашнее задание',
                  style: TextStyle(
                    color: hasAny ? AppTheme.textPrimary : AppTheme.textMuted,
                    fontSize: 11,
                    fontStyle: hasAny ? FontStyle.normal : FontStyle.italic,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ]),
            // Deadline chip
            if (deadline != null) ...[
              const SizedBox(height: 5),
              Row(children: [
                Icon(Icons.schedule, size: 11,
                    color: isOverdue ? AppTheme.error : isHot ? AppTheme.warning : AppTheme.textMuted),
                const SizedBox(width: 4),
                Text(
                  isOverdue
                      ? 'Просрочено: ${DateFormat('d MMM', 'ru_RU').format(deadline)}'
                      : isHot
                          ? 'Дедлайн через ${hw.daysUntilDeadline} д.: ${DateFormat('d MMM', 'ru_RU').format(deadline)}'
                          : 'До ${DateFormat('d MMM', 'ru_RU').format(deadline)}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: isOverdue ? AppTheme.error : isHot ? AppTheme.warning : AppTheme.textMuted,
                  ),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Homework List Screen ────────────────────────────────────────────────────────

class HomeworkListScreen extends ConsumerWidget {
  const HomeworkListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hwAsync = ref.watch(allHomeworkProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Домашние задания'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.refresh(allHomeworkProvider),
          ),
        ],
      ),
      body: hwAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (e, _) => Center(child: Text('$e', style: const TextStyle(color: AppTheme.textSecondary))),
        data: (all) {
          final overdue = all.where((h) => h.isOverdue && !h.isEmpty).toList();
          final hot = all.where((h) => h.isHot && !h.isEmpty).toList();
          final upcoming = all.where((h) => !h.isHot && !h.isOverdue && !h.isEmpty && h.deadline != null).toList();
          final noDeadline = all.where((h) => !h.isEmpty && h.deadline == null).toList();

          if (all.where((h) => !h.isEmpty).isEmpty) {
            return Center(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.assignment_outlined, color: AppTheme.textMuted, size: 56),
                const SizedBox(height: 16),
                const Text('Нет домашних заданий', style: TextStyle(color: AppTheme.textSecondary, fontSize: 16)),
                const SizedBox(height: 8),
                const Text('Добавляй ДЗ прямо из расписания',
                    style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
              ]),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (overdue.isNotEmpty) ...[
                _SectionHeader('🚨 Просрочено', AppTheme.error),
                const SizedBox(height: 8),
                ...overdue.map((hw) => _HomeworkListCard(hw: hw, ref: ref)),
                const SizedBox(height: 20),
              ],
              if (hot.isNotEmpty) ...[
                _SectionHeader('🔥 Горящие (до 2 дней)', AppTheme.warning),
                const SizedBox(height: 8),
                ...hot.map((hw) => _HomeworkListCard(hw: hw, ref: ref)),
                const SizedBox(height: 20),
              ],
              if (upcoming.isNotEmpty) ...[
                _SectionHeader('📅 Предстоящие', AppTheme.accent),
                const SizedBox(height: 8),
                ...upcoming.map((hw) => _HomeworkListCard(hw: hw, ref: ref)),
                const SizedBox(height: 20),
              ],
              if (noDeadline.isNotEmpty) ...[
                _SectionHeader('📝 Без дедлайна', AppTheme.textSecondary),
                const SizedBox(height: 8),
                ...noDeadline.map((hw) => _HomeworkListCard(hw: hw, ref: ref)),
                const SizedBox(height: 20),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _SectionHeader extends ConsumerWidget {
  final String title;
  final Color color;
  const _SectionHeader(this.title, this.color);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(title,
      style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w700));
}

class _HomeworkListCard extends ConsumerWidget {
  final HomeworkModel hw;
  final WidgetRef ref;
  const _HomeworkListCard({required this.hw, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOverdue = hw.isOverdue;
    final isHot = hw.isHot;
    final borderColor = isOverdue ? AppTheme.error : isHot ? AppTheme.warning : AppTheme.divider;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor.withOpacity(isOverdue || isHot ? 0.4 : 1.0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(hw.discipline,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
          if (hw.deadline != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: (isOverdue ? AppTheme.error : isHot ? AppTheme.warning : AppTheme.accent)
                      .withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(
                isOverdue ? 'Просрочено' :
                    'до ${DateFormat('d MMM', 'ru_RU').format(hw.deadline!)}',
                style: TextStyle(
                  color: isOverdue ? AppTheme.error : isHot ? AppTheme.warning : AppTheme.accent,
                  fontSize: 10, fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        if (hw.hasServerHomework) ...[
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(4)),
              child: const Text('от препода',
                  style: TextStyle(color: AppTheme.success, fontSize: 9)),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(hw.serverText!,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ]),
          if (hw.localText?.isNotEmpty == true) const SizedBox(height: 4),
        ],
        if (hw.localText?.isNotEmpty == true)
          Text(hw.localText!,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
              maxLines: 2, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 8),
        Text(
          hw.date.isNotEmpty
              ? 'Занятие: ${_formatDate(hw.date)}'
              : '',
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
      ]),
    );
  }

  String _formatDate(String iso) {
    try {
      return DateFormat('d MMMM yyyy', 'ru_RU').format(DateTime.parse(iso));
    } catch (_) {
      return iso;
    }
  }
}

// ── Editor Screen ──────────────────────────────────────────────────────────────

class HomeworkEditorScreen extends ConsumerStatefulWidget {
  final HomeworkModel hw;
  final ScheduleLesson lesson;
  final VoidCallback onSaved;
  const HomeworkEditorScreen(
      {super.key, required this.hw, required this.lesson, required this.onSaved});

  @override
  ConsumerState<HomeworkEditorScreen> createState() => _HomeworkEditorState();
}

class _HomeworkEditorState extends ConsumerState<HomeworkEditorScreen> {
  late TextEditingController _ctrl;
  late List<String> _files;
  DateTime? _deadline;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.hw.localText ?? '');
    _files = List.from(widget.hw.localFilePaths);
    _deadline = widget.hw.deadline;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime.now().add(const Duration(days: 3)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppTheme.accent),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result != null) {
      setState(() => _files.addAll(
          result.files.map((f) => f.path ?? '').where((p) => p.isNotEmpty)));
    }
  }


  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      widget.hw
        ..localText = _ctrl.text.trim()
        ..localFilePaths = _files
        ..deadline = _deadline
        ..isLocalOverwrite = true;
      await ref.read(localDbServiceProvider).saveLocalHomework(widget.hw);

      // Schedule notification if deadline set
      if (_deadline != null && widget.hw.effectiveText.isNotEmpty) {
        await ref.read(notificationServiceProvider).scheduleHomeworkReminder(
          id: homeworkNotifId(widget.hw.lessonId),
          discipline: widget.hw.discipline,
          deadline: _deadline!,
          text: widget.hw.effectiveText,
        );
      } else if (_deadline == null) {
        await ref.read(notificationServiceProvider)
            .cancelHomeworkReminder(homeworkNotifId(widget.hw.lessonId));
      }

      widget.onSaved();
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = widget.lesson.day.isNotEmpty
        ? DateFormat('d MMMM yyyy', 'ru_RU')
            .format(DateTime.tryParse(widget.lesson.day) ?? DateTime.now())
        : '';

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Домашнее задание'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Сохранить',
                    style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Lesson info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.divider)),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.school_outlined, color: AppTheme.accent, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.lesson.discipline,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13,
                        fontWeight: FontWeight.w500)),
                Text('${widget.lesson.startTime} — ${widget.lesson.endTime}  •  $dateStr',
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),

          // Server homework (read-only)
          if (widget.hw.hasServerHomework) ...[
            _Label('ДЗ от преподавателя', AppTheme.success),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.success.withOpacity(0.2))),
              child: Text(widget.hw.serverText!,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, height: 1.6)),
            ),
            const SizedBox(height: 20),
          ],

          // Local note
          _Label('Мои заметки', AppTheme.textSecondary),
          const SizedBox(height: 8),
          TextField(
            controller: _ctrl,
            maxLines: 6, minLines: 3,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, height: 1.6),
            decoration: const InputDecoration(hintText: 'Запишите задание, детали, ссылки...'),
          ),
          const SizedBox(height: 20),

          // Deadline picker
          _Label('Дедлайн и напоминания', AppTheme.textSecondary),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _pickDeadline,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _deadline != null ? AppTheme.accent.withOpacity(0.07) : AppTheme.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _deadline != null ? AppTheme.accent.withOpacity(0.3) : AppTheme.divider),
              ),
              child: Row(children: [
                Icon(Icons.notifications_active_outlined,
                    color: _deadline != null ? AppTheme.accent : AppTheme.textMuted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      _deadline != null
                          ? DateFormat('d MMMM yyyy', 'ru_RU').format(_deadline!)
                          : 'Установить дедлайн',
                      style: TextStyle(
                        color: _deadline != null ? AppTheme.textPrimary : AppTheme.textMuted,
                        fontSize: 14, fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (_deadline != null)
                      Text(
                        'Уведомление за 1 день и в день дедлайна',
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                      ),
                  ]),
                ),
                if (_deadline != null)
                  GestureDetector(
                    onTap: () => setState(() => _deadline = null),
                    child: const Icon(Icons.close, color: AppTheme.textMuted, size: 18),
                  )
                else
                  const Icon(Icons.chevron_right, color: AppTheme.textMuted, size: 18),
              ]),
            ),
          ),
          const SizedBox(height: 20),

          // Files
          _Label('Прикреплённые файлы', AppTheme.textSecondary),
          const SizedBox(height: 8),
          if (_files.isEmpty)
            GestureDetector(
              onTap: _pickFile,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: AppTheme.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.divider)),
                alignment: Alignment.center,
                child: const Column(children: [
                  Icon(Icons.upload_file_outlined, color: AppTheme.textMuted, size: 28),
                  SizedBox(height: 6),
                  Text('Добавить файл',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                ]),
              ),
            )
          else ...[
            ..._files.asMap().entries.map((e) => _FileChip(
                path: e.value, onRemove: () => setState(() => _files.removeAt(e.key)))),
            TextButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Ещё файл'),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _Label extends ConsumerWidget {
  final String text;
  final Color color;
  const _Label(this.text, this.color);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4));
}

class _FileChip extends ConsumerWidget {
  final String path;
  final VoidCallback onRemove;
  const _FileChip({required this.path, required this.onRemove});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = path.split('/').last.split('\\').last;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.divider)),
      child: Row(children: [
        const Icon(Icons.insert_drive_file_outlined, color: AppTheme.accent, size: 16),
        const SizedBox(width: 10),
        Expanded(child: Text(name,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12),
            overflow: TextOverflow.ellipsis)),
        GestureDetector(onTap: onRemove,
            child: const Icon(Icons.close, color: AppTheme.textMuted, size: 16)),
      ]),
    );
  }
}


class _Skeleton extends ConsumerWidget {
  const _Skeleton();
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    margin: const EdgeInsets.only(top: 8), height: 32,
    decoration: BoxDecoration(color: AppTheme.bgSurface, borderRadius: BorderRadius.circular(8)),
  );
}
