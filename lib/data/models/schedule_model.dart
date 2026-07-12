// lib/data/models/schedule_model.dart

import 'package:flutter/material.dart';
import '../../core/utils/log.dart' as logger;

class ScheduleDay {
  final String title;
  final List<ScheduleLesson> data;

  const ScheduleDay({required this.title, required this.data});

  factory ScheduleDay.fromJson(dynamic raw) {
    if (raw is String) return ScheduleDay(title: raw, data: const []);
    if (raw is! Map) return ScheduleDay(title: '', data: const []);
    final j = raw is Map<String, dynamic> ? raw : Map<String, dynamic>.from(raw as Map);
    final title = (j['title'] ?? j['date'] ?? j['day'] ?? '').toString();
    dynamic rawLessons = j['data'] ?? j['lessons'] ?? j['items'] ?? j['schedule'] ?? [];
    if (rawLessons is! List) rawLessons = [];
    final lessons = (rawLessons as List)
        .where((e) => e is Map)
        .map((e) => ScheduleLesson.fromJson(
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map)))
        .toList();
    return ScheduleDay(title: title, data: lessons);
  }

  DateTime get date => DateTime.tryParse(title) ?? DateTime(2000);
}

class ScheduleLesson {
  final String id;
  final String day;
  final String start;
  final String end;
  final List<String> groups;
  final String teacher;
  final String teacherId;
  final String discipline;
  final String disciplineId;
  final String type;
  final String corps;
  final String? auditory;
  final int? subGroup;
  final String? homeworkId;
  final String? homeworkText;

  const ScheduleLesson({
    required this.id,
    required this.day,
    required this.start,
    required this.end,
    required this.groups,
    required this.teacher,
    required this.teacherId,
    required this.discipline,
    required this.disciplineId,
    required this.type,
    required this.corps,
    this.auditory,
    this.subGroup,
    this.homeworkId,
    this.homeworkText,
  });

  factory ScheduleLesson.fromJson(Map<String, dynamic> j) {
    final rawStart = (j['start'] ?? '').toString();
    final rawEnd   = (j['end'] ?? '').toString();
    // Debug: uncomment to see raw values from server
    // ignore: avoid_print
    logger.log('[LESSON TIME] raw start="$rawStart" → "${_extractTime(rawStart)}"   end="$rawEnd" → "${_extractTime(rawEnd)}"');

    return ScheduleLesson(
      id:           (j['id'] ?? '').toString(),
      day:          (j['day'] ?? '').toString(),
      start:        rawStart,
      end:          rawEnd,
      groups:       _parseStringList(j['groups']),
      teacher:      (j['teacher'] ?? '').toString(),
      teacherId:    (j['teacherID'] ?? j['teacherId'] ?? '').toString(),
      discipline:   (j['discipline'] ?? '').toString(),
      disciplineId: (j['disciplineID'] ?? j['disciplineId'] ?? '').toString(),
      type:         (j['type'] ?? '').toString(),
      corps:        (j['corps'] ?? j['building'] ?? '').toString(),
      auditory:     _nonEmpty(j['auditory'] ?? j['room']),
      subGroup:     j['subGroups'] is List
          ? ((j['subGroups'] as List).isNotEmpty
              ? int.tryParse((j['subGroups'] as List).first.toString())
              : null)
          : (j['subGroup'] as int?),
      homeworkId:   _nonEmpty(j['homework'] ?? j['homeworkId']),
      homeworkText: _nonEmpty(j['homeworkText'] ?? j['task']),
    );
  }

  static String? _nonEmpty(dynamic v) {
    final s = v?.toString() ?? '';
    return s.isEmpty ? null : s;
  }

  static List<String> _parseStringList(dynamic raw) {
    if (raw is List) return raw.map((e) => e.toString()).toList();
    if (raw is String && raw.isNotEmpty) return [raw];
    return [];
  }

