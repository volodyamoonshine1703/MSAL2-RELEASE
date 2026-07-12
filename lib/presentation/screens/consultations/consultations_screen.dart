import '../../../core/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/grade_model.dart';
import '../../../data/models/consultation_model.dart';
import '../../../data/services/api_service.dart';
import '../grades/grades_screen.dart' show gradesProvider;
import '../ai/ai_screen.dart' show activeChatProvider;
import '../shell/main_shell.dart' show shellIndexProvider;
import '../../../data/services/myprepod_service.dart';
import '../../../data/services/auth_service.dart';
import '../plan/recovery_plan_screen.dart';

class ConsultationsScreen extends ConsumerStatefulWidget {
  const ConsultationsScreen({super.key});

  @override
  ConsumerState<ConsultationsScreen> createState() => _ConsultationsScreenState();
}

class _ConsultationsScreenState extends ConsumerState<ConsultationsScreen> {
  ProgressItem? _selectedDiscipline;
  ConsultationTeacher? _selectedTeacher;
  ConsultationTheme? _selectedTheme;
  
  List<ConsultationTeacher> _teachers = [];
  List<ConsultationTheme> _themes = [];
  List<ConsultationSlot> _slots = [];
  List<ConsultationSlot> _myBookings = [];
  
  bool _loadingTeachers = false;
  bool _loadingSlots = false;
  bool _loadingBookings = false;
  String _slotsStatus = '';
  
  bool _isRemote = false;

  @override
  void initState() {
    super.initState();
    _loadThemes();
    _loadMyBookings();
  }

