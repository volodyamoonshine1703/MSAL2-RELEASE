import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/data/services/ai_service.dart
//
// NVIDIA NIM (OpenAI-compatible) API client.
// Model: meta/llama-3.1-70b-instruct (or any NIM model).
//
// Token budget: 8000 tokens max context.
// System prompt: ~500 tokens (always kept).
// Sliding window: drop oldest user/assistant pairs until fits.

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/utils/log.dart' as logger;
import '../models/chat_model.dart';
import '../models/schedule_model.dart';
import '../models/grade_model.dart';
import '../models/homework_model.dart';
import '../services/local_db_service.dart';
import '../services/auth_service.dart';

/// Actions the AI can request the app to perform
class AiAction {
  final String type; // 'set_deadline' | 'edit_note' | 'delete_note' | 'none'
  final Map<String, dynamic> params;
  const AiAction({required this.type, required this.params});
}

/// Result from one AI turn
class AiTurnResult {
  final String text;       // AI's reply text
  final AiAction? action;  // optional action to execute
  const AiTurnResult({required this.text, this.action});
}

class AiService {
  final Ref ref;
  AiService(this.ref);

  // ── NIM endpoint ─────────────────────────────────────────────────────────
  static const _baseUrl = 'https://integrate.api.nvidia.com/v1';
  static const _model   = 'meta/llama-3.1-70b-instruct';
  static const _prefKey = 'nim_api_key';

  static const _secureStorage = FlutterSecureStorage();
  String? _apiKey; // loaded from FlutterSecureStorage

  static const _maxContextTokens = 7500; // leave headroom
  static const _maxNewTokens     = 2000;

