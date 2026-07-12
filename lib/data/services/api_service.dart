import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/data/services/api_service.dart
//
// Key fixes (confirmed from HAR lk.msal.ru):
//  1. Progress list   → GET /progress?course=X&semester=Y
//  2. Lesson details  → GET /progress/details?disciplineID=UUID&course=X&semester=Y
//     (was incorrectly called /progress/getProgressDetails — 404)
//  3. Date format     → "dd.MM.yyyy" handled in grade_model.dart via intl

import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../models/schedule_model.dart';
import '../models/grade_model.dart';
import '../models/user_model.dart';
import '../models/consultation_model.dart';
import '../../core/constants/api_constants.dart';
import 'auth_service.dart';
import 'local_db_service.dart';
import '../../core/utils/log.dart' as logger;

class ApiService {
  final Ref ref;
  ApiService(this.ref);

  Dio get _dio => ref.read(authServiceProvider).dio;
  static final _isoFmt = DateFormat('yyyy-MM-dd');

  // ── Schedule ──────────────────────────────────────────────────────────────

  Future<List<ScheduleDay>> getScheduleWeek(DateTime monday) async {
    final sunday = monday.add(const Duration(days: 6));
    final from = _isoFmt.format(monday);
    final to   = _isoFmt.format(sunday);
    final cacheKey = 'schedule_${from}_$to';

    // No cache — always fetch live from server
    final resp = await _dio.get(
      ApiConstants.schedule,
      queryParameters: {'from': from, 'to': to},
    );

    // Fetch consultations
    List<ConsultationSlot> myConsultations = [];
    if (ref.read(authServiceProvider).currentUser?.isInstitute == true) {
      try {
        myConsultations = await getMyConsultations(monday, sunday);
      } catch (_) {}
    }

    if (resp.statusCode != 200 && resp.statusCode != 304) {
      throw Exception('/schedule → HTTP ${resp.statusCode}: ${resp.data}');
    }

    final list = _asList(resp.data);

    // Save raw schedule response to cache for instant loading next time
    try {
      await ref.read(localDbServiceProvider).setCache('schedule_cache', cacheKey, jsonEncode(resp.data));
    } catch (_) {}

    final scheduleDays = list
        .where((e) => e is Map)
        .map((e) => ScheduleDay.fromJson(_toStringMap(e)))
        .toList();

    // Merge consultations into schedule
    if (myConsultations.isNotEmpty) {
      for (final slot in myConsultations) {
        String dateStr = '';
        if (slot.start.length >= 10) {
          dateStr = slot.start.substring(0, 10); // YYYY-MM-DD
        } else if (slot.day.length >= 10) {
          dateStr = slot.day.substring(0, 10);
        } else {
          dateStr = slot.day;
        }

        try {
          final parsed = DateTime.tryParse(dateStr);
          if (parsed != null) dateStr = _isoFmt.format(parsed);
        } catch (_) {}

        if (dateStr.isEmpty) continue; // Skip if no date found

        final lesson = ScheduleLesson(
          id: 'consultation_${slot.start}',
          day: dateStr,
          start: slot.startConsultation.isNotEmpty ? slot.startConsultation : slot.start,
          end: slot.endConsultation.isNotEmpty ? slot.endConsultation : slot.start,
          groups: [],
          teacher: slot.teacherName,
          teacherId: slot.teacherId,
          discipline: slot.disciplineName,
          disciplineId: slot.disciplineId,
          type: 'Консультация',
          corps: slot.corps,
          auditory: slot.auditory,
          homeworkText: slot.themeName != null ? 'Тема: ${slot.themeName}' : null,
        );

        // Find matching day by date
        int dayIdx = scheduleDays.indexWhere((d) {
          if (dateStr.isEmpty) return false;
          final dStr = _isoFmt.format(d.date);
          return dStr == dateStr;
        });

        if (dayIdx >= 0) {
          final updatedData = List<ScheduleLesson>.from(scheduleDays[dayIdx].data)..add(lesson);
          // Sort by start time
          updatedData.sort((a, b) => a.startTime.compareTo(b.startTime));
          scheduleDays[dayIdx] = ScheduleDay(title: scheduleDays[dayIdx].title, data: updatedData);
        } else if (dateStr.isNotEmpty) {
          // Add new day if missing
          scheduleDays.add(ScheduleDay(title: dateStr, data: [lesson]));
        }
      }
      
      // Sort days
      scheduleDays.sort((a, b) => a.date.compareTo(b.date));
    }

    return scheduleDays;
  }

