import '../../../core/providers.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_model.dart';
import '../../../data/services/ai_service.dart';
import '../../../data/services/api_service.dart';
import '../../../data/services/myprepod_service.dart';
import '../../../data/models/consultation_model.dart';

class RecoveryPlanScreen extends ConsumerStatefulWidget {
  const RecoveryPlanScreen({Key? key}) : super(key: key);

  @override
  _RecoveryPlanScreenState createState() => _RecoveryPlanScreenState();
}

class _RecoveryPlanScreenState extends ConsumerState<RecoveryPlanScreen> {
  bool _isLoading = false;
  String _plan = '';
  String _status = '';
  List<_RecoverySubject> _subjects = [];
  String _strategy = '';

  @override
  void initState() {
    super.initState();
    _generatePlan();
  }

  String _formatDateTime(String iso) {
    try {
      final dt = DateTime.parse(iso);
      final months = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
      return '${dt.day} ${months[dt.month]}, ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso.split('T').join(' ').split('.')[0];
    }
  }

  Future<void> _generatePlan() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _status = 'Анализ дисциплин и задолженностей...';
      _plan = '';
      _subjects = [];
      _strategy = '';
    });

    try {
      final items = await ref.read(apiServiceProvider).getProgressWithLessons();
      // Include all problematic subjects: debts, no access, or low progress
      final itemsToPlan = items.where((i) => i.hasDebt || !i.access || i.barsScore < 55).toList();

      if (itemsToPlan.isEmpty) {
        setState(() {
          _plan = 'У вас нет задолженностей или критически низкого прогресса. План не требуется.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _status = 'Сбор данных по ${itemsToPlan.length} предметам...';
      });

      // Data structures to hold raw objects for the prompt and UI
      final List<Map<String, dynamic>> rawData = [];

      await Future.wait(itemsToPlan.map((d) async {
        final Map<String, dynamic> dData = {
          'discipline': d.discipline,
          'disciplineId': d.disciplineId,
          'teachers': [],
        };
        
        try {
          final teachers = await ref.read(apiServiceProvider).getConsultationTeachers(d.disciplineId);
          if (teachers.isNotEmpty) {
            final teacherResults = await Future.wait(teachers.take(3).map((t) async {
              try {
                final mpData = await ref.read(myprepodServiceProvider).getTeacherRating(t.name);
                final slots = (await ref.read(apiServiceProvider).getConsultationSlots(
                  d.disciplineId, 
                  t.id, 
                  DateTime.now(), 
                  DateTime.now().add(const Duration(days: 90))
                )).where((s) => !s.isRecord).toList();

                return {
                  'id': t.id,
                  'name': t.name,
                  'rating': mpData?.rating ?? '0.0',
                  'reviews': mpData?.reviews ?? [],
                  'slots': slots.take(3).map((s) => { 
                    'id': s.raw['id'] ?? '',
                    'time': _formatDateTime(s.startConsultation.isNotEmpty ? s.startConsultation : s.start),
                    'auditory': s.auditory,
                    'raw': s,
                  }).toList(),
                };
              } catch (_) {
                return null;
              }
            }));
            dData['teachers'] = teacherResults.where((t) => t != null).toList();
          }
        } catch (_) {}
        // Always add the subject, even if no teachers found
        rawData.add(dData);
      }));

      if (rawData.isEmpty) {
        setState(() {
          _plan = 'Не удалось получить данные о ваших дисциплинах. Попробуйте обновить страницу.';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _status = 'ИИ составляет план по ${rawData.length} предметам...';
      });

      final prompt = '''
Ты — ИИ МГЮА. Создай ПОЛНЫЙ JSON-план для ВСЕХ ${rawData.length} предметов. НЕ ПРОПУСКАЙ НИ ОДИН ПРЕДМЕТ.
Цель: лояльные/халявные преподы (анализируй revs: "добрый", "халява").

ДАННЫЕ:
${jsonEncode(rawData.map((d) => {
  's': d['discipline'],
  't': (d['teachers'] as List).map((t) => {
    'n': t['name'],
    'r': t['rating'],
    'rv': t['reviews'],
    'sl': (t['slots'] as List).map((s) => s['time']).toList()
  }).toList()
}).toList())}

ЗАДАЧА:
Верни JSON со стратегией и ВСЕМИ предметами (subjects):
{
  "strategy": "совет",
  "subjects": [
    {
      "name": "Предмет",
      "description": "суть",
      "best_option": {"teacher_name": "ФИО", "why": "аргумент + цитата", "slots_indices": [0]},
      "alternatives": [{"teacher_name": "ФИО", "why": "...", "slots_indices": [0]}]
    }
  ]
}
ОТВЕТЬ ТОЛЬКО JSON. НЕ ПРОПУСКАЙ ПРЕДМЕТЫ.
''';

      final result = await ref.read(aiServiceProvider).sendMessage(
        session: ChatSession.create(title: 'Recovery Plan'),
        userText: prompt,
      );

      final startIdx = result.text.indexOf('{');
      final endIdx = result.text.lastIndexOf('}');
      if (startIdx == -1 || endIdx == -1) throw Exception('JSON не найден в ответе ИИ');
      final cleanJson = result.text.substring(startIdx, endIdx + 1);
      final decoded = jsonDecode(cleanJson);

      _strategy = decoded['strategy'] ?? '';
      _subjects = (decoded['subjects'] as List).map((s) {
        final disciplineName = s['name'];
        final rawDiscipline = rawData.firstWhere((r) => r['discipline'] == disciplineName, orElse: () => <String, dynamic>{});
        
        _RecoveryOption _parseOption(Map<String, dynamic> opt) {
          final teacherName = opt['teacher_name'];
          final List<_RecoverySlot> slots = [];
          String rating = 'неизвестно';
          
          if (rawDiscipline.isNotEmpty) {
            final teacherMatches = (rawDiscipline['teachers'] as List).where((t) => t['name'] == teacherName);
            if (teacherMatches.isNotEmpty) {
              final t = teacherMatches.first;
              rating = t['rating'].toString();
              final indices = (opt['slots_indices'] as List? ?? []).cast<int>();
              for (var idx in indices) {
                if (idx < (t['slots'] as List).length) {
                  final slotData = t['slots'][idx];
                  slots.add(_RecoverySlot(
                    time: slotData['time'],
                    auditory: slotData['auditory'],
                    slot: slotData['raw'],
                    disciplineId: rawDiscipline['disciplineId'],
                    disciplineName: disciplineName,
                    teacherRating: rating,
                  ));
                }
              }
            }
          }
          return _RecoveryOption(
            teacherName: teacherName,
            why: opt['why'] ?? '',
            rating: rating,
            slots: slots,
          );
        }

        return _RecoverySubject(
          name: disciplineName,
          description: s['description'] ?? '',
          best: _parseOption(s['best_option']),
          alternatives: (s['alternatives'] as List? ?? []).map((a) => _parseOption(a)).toList(),
        );
      }).toList();

      setState(() {
        _isLoading = false;
      });

    } catch (e) {
      print('Plan error: $e');
      setState(() {
        _plan = 'Ошибка при генерации интерактивного плана. Попробуйте еще раз.\n$e';
        _isLoading = false;
      });
    }
  }

  Future<void> _book(BuildContext context, _RecoverySlot rs) async {
    // Need themes for booking. We'll pick the first one available or show a picker.
    // For simplicity in "one-click", we'll try to find a theme or show a quick dialog.
    final themes = await ref.read(apiServiceProvider).getConsultationThemes();
    if (themes.isEmpty) return;

    if (!mounted) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Подтверждение записи', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Преподаватель: ${rs.slot.teacherName}', style: const TextStyle(color: Colors.white, fontSize: 16)),
            const SizedBox(height: 4),
            Text('Рейтинг: ${rs.teacherRating}/5.0', style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text('Дата: ${rs.time}', style: const TextStyle(color: AppTheme.textSecondary)),
            Text('Предмет: ${rs.disciplineName}', style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Записаться'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await ref.read(apiServiceProvider).bookConsultation(
        rs.slot, 
        rs.disciplineId, 
        rs.disciplineName, 
        themes.first.id
      );
      
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(success ? 'Вы успешно записаны!' : 'Ошибка при записи'),
        backgroundColor: success ? AppTheme.success : AppTheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
        title: const Text('Индивидуальный план спасения',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(color: AppTheme.accent),
                  const SizedBox(height: 16),
                  Text(_status, style: const TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : _subjects.isEmpty && _plan.isNotEmpty 
            ? Center(child: Padding(padding: const EdgeInsets.all(20), child: SelectableText(_plan, style: const TextStyle(color: Colors.white))))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_strategy.isNotEmpty)
                    _StrategyCard(text: _strategy),
                  const SizedBox(height: 16),
                  ..._subjects.map((s) => _SubjectCard(subject: s, onBook: (rs) => _book(context, rs))),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _generatePlan,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Пересобрать план'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.bgCard,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: AppTheme.divider),
                    ),
                  ),
                ],
              ),
    );
  }
}