  Dio get _dio => Dio(BaseOptions(
    baseUrl: _baseUrl,
    headers: {
      'Authorization': 'Bearer ${_apiKey ?? ''}',
      'Content-Type': 'application/json',
    },
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 300),
  ));

  // ── Key management ────────────────────────────────────────────────────────

  Future<void> loadApiKey() async {
    _apiKey = await _secureStorage.read(key: _prefKey);
  }

  Future<void> saveApiKey(String key) async {
    _apiKey = key.trim();
    await _secureStorage.write(key: _prefKey, value: _apiKey!);
  }

  Future<void> clearApiKey() async {
    _apiKey = null;
    await _secureStorage.delete(key: _prefKey);
  }

  String? get apiKey => _apiKey;
  bool get hasApiKey => _apiKey != null && _apiKey!.isNotEmpty;

  /// Masked key for display: "nvapi-Ab...XyZ"
  String get maskedKey {
    if (_apiKey == null || _apiKey!.length < 10) return '—';
    return '${_apiKey!.substring(0, 8)}...${_apiKey!.substring(_apiKey!.length - 4)}';
  }

  // ── System prompt factory ─────────────────────────────────────────────────

  ChatMessage _buildSystemPrompt({
    List<HomeworkModel>? homework,
    List<ScheduleDay>? schedule,
    List<Map<String, dynamic>>? generalNotes,
    List<ProgressItem>? grades,
  }) {
    final user   = ref.read(authServiceProvider).currentUser;
    final name   = user?.name ?? 'студент';
    final group  = user?.group ?? '';
    final course = user?.course ?? '';

    // ── Date / time context ──────────────────────────────────────────────────
    final now      = DateTime.now();
    final weekdays = ['', 'понедельник', 'вторник', 'среда', 'четверг',
                      'пятница', 'суббота', 'воскресенье'];
    final dateStr  = '${now.day}.${now.month}.${now.year} (${weekdays[now.weekday]})';
    final tomorrow = DateTime(now.year, now.month, now.day + 1);

    // ── Tomorrow schedule block ───────────────────────────────────────────────
    String tomorrowBlock = '';
    if (schedule != null) {
      final tomorrowDays = schedule.where((d) {
        final dt = DateTime.tryParse(d.title) ?? d.date;
        return dt.year == tomorrow.year &&
               dt.month == tomorrow.month &&
               dt.day   == tomorrow.day;
      }).toList();
      if (tomorrowDays.isNotEmpty && tomorrowDays.first.data.isNotEmpty) {
        tomorrowBlock = '\n\nЗАВТРА (${tomorrow.day}.${tomorrow.month}):\n' +
            tomorrowDays.first.data
                .map((l) => '  ${l.startTime}–${l.endTime} ${l.discipline} (${l.typeLabel})')
                .join('\n');
      } else {
        tomorrowBlock = '\n\nЗАВТРА: занятий нет.';
      }
    }

    // ── Homework block ────────────────────────────────────────────────────────
    final hwBlock = homework == null || homework.isEmpty ? '' : '''

ТЕКУЩИЕ ДОМАШНИЕ ЗАДАНИЯ:
${homework.where((h) => !h.isEmpty).take(10).map((h) {
  final deadline = h.deadline != null
      ? 'дедлайн ${h.deadline!.day}.${h.deadline!.month}'
      : 'без дедлайна';
  return '• [${h.lessonId}] ${h.discipline}: ${h.effectiveText.substring(0, h.effectiveText.length.clamp(0, 80))} ($deadline)';
}).join('\n')}''';

    // ── Schedule block ────────────────────────────────────────────────────────
    final schedBlock = schedule == null || schedule.isEmpty ? '' : '''

РАСПИСАНИЕ НА НЕДЕЛЮ:
${schedule.where((d) => d.data.isNotEmpty).map((d) {
  final dt = DateTime.tryParse(d.title);
  final dayLabel = dt != null
      ? '${dt.day}.${dt.month} (${weekdays[dt.weekday]})'
      : d.title;
  return '$dayLabel: ${d.data.map((l) => '${l.startTime} ${l.discipline} (${l.typeLabel})').join(', ')}';
}).join('\n')}$tomorrowBlock''';

    // ── General Notes block ───────────────────────────────────────────────────
    final notesBlock = generalNotes == null || generalNotes.isEmpty ? '' : '''

ОБЩИЕ ЗАМЕТКИ СТУДЕНТА:
${generalNotes.take(10).map((n) {
  return '• [ID: ${n['id']}] ${n['title']}: ${n['content']}';
}).join('\n')}''';

    // ── Debts block ───────────────────────────────────────────────────────────
    final debtsBlock = grades == null ? '' : () {
      final List<String> issues = [];
      
      for (final g in grades) {
        bool hasIssue = false;
        String line = '• ${g.discipline}:';
        
        if (g.hasDebt) {
          line += ' Долги: ${g.debtCount}.';
          hasIssue = true;
        }
        
        final failingMods = g.failingModules;
        if (failingMods.isNotEmpty) {
          for (final m in failingMods) {
            line += ' Модуль "${m.module}" НЕТ ДОПУСКА (${m.admissionStatus}).';
          }
          hasIssue = true;
        }
        
        if (hasIssue) issues.add(line);
      }
      
      if (issues.isEmpty) return '\n\nПРОБЛЕМ С ДОПУСКОМ И ДОЛГОВ: нет.';
      return '\n\nПРОБЛЕМНЫЕ ПРЕДМЕТЫ СТУДЕНТА (НЕТ ДОПУСКА ИЛИ ЕСТЬ ДОЛГИ):\n' + issues.join('\n');
    }();

    return ChatMessage(
      role: MessageRole.system,
      timestamp: now,
      content: '''Ты — персональный ИИ-ассистент студента МГЮА.
Сегодня: $dateStr.
Студент: $name, группа: $group, курс: $course.

Ты умеешь:
1. Анализировать расписание и давать советы по тайм-менеджменту
2. Управлять домашними заданиями (менять дедлайны, редактировать заметки)
3. Создавать, просматривать и редактировать общие заметки
4. Напоминать о горящих дедлайнах и помогать расставлять приоритеты
5. Составлять план подготовки к экзаменам и зачётам
6. Сформировать индивидуальный план по закрытию задолженностей с помощью ИИ.
   ВНИМАНИЕ: Студенту НЕОБЯЗАТЕЛЬНО закрывать долг у своего преподавателя! Он может записаться на консультацию К ЛЮБОМУ ИЗ ДОСТУПНЫХ.
   Твоя главная задача при анализе преподавателей — искать "халяву"! Советуй максимально лайтовых, спокойных и добрых преподавателей, у которых будет легко закрыть долг или получить допуск по их предмету.

Когда студент просит изменить ДЗ/дедлайн, отвечай в JSON-блоке:
```action
{"type":"set_deadline","lessonId":"...","deadline":"YYYY-MM-DD"}
```
Для редактирования текста ДЗ:
```action
{"type":"edit_note","lessonId":"...","text":"новый текст"}
```
Для создания новой общей заметки:
```action
{"type":"create_general_note","title":"Заголовок","content":"Текст заметки"}
```
Для редактирования общей заметки:
```action
{"type":"edit_general_note","id":ID,"content":"Новый текст"}
```
После JSON-блока напиши подтверждение на русском языке.$hwBlock$schedBlock$notesBlock$debtsBlock''',
    );
  }

  // ── Sliding window context builder ────────────────────────────────────────
  //
  // Always keeps: system prompt (index 0)
  // Drops oldest user/assistant pairs if total exceeds budget.

  List<Map<String, String>> _buildContext(
      List<ChatMessage> messages, ChatMessage systemPrompt) {
    int tokens = systemPrompt.estimatedTokens;
    final window = <ChatMessage>[];

    // Walk from newest to oldest (skip system messages in history)
    for (final m in messages.reversed) {
      if (m.role == MessageRole.system) continue;
      if (tokens + m.estimatedTokens > _maxContextTokens) break;
      tokens += m.estimatedTokens;
      window.insert(0, m);
    }

    return [
      systemPrompt.toApiMap(),
      ...window.map((m) => m.toApiMap()),
    ];
  }

  // ── Main chat call ────────────────────────────────────────────────────────

  Future<AiTurnResult> sendMessage({
    required ChatSession session,
    required String userText,
    List<HomeworkModel>? homework,
    List<ScheduleDay>? schedule,
    List<Map<String, dynamic>>? generalNotes,
    List<ProgressItem>? grades,
  }) async {
    final systemPrompt = _buildSystemPrompt(
        homework: homework, schedule: schedule, generalNotes: generalNotes, grades: grades);

    // Add user message to session
    final userMsg = ChatMessage(
        role: MessageRole.user,
        content: userText,
        timestamp: DateTime.now());
    session.messages.add(userMsg);

    final context = _buildContext(session.messages, systemPrompt);

    try {
      final resp = await _dio.post(
        '/chat/completions',
        data: jsonEncode({
          'model': _model,
          'messages': context,
          'max_tokens': _maxNewTokens,
          'temperature': 0.7,
          'stream': false,
        }),
      );

      if (resp.statusCode != 200) {
        throw Exception('NIM API ${resp.statusCode}: ${resp.data}');
      }

      final body = resp.data as Map<String, dynamic>;
      final content = body['choices'][0]['message']['content'] as String;

      // Extract action if present
      final action = _parseAction(content);
      final cleanText = _stripActionBlock(content);

      // Add assistant reply to session
      session.messages.add(ChatMessage(
          role: MessageRole.assistant,
          content: cleanText,
          timestamp: DateTime.now()));

      session.updatedAt = DateTime.now();
      session.metadata.tokenCount =
          (body['usage']?['total_tokens'] as int?) ?? 0;

      return AiTurnResult(text: cleanText, action: action);
    } on DioException catch (e) {
      final errMsg = e.type == DioExceptionType.connectionTimeout
          ? 'Нет соединения с AI сервером'
          : 'Ошибка AI: ${e.message}';
      // Remove the user message we added (rollback)
      session.messages.removeLast();
      throw Exception(errMsg);
    }
  }

  // ── Execute an AI action on local data ───────────────────────────────────

  Future<String> executeAction(AiAction action) async {
    switch (action.type) {
      case 'set_deadline':
        final lessonId = action.params['lessonId'] as String?;
        final dateStr  = action.params['deadline'] as String?;
        if (lessonId == null || dateStr == null) return 'Ошибка параметров';
        final deadline = DateTime.tryParse(dateStr);
        if (deadline == null) return 'Неверный формат даты';
        var hw = await ref.read(localDbServiceProvider).getLocalHomework(lessonId) ?? HomeworkModel(
            lessonId: lessonId, discipline: '', date: '');
        hw.deadline = deadline;
        await ref.read(localDbServiceProvider).saveLocalHomework(hw);
        return 'Дедлайн установлен: ${deadline.day}.${deadline.month}.${deadline.year}';

      case 'edit_note':
        final lessonId = action.params['lessonId'] as String?;
        final text     = action.params['text'] as String?;
        if (lessonId == null || text == null) return 'Ошибка параметров';
        var hw = await ref.read(localDbServiceProvider).getLocalHomework(lessonId) ?? HomeworkModel(
            lessonId: lessonId, discipline: '', date: '');
        hw.localText       = text;
        hw.isLocalOverwrite = true;
        await ref.read(localDbServiceProvider).saveLocalHomework(hw);
        return 'Заметка обновлена';

      case 'delete_note':
        final lessonId = action.params['lessonId'] as String?;
        if (lessonId == null) return 'Ошибка параметров';
        var hw = await ref.read(localDbServiceProvider).getLocalHomework(lessonId);
        if (hw != null) {
          hw.localText       = '';
          hw.isLocalOverwrite = false;
          hw.deadline        = null;
          await ref.read(localDbServiceProvider).saveLocalHomework(hw);
        }
        return 'Заметка удалена';

      case 'create_general_note':
        final title = action.params['title'] as String?;
        final content = action.params['content'] as String?;
        if (title == null) return 'Ошибка параметров';
        await ref.read(localDbServiceProvider).addGeneralNote(title: title, content: content ?? '');
        return 'Общая заметка создана';

      case 'edit_general_note':
        final id = action.params['id'] as int?;
        final content = action.params['content'] as String?;
        if (id == null || content == null) return 'Ошибка параметров';
        await ref.read(localDbServiceProvider).updateGeneralNote(id, content: content);
        return 'Общая заметка обновлена';

      default:
        return '';
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  AiAction? _parseAction(String text) {
    final match = RegExp(
            r'```action\s*\n(\{.*?\})\s*\n```',
            dotAll: true)
        .firstMatch(text);
    if (match == null) return null;
    try {
      final j = jsonDecode(match.group(1)!) as Map<String, dynamic>;
      return AiAction(
          type: j['type'] as String, params: Map<String, dynamic>.from(j));
    } catch (_) {
      return null;
    }
  }

  String _stripActionBlock(String text) => text
      .replaceAll(RegExp(r'```action\s*\n\{.*?\}\s*\n```', dotAll: true), '')
      .trim();
}