  Future<List<ScheduleDay>> getCurrentWeek() =>
      getScheduleWeek(_monday(DateTime.now()));

  Future<List<ScheduleDay>> getToday() async {
    final days = await getCurrentWeek();
    final today = DateTime.now();
    return days.where((d) => _sameDay(d.date, today)).toList();
  }

  /// Stale-while-revalidate: yields cached schedule instantly, then ALWAYS fetches fresh.
  /// Ensures the user sees data immediately while the slow server responds.
  Stream<List<ScheduleDay>> getScheduleWeekStream(DateTime monday) async* {
    bool hasCachedData = false;

    // Phase 1: Try to yield cached data instantly
    try {
      final sunday = monday.add(const Duration(days: 6));
      final from = _isoFmt.format(monday);
      final to = _isoFmt.format(sunday);
      final cacheKey = 'schedule_${from}_$to';
      // Use a very long maxAge — we don't expire cache, we always refetch
      final cachedJson = await ref.read(localDbServiceProvider).getCache(
          'schedule_cache', cacheKey, maxAge: const Duration(days: 365));
      if (cachedJson != null) {
        final list = _asList(jsonDecode(cachedJson));
        final cached = list
            .where((e) => e is Map)
            .map((e) => ScheduleDay.fromJson(_toStringMap(e)))
            .toList();
        if (cached.isNotEmpty) {
          hasCachedData = true;
          yield cached;
        }
      }
    } catch (e) {
      logger.log('[SCHEDULE] Cache read error: $e');
    }

    // Phase 2: ALWAYS fetch fresh from server (regardless of cache)
    try {
      final fresh = await getScheduleWeek(monday);
      yield fresh;
    } catch (e) {
      if (!hasCachedData) rethrow;
      // Server failed but we have cached data — silently keep showing it
      logger.log('[SCHEDULE] Server fetch failed, using cached data: $e');
    }
  }


  // ── Progress list ─────────────────────────────────────────────────────────
  // GET /progress?course=2&semester=4
  // Returns array of discipline summaries WITH disciplineID but WITHOUT lesson data.

  Future<List<ProgressItem>> getProgress({bool forceRefresh = false}) async {
    // No local cache — always fetch live
    const cacheKey = 'progress_list'; // kept for compatibility

    final user = ref.read(authServiceProvider).currentUser;
    final params = <String, dynamic>{};
    if (user?.course    != null) params['course']   = user!.course;
    if (user?.semester  != null) params['semester'] = user!.semester;

    // Confirmed working endpoint from HAR
    final resp = await _dio.get('/progress', queryParameters: params.isEmpty ? null : params);
    logger.log('[PROGRESS LIST] ${resp.statusCode} /progress params=$params');

    if (resp.statusCode != 200 && resp.statusCode != 304) {
      throw Exception('/progress → HTTP ${resp.statusCode}');
    }

    final list = _asList(resp.data);
    logger.log('[PROGRESS LIST] Got ${list.length} items from server');

    final isInstitute = user?.isInstitute ?? true;
    
    if (isInstitute) {
      final items = <ProgressItem>[];
      final targetCourse = user?.course.toString();
      final targetSem = user?.semester.toString();

      for (final sem in list) {
        if (sem is! Map) continue;
        final courseStr = sem['coures']?.toString() ?? '1';
        final semStr = sem['semester']?.toString() ?? '1';
        
        // Match college behavior: return only current semester
        if (targetCourse != null && targetSem != null) {
          if (courseStr != targetCourse || semStr != targetSem) continue;
        }

        final disciplines = _asList(sem['disciplines']);
        for (final d in disciplines) {
          if (d is Map) {
            items.add(ProgressItem.fromUniversityJson(
              _toStringMap(d),
              course: courseStr,
              semester: semStr,
            ));
          }
        }
      }
      logger.log('[PROGRESS LIST] Parsed ${items.length} university disciplines');
      return items;
    } else {
      final items = list
          .where((e) => e is Map)
          .map((e) => ProgressItem.fromJson(_toStringMap(e)))
          .toList();
      logger.log('[PROGRESS LIST] Parsed ${items.length} college disciplines');
      return items;
    }
  }