class _RecoverySubject {
  final String name;
  final String description;
  final _RecoveryOption best;
  final List<_RecoveryOption> alternatives;

  _RecoverySubject({
    required this.name,
    required this.description,
    required this.best,
    required this.alternatives,
  });
}

class _RecoveryOption {
  final String teacherName;
  final String why;
  final String rating;
  final List<_RecoverySlot> slots;

  _RecoveryOption({
    required this.teacherName,
    required this.why,
    required this.rating,
    required this.slots,
  });
}

class _RecoverySlot {
  final String time;
  final String auditory;
  final ConsultationSlot slot;
  final String disciplineId;
  final String disciplineName;
  final String teacherRating;

  _RecoverySlot({
    required this.time,
    required this.auditory,
    required this.slot,
    required this.disciplineId,
    required this.disciplineName,
    required this.teacherRating,
  });
}

class _StrategyCard extends ConsumerWidget {
  final String text;
  const _StrategyCard({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppTheme.accent.withOpacity(0.2), AppTheme.bgCard.withOpacity(0.5)]
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: AppTheme.accent.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.auto_awesome, color: AppTheme.accent, size: 18),
              ),
              const SizedBox(width: 10),
              const Text('СТРАТЕГИЯ СПАСЕНИЯ', style: TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, letterSpacing: 1.2, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),
          Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.5)),
        ],
      ),
    );
  }
}

