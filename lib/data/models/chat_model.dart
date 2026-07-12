// lib/data/models/chat_model.dart
//
// JSON schema for one chat session:
// {
//   "chat_id": "uuid-v4",
//   "title": "Расписание на май",
//   "created_at": "2026-04-28T10:00:00Z",
//   "updated_at": "2026-04-28T10:30:00Z",
//   "messages": [
//     {"role": "system", "content": "...", "timestamp": "..."},
//     {"role": "user",   "content": "...", "timestamp": "..."},
//     {"role": "assistant", "content": "...", "timestamp": "..."}
//   ],
//   "metadata": {
//     "homework_ids": ["lesson-abc", "lesson-def"],
//     "discipline_ids": ["disc-123"],
//     "drive_file_id": "1BxiM...google drive file id",
//     "token_count": 1840
//   }
// }

import 'dart:convert';

enum MessageRole { system, user, assistant }

class ChatMessage {
  final MessageRole role;
  final String content;
  final DateTime timestamp;

  const ChatMessage({
    required this.role,
    required this.content,
    required this.timestamp,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
        role: MessageRole.values.firstWhere(
            (r) => r.name == j['role'], orElse: () => MessageRole.user),
        content: j['content'] as String,
        timestamp: DateTime.tryParse(j['timestamp'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
      };

  /// Format for NIM/OpenAI API call
  Map<String, String> toApiMap() => {
        'role': role.name,
        'content': content,
      };

  /// Rough token estimate (4 chars ≈ 1 token)
  int get estimatedTokens => (content.length / 4).ceil();
}

class ChatMetadata {
  final List<String> homeworkIds;
  final List<String> disciplineIds;
  final String? driveFileId;
  int tokenCount;

  ChatMetadata({
    this.homeworkIds = const [],
    this.disciplineIds = const [],
    this.driveFileId,
    this.tokenCount = 0,
  });

  factory ChatMetadata.fromJson(Map<String, dynamic> j) => ChatMetadata(
        homeworkIds: List<String>.from(j['homework_ids'] ?? []),
        disciplineIds: List<String>.from(j['discipline_ids'] ?? []),
        driveFileId: j['drive_file_id'] as String?,
        tokenCount: (j['token_count'] as int?) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'homework_ids': homeworkIds,
        'discipline_ids': disciplineIds,
        'drive_file_id': driveFileId,
        'token_count': tokenCount,
      };

  ChatMetadata copyWith({String? driveFileId, int? tokenCount}) => ChatMetadata(
        homeworkIds: homeworkIds,
        disciplineIds: disciplineIds,
        driveFileId: driveFileId ?? this.driveFileId,
        tokenCount: tokenCount ?? this.tokenCount,
      );
}

class ChatSession {
  final String chatId;
  String title;
  final DateTime createdAt;
  DateTime updatedAt;
  List<ChatMessage> messages;
  ChatMetadata metadata;

  ChatSession({
    required this.chatId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
    required this.messages,
    required this.metadata,
  });

  factory ChatSession.create({String title = 'Новый чат'}) => ChatSession(
        chatId: _uuid(),
        title: title,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        messages: [],
        metadata: ChatMetadata(),
      );

  factory ChatSession.fromJson(Map<String, dynamic> j) => ChatSession(
        chatId: j['chat_id'] as String,
        title: j['title'] as String? ?? 'Чат',
        createdAt: DateTime.tryParse(j['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(j['updated_at'] as String? ?? '') ??
            DateTime.now(),
        messages: (j['messages'] as List<dynamic>? ?? [])
            .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
        metadata: j['metadata'] != null
            ? ChatMetadata.fromJson(j['metadata'] as Map<String, dynamic>)
            : ChatMetadata(),
      );

  Map<String, dynamic> toJson() => {
        'chat_id': chatId,
        'title': title,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
        'metadata': metadata.toJson(),
      };

  String toJsonString() => jsonEncode(toJson());

  /// Last Write Wins: this chat wins if its updatedAt is newer
  bool isNewerThan(ChatSession other) => updatedAt.isAfter(other.updatedAt);

  /// Preview text for chat list
  String get preview {
    final last = messages.lastWhere(
        (m) => m.role != MessageRole.system,
        orElse: () => messages.isEmpty
            ? ChatMessage(
                role: MessageRole.user,
                content: '',
                timestamp: createdAt)
            : messages.first);
    final text = last.content;
    return text.length > 60 ? '${text.substring(0, 60)}...' : text;
  }

  static String _uuid() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${now.toRadixString(16)}-${(now % 0xFFFF).toRadixString(16)}-'
        '${DateTime.now().millisecond.toRadixString(16)}';
  }
}