  Future<void> _loadMyBookings() async {
    setState(() => _loadingBookings = true);
    final now = DateTime.now();
    final to = now.add(const Duration(days: 90));
    try {
      final list = await ref.read(apiServiceProvider).getMyConsultations(now, to);
      if (mounted) setState(() => _myBookings = list);
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingBookings = false);
    }
  }

  Future<void> _loadThemes() async {
    try {
      final themes = await ref.read(apiServiceProvider).getConsultationThemes();
      if (mounted && themes.isNotEmpty) {
        setState(() {
          _themes = themes;
          _selectedTheme ??= themes.first;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadTeachers(String disciplineId) async {
    setState(() {
      _loadingTeachers = true;
      _teachers = [];
      _selectedTeacher = null;
      _slots = [];
    });
    try {
      final teachers = await ref.read(apiServiceProvider).getConsultationTeachers(disciplineId);
      if (mounted) {
        setState(() {
          _teachers = teachers;
          if (teachers.isNotEmpty) {
             _selectedTeacher = teachers.first;
             _loadSlots();
          }
          _loadingTeachers = false;
        });
        _fetchTeacherRatings(teachers);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingTeachers = false);
    }
  }

  Future<void> _fetchTeacherRatings(List<ConsultationTeacher> loadedTeachers) async {
    for (int i = 0; i < loadedTeachers.length; i++) {
      final data = await ref.read(myprepodServiceProvider).getTeacherRating(loadedTeachers[i].name);
      if (data != null && mounted) {
        setState(() {
          final idx = _teachers.indexWhere((t) => t.id == loadedTeachers[i].id);
          if (idx != -1) {
            _teachers[idx] = _teachers[idx].copyWith(
              rating: data.rating,
              reviews: data.reviews,
            );
            if (_selectedTeacher?.id == loadedTeachers[i].id) {
               _selectedTeacher = _teachers[idx];
            }
          }
        });
      }
    }
  }

  void _showReviews(ConsultationTeacher teacher) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text('Отзывы: ${teacher.name}', style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold))),
                const SizedBox(width: 8),
                if (teacher.rating != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('★ ${teacher.rating}', style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: teacher.reviews.isEmpty 
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Отзывов пока нет', style: TextStyle(color: AppTheme.textMuted))))
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: teacher.reviews.length,
                    separatorBuilder: (_, __) => const Divider(color: AppTheme.divider, height: 24),
                    itemBuilder: (context, index) => Text(teacher.reviews[index], style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13, height: 1.4)),
                  ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _loadSlots() async {
    if (_selectedDiscipline == null || _selectedTeacher == null) return;
    
    setState(() {
      _loadingSlots = true;
      _slotsStatus = 'Загрузка расписания...';
    });
    
    final now = DateTime.now();
    final to = now.add(const Duration(days: 90)); // Extended to 90 days to show all possible dates
    
    try {
      final slots = await ref.read(apiServiceProvider).getConsultationSlots(
        _selectedDiscipline!.disciplineId,
        _selectedTeacher!.id,
        now,
        to
      );
      
      if (mounted) {
        setState(() {
          _slots = slots;
          _loadingSlots = false;
          _slotsStatus = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingSlots = false;
          _slotsStatus = 'Ошибка загрузки';
        });
      }
    }
  }

  Future<void> _bookSlot(ConsultationSlot slot) async {
    // If no theme selected, try to auto-select or show picker
    if (_selectedTheme == null) {
      if (_themes.isEmpty) {
        // Try loading themes one more time
        await _loadThemes();
      }
      if (_themes.isNotEmpty && _selectedTheme == null) {
        setState(() => _selectedTheme = _themes.first);
      }
      if (_selectedTheme == null) {
        // Last resort: show a dialog to pick a theme
        final picked = await _showThemePicker();
        if (picked == null) return;
        setState(() => _selectedTheme = picked);
      }
    }

    // Confirmation dialog
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
            Text('📅 ${slot.day} • ${slot.between}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('📍 ${slot.corps}, ${slot.auditory}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 8),
            Text('👤 ${_selectedTeacher?.name ?? ""}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 8),
            Text('📝 Тема: ${_selectedTheme!.name}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
            const SizedBox(height: 8),
            Text('💻 Формат: ${_isRemote ? "Дистант" : "Очная"}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена', style: TextStyle(color: AppTheme.textSecondary))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
            child: const Text('Записаться', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    
    setState(() => _loadingSlots = true);
    final success = await ref.read(apiServiceProvider).bookConsultation(
      slot, 
      _selectedDiscipline!.disciplineId, 
      _selectedDiscipline!.discipline, 
      _selectedTheme!.id,
      isRemote: _isRemote,
    );
    
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('✅ Вы успешно записаны!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          backgroundColor: AppTheme.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        _loadSlots();
        _loadMyBookings();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('❌ Ошибка при записи. Попробуйте ещё раз.', style: TextStyle(color: Colors.white)),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ));
        setState(() => _loadingSlots = false);
      }
    }
  }

  Future<ConsultationTheme?> _showThemePicker() async {
    if (_themes.isEmpty) return null;
    return showModalBottomSheet<ConsultationTheme>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Выберите тему консультации', style: TextStyle(color: AppTheme.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...(_themes.map((t) => ListTile(
              title: Text(t.name, style: const TextStyle(color: AppTheme.textPrimary)),
              leading: const Icon(Icons.topic, color: AppTheme.accent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              onTap: () => Navigator.pop(ctx, t),
            ))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final progressAsync = ref.watch(gradesProvider);
    
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Запись на консультацию'),
        backgroundColor: AppTheme.bgDark,
        elevation: 0,
      ),
      floatingActionButton: ref.read(authServiceProvider).currentUser?.isInstitute == true
          ? FloatingActionButton.extended(
              backgroundColor: AppTheme.accent,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              label: const Text('План по долгам', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.push(context, MaterialPageRoute(builder: (_) => const RecoveryPlanScreen()));
              },
            )
          : null,
      body: progressAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (err, _) => Center(child: Text('Ошибка: $err')),
        data: (items) {
          final validItems = items.where((i) => i.disciplineId.isNotEmpty).toList();
          
          if (validItems.isEmpty) {
            return const Center(child: Text('Дисциплины не найдены', style: TextStyle(color: AppTheme.textMuted)));
          }
          
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppTheme.bgCard,
                  border: Border(bottom: BorderSide(color: AppTheme.divider)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Дисциплина', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.bgSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<ProgressItem>(
                          isExpanded: true,
                          dropdownColor: AppTheme.bgCard,
                          hint: const Text('Выберите дисциплину', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                          value: _selectedDiscipline,
                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                          items: validItems.map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(d.discipline, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (val) {
                            if (val != null && val != _selectedDiscipline) {
                              setState(() => _selectedDiscipline = val);
                              _loadTeachers(val.disciplineId);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Преподаватель', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                decoration: BoxDecoration(
                                  color: AppTheme.bgSurface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppTheme.divider),
                                ),
                                child: _loadingTeachers 
                                    ? const SizedBox(height: 48, child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))))
                                    : DropdownButtonHideUnderline(
                                        child: DropdownButton<ConsultationTeacher>(
                                          isExpanded: true,
                                          dropdownColor: AppTheme.bgCard,
                                          hint: const Text('Выберите преподавателя', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
                                          value: _selectedTeacher,
                                          icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textMuted),
                                          items: _teachers.map((t) => DropdownMenuItem(
                                            value: t,
                                            child: Row(
                                              children: [
                                                Expanded(
                                                  child: Text(t.name, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                                                ),
                                                if (t.rating != null) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                    decoration: BoxDecoration(
                                                      color: (double.tryParse(t.rating!.replaceAll(',', '.')) ?? 0) >= 4.0 ? AppTheme.success.withOpacity(0.2) : 
                                                             (double.tryParse(t.rating!.replaceAll(',', '.')) ?? 0) >= 3.0 ? AppTheme.warning.withOpacity(0.2) : 
                                                             AppTheme.error.withOpacity(0.2),
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Row(
                                                       mainAxisSize: MainAxisSize.min,
                                                       children: [
                                                          Icon(Icons.star, size: 12, color: (double.tryParse(t.rating!.replaceAll(',', '.')) ?? 0) >= 4.0 ? AppTheme.success : 
                                                                                 (double.tryParse(t.rating!.replaceAll(',', '.')) ?? 0) >= 3.0 ? AppTheme.warning : 
                                                                                 AppTheme.error),
                                                          const SizedBox(width: 2),
                                                          Text(t.rating!, style: TextStyle(
                                                            fontSize: 12, 
                                                            fontWeight: FontWeight.bold,
                                                            color: (double.tryParse(t.rating!.replaceAll(',', '.')) ?? 0) >= 4.0 ? AppTheme.success : 
                                                                   (double.tryParse(t.rating!.replaceAll(',', '.')) ?? 0) >= 3.0 ? AppTheme.warning : 
                                                                   AppTheme.error,
                                                          )),
                                                       ],
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          )).toList(),
                                          onChanged: (val) {
                                            if (val != null) {
                                              setState(() => _selectedTeacher = val);
                                              _loadSlots();
                                            }
                                          },
                                        ),
                                      ),
                              ),
                              if (_selectedTeacher?.reviews.isNotEmpty ?? false) ...[
                                const SizedBox(height: 6),
                                InkWell(
                                  onTap: () => _showReviews(_selectedTeacher!),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.comment_outlined, size: 12, color: AppTheme.accent),
                                      const SizedBox(width: 4),
                                      Text('Посмотреть отзывы (${_selectedTeacher!.reviews.length})', 
                                        style: const TextStyle(color: AppTheme.accent, fontSize: 11, fontWeight: FontWeight.w600, decoration: TextDecoration.underline)),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (_themes.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 1,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Тема', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
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
                                      hint: const Text('Тема', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
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
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    Row(
                      children: [
                         const Text('Формат:', style: TextStyle(color: AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                         const SizedBox(width: 16),
                         Expanded(
                           child: Container(
                             height: 36,
                             decoration: BoxDecoration(
                               color: AppTheme.bgSurface,
                               borderRadius: BorderRadius.circular(8),
                               border: Border.all(color: AppTheme.divider),
                             ),
                             child: Row(
                               children: [
                                 Expanded(
                                   child: GestureDetector(
                                     onTap: () => setState(() => _isRemote = false),
                                     child: Container(
                                       decoration: BoxDecoration(
                                         color: !_isRemote ? AppTheme.accent : Colors.transparent,
                                         borderRadius: BorderRadius.circular(7),
                                       ),
                                       alignment: Alignment.center,
                                       child: Text('Очная', style: TextStyle(color: !_isRemote ? Colors.white : AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                                     ),
                                   ),
                                 ),
                                 Expanded(
                                   child: GestureDetector(
                                     onTap: () => setState(() => _isRemote = true),
                                     child: Container(
                                       decoration: BoxDecoration(
                                         color: _isRemote ? AppTheme.accent : Colors.transparent,
                                         borderRadius: BorderRadius.circular(7),
                                       ),
                                       alignment: Alignment.center,
                                       child: Text('Дистант', style: TextStyle(color: _isRemote ? Colors.white : AppTheme.textSecondary, fontSize: 13, fontWeight: FontWeight.w600)),
                                     ),
                                   ),
                                 ),
                               ],
                             ),
                           ),
                         ),
                      ],
                    ),
                  ],
                ),
              ),
              
              Expanded(
                child: _buildSlotsView(),
              ),
            ],
          );
        },
      ),
    );
  }
  
  Widget _buildSlotsView() {
    if (_selectedDiscipline == null || _selectedTeacher == null) {
      return _buildMyBookings();
    }
    
    if (_loadingSlots) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: AppTheme.accent),
            const SizedBox(height: 16),
            Text(_slotsStatus, style: const TextStyle(color: AppTheme.textSecondary)),
          ],
        ),
      );
    }
    
    final visibleSlots = _slots.where((s) => s.isFree || s.isRecord).toList();
    
    if (visibleSlots.isEmpty) {
      return const Center(
        child: Text('Нет доступных или текущих записей', style: TextStyle(color: AppTheme.textMuted, fontSize: 15)),
      );
    }
    
    visibleSlots.sort((a, b) {
      if (a.isRecord && !b.isRecord) return -1;
      if (!a.isRecord && b.isRecord) return 1;
      return a.start.compareTo(b.start);
    });

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: visibleSlots.length,
      itemBuilder: (context, index) {
        final slot = visibleSlots[index];
        final isBooked = slot.isRecord;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: isBooked ? AppTheme.success.withOpacity(0.08) : AppTheme.bgCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: isBooked ? AppTheme.success.withOpacity(0.4) : AppTheme.divider),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_month, size: 16, color: isBooked ? AppTheme.success : AppTheme.accent),
                          const SizedBox(width: 6),
                          Text('${slot.day} • ${slot.between}', 
                              style: TextStyle(color: isBooked ? AppTheme.success : AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(child: Text('${slot.corps}, ${slot.auditory}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                        ],
                      ),
                      if (isBooked && slot.themeName != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 14, color: AppTheme.success),
                            const SizedBox(width: 4),
                            Expanded(child: Text('Тема: ${slot.themeName}', style: const TextStyle(color: AppTheme.success, fontSize: 12))),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                if (isBooked)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.success.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Вы записаны', style: TextStyle(color: AppTheme.success, fontWeight: FontWeight.w600, fontSize: 12)),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      elevation: 2,
                      shadowColor: AppTheme.accent.withOpacity(0.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                    ),
                    onPressed: () => _bookSlot(slot),
                    icon: const Icon(Icons.event_available, size: 18),
                    label: const Text('Записаться', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMyBookings() {
    if (_loadingBookings) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.accent));
    }
    if (_myBookings.isEmpty) {
      return const Center(
        child: Text('У вас пока нет записей на консультации.\nВыберите дисциплину и преподавателя для записи.', 
          style: TextStyle(color: AppTheme.textMuted, fontSize: 14), textAlign: TextAlign.center),
      );
    }
    
    _myBookings.sort((a, b) => a.start.compareTo(b.start));
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text('Мои предстоящие консультации', 
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600)),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _myBookings.length,
            itemBuilder: (context, index) {
              final slot = _myBookings[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppTheme.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.success.withOpacity(0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.calendar_month, size: 16, color: AppTheme.success),
                          const SizedBox(width: 6),
                          Text('${slot.day} • ${slot.between}', 
                              style: const TextStyle(color: AppTheme.success, fontSize: 15, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          const Icon(Icons.check_circle, size: 20, color: AppTheme.success),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(slot.disciplineName, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(slot.teacherName, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 14, color: AppTheme.textSecondary),
                          const SizedBox(width: 4),
                          Expanded(child: Text('${slot.corps}, ${slot.auditory}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                        ],
                      ),
                      if (slot.themeName != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 14, color: AppTheme.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(child: Text('Тема: ${slot.themeName}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13))),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