class _SubjectCard extends ConsumerWidget {
  final _RecoverySubject subject;
  final Function(_RecoverySlot) onBook;

  const _SubjectCard({required this.subject, required this.onBook});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.divider),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        title: Text(subject.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        subtitle: Text('Топ-выбор: ${subject.best.teacherName} (${subject.best.rating})', style: const TextStyle(color: AppTheme.accent, fontSize: 13)),
        childrenPadding: const EdgeInsets.all(16),
        collapsedIconColor: Colors.white,
        iconColor: AppTheme.accent,
        children: [
          _infoRow(Icons.warning_amber_rounded, 'ПОЧЕМУ ДОЛГ', subject.description),
          const SizedBox(height: 20),
          
          // Best option section
          _OptionHeader(title: 'РЕКОМЕНДУЕМЫЙ ВАРИАНТ', color: AppTheme.success),
          const SizedBox(height: 12),
          _TeacherInfo(option: subject.best),
          ...subject.best.slots.map((rs) => _SlotItem(rs: rs, onBook: onBook)),
          
          if (subject.alternatives.isNotEmpty) ...[
            const SizedBox(height: 24),
            _OptionHeader(title: 'АЛЬТЕРНАТИВНЫЕ ВАРИАНТЫ', color: AppTheme.textSecondary),
            const SizedBox(height: 12),
            ...subject.alternatives.map((alt) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TeacherInfo(option: alt),
                ...alt.slots.map((rs) => _SlotItem(rs: rs, onBook: onBook)),
                const SizedBox(height: 12),
              ],
            )),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppTheme.textSecondary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label.toUpperCase(), style: const TextStyle(color: AppTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 4),
              Text(value, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionHeader extends ConsumerWidget {
  final String title;
  final Color color;
  const _OptionHeader({required this.title, required this.color});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Container(width: 4, height: 14, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5)),
      ],
    );
  }
}

class _TeacherInfo extends ConsumerWidget {
  final _RecoveryOption option;
  const _TeacherInfo({required this.option});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(option.teacherName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.1), 
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.accent.withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, color: AppTheme.accent, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Myprepod: ${option.rating}', 
                      style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold, fontSize: 11)
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(option.why, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12, fontStyle: FontStyle.italic)),
        ],
      ),
    );
  }
}

class _SlotItem extends ConsumerWidget {
  final _RecoverySlot rs;
  final Function(_RecoverySlot) onBook;
  const _SlotItem({required this.rs, required this.onBook});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.bgSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rs.time, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                Text('Ауд: ${rs.auditory.isEmpty ? "кафедра" : rs.auditory}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () => onBook(rs),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Записаться', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}