  // ── Progress WITH per-lesson detail ──────────────────────────────────────
  // Calls /progress to get the list, then /progress/details for each discipline.
  // Lesson data enables: correct hasDebt, monthly attendance, grade history.

  Future<List<ProgressItem>> getProgressWithLessons({bool forceRefresh = false}) async {
    // Live mode — no cache

    final items = await getProgress(forceRefresh: forceRefresh);

    // Fetch lesson details for all disciplines in parallel
    final enriched = await Future.wait(
      items.map((item) => _fetchLessons(item)),
    );

    return enriched;
  }

  /// GET /progress/details?disciplineID=UUID&course=X&semester=Y
  /// Confirmed from HAR: returns array of lesson objects with
  /// {date, teacher, turnout, lateness, subgroup, ratings}
  Future<ProgressItem> _fetchLessons(ProgressItem item) async {
    if (item.disciplineId.isEmpty) {
      logger.log('[LESSONS] Skipping "${item.discipline}" — no disciplineID');
      return item;
    }

    final user = ref.read(authServiceProvider).currentUser;
    final params = <String, dynamic>{
      'disciplineID': item.disciplineId,
    };
    if (user?.course   != null) params['course']   = user!.course;
    if (user?.semester != null) params['semester'] = user!.semester;

    try {
      final resp = await _dio.get('/progress/details', queryParameters: params);
      logger.log('[LESSONS] ${resp.statusCode} /progress/details disciplineID=${item.disciplineId} "${item.discipline}"');

      if (resp.statusCode != 200 && resp.statusCode != 304) {
        logger.log('[LESSONS] Non-200 for "${item.discipline}", skipping');
        return item;
      }

      final list = _asList(resp.data);
      if (list.isEmpty) {
        logger.log('[LESSONS] Empty response for "${item.discipline}"');
        return item;
      }

      final isInstitute = user?.isInstitute ?? true;
      List<LessonGrade> lessons = [];
      List<UniversityModule>? universityModules;
      bool access = item.access;
      String debtReport = item.debtReport;

      if (isInstitute) {
        for (final topLevel in list) {
          if (topLevel is! Map) continue;
          
          final topLevelDiscipline = topLevel['discipline']?.toString().trim().toLowerCase() ?? '';
          final currentDiscipline = item.discipline.trim().toLowerCase();
          
          if (topLevelDiscipline != currentDiscipline) continue;
          
          // In University JSON, access is in "accessTotal", and debt report in "info"
          if (topLevel.containsKey('accessTotal')) {
            final a = topLevel['accessTotal'];
            access = (a == 1 || a == true || a?.toString().toLowerCase() == 'true');
          }
          if (topLevel.containsKey('info')) {
            debtReport = topLevel['info'].toString();
          }

          final mods = _asList(topLevel['modules']);
          universityModules = mods
              .whereType<Map>()
              .map((m) => UniversityModule.fromJson(_toStringMap(m)))
              .toList();

          for (final m in universityModules!) {
            for (final t in m.themes) {
              lessons.addAll(t.items);
            }
          }
          
          // Found our match, no need to process the rest of the array
          break;
        }
      } else {
        lessons = list
            .where((e) => e is Map)
            .map((e) => LessonGrade.fromJson(_toStringMap(e)))
            .toList();
      }

      logger.log('[LESSONS] "${item.discipline}" → ${lessons.length} lessons, '
            '${lessons.where((l) => !l.turnout).length} absences, '
            '${lessons.where((l) => l.hasDebt).length} with grade=2');

      // Recompute totals from actual lesson data
      final missed = lessons.where((l) => !l.turnout).length;

      return ProgressItem(
        discipline:   item.discipline,
        disciplineId: item.disciplineId,
        course:       item.course,
        semester:     item.semester,
        access:       access,
        countTotal:   lessons.length,
        missedTotal:  missed,
        debtReport:   debtReport,
        lessons:      lessons,
        universityModules: universityModules,
        personalNote: item.personalNote,
      );
    } catch (e) {
      logger.log('[LESSONS] Error fetching "${item.discipline}": $e');
      return item;
    }
  }