  // ── Time extraction: handles all formats the server might use ─────────────
  String get startTime => _extractTime(start);
  String get endTime   => _extractTime(end);

  static String _extractTime(String s) {
    if (s.isEmpty) return '--:--';
    // ISO: "2026-04-20T09:00:00.000Z"
    if (s.contains('T')) {
      final tp = s.split('T').last.replaceAll('Z', '').split('+').first;
      return tp.length >= 5 ? tp.substring(0, 5) : tp;
    }
    // Russian datetime: "20.04.2026 09:00:00" or "20.04.2026 09:00"
    if (RegExp(r'\d{2}\.\d{2}\.\d{4}\s').hasMatch(s)) {
      final timePart = s.split(' ').last;
      return timePart.length >= 5 ? timePart.substring(0, 5) : timePart;
    }
    // Pure time string: "09:00:00" or "09:00"
    if (RegExp(r'^\d{2}:\d{2}').hasMatch(s)) {
      return s.substring(0, 5);
    }
    // Date only "2026-04-20" — no time info, return empty
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) return '--:--';
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  DateTime? get lessonDate {
    try {
      if (start.contains('T')) return DateTime.parse(start).toLocal();
      if (start.contains(' ') && start.contains('.')) {
        final p = start.split(' ').first.split('.');
        if (p.length == 3) {
          return DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0]));
        }
      }
      if (day.isNotEmpty) return DateTime.tryParse(day);
    } catch (_) {}
    return null;
  }

  bool get hasServerHomework =>
      (homeworkText?.isNotEmpty == true) || (homeworkId?.isNotEmpty == true);

  Color get typeColor {
    final t = type.toLowerCase();
    if (t.contains('лекц'))                                     return const Color(0xFF6B3FA0);
    if (t.contains('практ') || t.contains('лаб'))               return const Color(0xFF2D7A4F);
    if (t.contains('семин'))                                     return const Color(0xFF1A5276);
    if (t.contains('курсов') || t.contains('проектир'))         return const Color(0xFF1A4A5C);
    if (t.contains('экзам'))                                     return const Color(0xFF8B2500);
    if (t.contains('зачёт') || t.contains('зачет'))             return const Color(0xFF5C3D00);
    if (t.contains('аттест'))                                    return const Color(0xFF8B2500);
    return const Color(0xFF4A3060);
  }

  /// Friendly type label shown in UI
  String get typeLabel {
    final t = type.toLowerCase();
    if (t.contains('лекц'))                          return 'Лекция';
    if (t.contains('практ'))                         return 'Практика';
    if (t.contains('лаб'))                           return 'Лабораторная';
    if (t.contains('семин'))                         return 'Семинар';
    if (t.contains('курсов') || t.contains('проектир')) return 'Курсовое проект.';
    if (t.contains('экзам'))                         return 'Экзамен';
    if (t.contains('зачёт') || t.contains('зачет')) return 'Зачёт';
    if (t.contains('аттест'))                        return 'Аттестация';
    if (type.isNotEmpty)                             return type;
    return 'Занятие';
  }

  bool get isLecture     => type.toLowerCase().contains('лекц');
  bool get isPractice    => type.toLowerCase().contains('практ') || type.toLowerCase().contains('лаб');
  bool get isSeminar     => type.toLowerCase().contains('семин');
  bool get isCourseWork  => type.toLowerCase().contains('курсов') || type.toLowerCase().contains('проектир');
  bool get isExam        => type.toLowerCase().contains('экзам');
  bool get isCredit      => type.toLowerCase().contains('зачёт') || type.toLowerCase().contains('зачет');
  bool get isAttestation => isExam || isCredit || type.toLowerCase().contains('аттест');

  /// Duration hint shown in schedule card for attestation types
  String? get attestationDuration {
    if (isExam)   return '3 часа';
    if (isCredit) return '1.5 часа';
    return null;
  }
}

extension ListFirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