  // ── Record book ───────────────────────────────────────────────────────────

  Future<List<RecordEntry>> getRecordbook() async {
    final resp = await _dio.get(ApiConstants.recordbook);
    _assertOk(resp, ApiConstants.recordbook);
    return _asList(resp.data)
        .where((e) => e is Map)
        .map((e) => RecordEntry.fromJson(_toStringMap(e)))
        .toList();
  }

  // ── Group ─────────────────────────────────────────────────────────────────

  Future<List<UserModel>> getGroupmates() async {
    final resp = await _dio.get(ApiConstants.studentGroup);
    _assertOk(resp, ApiConstants.studentGroup);
    return _asList(resp.data)
        .where((e) => e is Map)
        .map((e) => UserModel.fromJson(_toStringMap(e)))
        .toList();
  }

  // ── Passes ────────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>> getStudentPasses() async {
    final resp = await _dio.get(ApiConstants.studentPasses);
    _assertOk(resp, ApiConstants.studentPasses);
    
    final user = ref.read(authServiceProvider).currentUser;
    if (user != null && user.isInstitute) {
      // In University LK, /student/passes returns "пропуски занятий" (absences),
      // whereas College returns "Электронный пропуск" (RFID card).
      // Since absences are shown in the Grades screen, hide the pass card in profile.
      return {};
    }
    
    return _asMap(resp.data);
  }

  // ── Info ──────────────────────────────────────────────────────────────────

  /// Only used by University. Returns { "reting": 764.4, "passes": 8, "InstituteUrl": "..." }
  Future<Map<String, dynamic>> getStudentInfo() async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user != null && user.isCollege) return {};
    
    try {
      final resp = await _dio.get('/student/info');
      if (resp.statusCode == 200 && resp.data is Map) {
        return _asMap(resp.data);
      }
    } catch (_) {}
    return {};
  }

  // ── Homework ──────────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getHomework(
      String lessonId, String discipline, String date) async {
    try {
      final resp = await _dio.get('/homework/$lessonId');
      if (resp.statusCode == 200 && resp.data is Map) {
        return resp.data as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  // ── Privacy ───────────────────────────────────────────────────────────────

  Future<void> updatePrivacySettings({
    required bool showEmail,
    required bool showPhoto,
    required bool showMobile,
  }) async {
    try {
      await _dio.put('/student/access', data: {
        'email': showEmail, 'photo': showPhoto, 'mobile': showMobile,
      });
    } catch (_) {}
  }

  // ── News ──────────────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getNews() async {
    try {
      final resp = await _dio.get(ApiConstants.newsPreview);
      if (resp.statusCode == 200 || resp.statusCode == 304) {
        return _asList(resp.data).whereType<Map<String, dynamic>>().toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> ping() async {
    try {
      final r = await _dio.get(ApiConstants.auth).timeout(const Duration(seconds: 5));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── Consultations ─────────────────────────────────────────────────────────

  Future<List<ConsultationTeacher>> getConsultationTeachers(String disciplineId) async {
    try {
      final resp = await _dio.get('/disciplines/$disciplineId/teachers');
      if (resp.statusCode == 200) {
        return _asList(resp.data)
            .map((e) => _toStringMap(e))
            .map((e) => ConsultationTeacher.fromJson(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<ConsultationSlot>> getConsultationSlots(String disciplineId, String teacherId, DateTime from, DateTime to) async {
    try {
      final resp = await _dio.get(
        '/consultation',
        queryParameters: {
          'discipline': disciplineId,
          'teacher': teacherId,
          'from': _isoFmt.format(from),
          'to': _isoFmt.format(to),
        },
      );
      if (resp.statusCode == 200) {
        return _asList(resp.data)
            .map((e) => _toStringMap(e))
            .map((e) => ConsultationSlot(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<List<ConsultationTheme>> getConsultationThemes() async {
    try {
      final resp = await _dio.get('/consultation/theme');
      if (resp.statusCode == 200) {
        return _asList(resp.data)
            .map((e) => _toStringMap(e))
            .map((e) => ConsultationTheme.fromJson(e))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  Future<bool> bookConsultation(ConsultationSlot slot, String disciplineId, String disciplineName, String themeId, {bool isRemote = false}) async {
    try {
      final payload = Map<String, dynamic>.from(slot.raw);
      payload['discipline'] = {
        'id': disciplineId,
        'name': disciplineName,
      };
      payload['typeConsultation'] = {
        'remote': isRemote,
        'offline': !isRemote,
      };
      payload['theme'] = themeId;
      payload['record'] = false;
      payload['duration'] = 10;
      
      final resp = await _dio.post('/consultation', data: payload);
      if (resp.statusCode == 200 || resp.statusCode == 201) {
        return true;
      }
    } catch (e) {
      logger.log('[CONSULTATION] Error booking: $e');
    }
    return false;
  }
  
  Future<bool> cancelConsultation(String teacherId, String startConsultation) async {
    try {
      final payload = {
        'teacher': teacherId,
        'startConsultation': startConsultation,
      };
      final resp = await _dio.patch('/consultation', data: payload);
      if (resp.statusCode == 200) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<List<ConsultationSlot>> getMyConsultations(DateTime from, DateTime to) async {
    List<ConsultationSlot> allBookings = [];
    try {
      final progress = await getProgress();
      final disciplineIds = progress.map((p) => p.disciplineId).where((id) => id.isNotEmpty).toSet().toList();
      
      final teacherFutures = disciplineIds.map((dId) async {
        final teachers = await getConsultationTeachers(dId);
        return {'disciplineId': dId, 'teachers': teachers};
      });
      
      final teachersResults = await Future.wait(teacherFutures);
      
      for (final res in teachersResults) {
        final dId = res['disciplineId'] as String;
        final teachers = res['teachers'] as List<ConsultationTeacher>;
        for (final t in teachers) {
          try {
            final resp = await _dio.get(
              '/consultation',
              queryParameters: {
                'discipline': dId,
                'teacher': t.id,
                'from': _isoFmt.format(from),
                'to': _isoFmt.format(to),
              },
            );
            if (resp.statusCode == 200) {
              final slots = _asList(resp.data)
                  .map((e) => _toStringMap(e))
                  .map((e) => ConsultationSlot(e))
                  .where((s) => s.isRecord)
                  .toList();
              
              // Ensure disciplineName is set
              for (final s in slots) {
                if (s.raw['discipline'] == null) {
                  final dName = progress.firstWhere((p) => p.disciplineId == dId, orElse: () => progress.first).discipline;
                  s.raw['discipline'] = {'id': dId, 'name': dName};
                }
              }
              
              allBookings.addAll(slots);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    return allBookings;
  }

  // ── Serialization for caching ─────────────────────────────────────────────

  Map<String, dynamic> _progressToJson(ProgressItem p) => {
    'discipline':   p.discipline,
    'disciplineID': p.disciplineId,
    'course':       p.course,
    'semester':     p.semester,
    'access':       p.access,
    'countGrape':   p.countTotal,
    'flawGrape':    p.missedTotal,
    'debtReport':   p.debtReport,
    'lessons': p.lessons.map((l) => {
      'date':     l.date,
      'teacher':  l.teacher,
      'turnout':  l.turnout,
      'lateness': l.lateness,
      'subgroup': l.subgroup,
      'ratings':  l.grades, // already filtered, no zeros
    }).toList(),
  };

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _assertOk(Response resp, String ep) {
    if (resp.statusCode != 200 && resp.statusCode != 304) {
      throw Exception('$ep → HTTP ${resp.statusCode}\n${resp.data}');
    }
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      for (final k in ['data', 'items', 'list', 'result', 'records', 'schedule', 'days']) {
        if (data.containsKey(k) && data[k] is List) return data[k] as List;
      }
      return [data];
    }
    if (data is String) {
      try { return _asList(jsonDecode(data)); } catch (_) {}
    }
    return [];
  }

  Map<String, dynamic> _toStringMap(dynamic e) =>
      e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map);

  Map<String, dynamic> _asMap(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }

  static DateTime _monday(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
