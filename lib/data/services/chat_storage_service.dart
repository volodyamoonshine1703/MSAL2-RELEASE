import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/data/services/chat_storage_service.dart
//
// Local SQLite store + lazy loading.
// Full chat JSON stored as-is in a TEXT column for simplicity.

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/chat_model.dart';
import 'package:uuid/uuid.dart';

class ChatStorageService {
  final Ref ref;
  ChatStorageService(this.ref);

  static const _uuidGen = Uuid();

  static String _uuid() {
    return _uuidGen.v4();
  }

  Database? _db;

  Future<void> init() async {
    final dir = await getApplicationDocumentsDirectory();
    _db = await openDatabase(
      p.join(dir.path, 'msal_chats.db'),
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE chats (
            chat_id   TEXT PRIMARY KEY,
            title     TEXT NOT NULL,
            updated_at TEXT NOT NULL,
            json_data TEXT NOT NULL
          )
        ''');
        // Index for fast sorted listing
        await db.execute(
            'CREATE INDEX idx_chats_updated ON chats(updated_at DESC)');
      },
    );
  }

  Database get _d {
    assert(_db != null, 'ChatStorageService not initialized');
    return _db!;
  }

  // ── CRUD ──────────────────────────────────────────────────────────────────

  Future<void> saveChat(ChatSession chat) async {
    await _d.insert(
      'chats',
      {
        'chat_id': chat.chatId,
        'title': chat.title,
        'updated_at': chat.updatedAt.toIso8601String(),
        'json_data': chat.toJsonString(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Lazy loading: returns only (chatId, title, updatedAt) — no messages
  Future<List<ChatSummary>> listChats({int limit = 30, int offset = 0}) async {
    final rows = await _d.query(
      'chats',
      columns: ['chat_id', 'title', 'updated_at'],
      orderBy: 'updated_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map((r) => ChatSummary(
          chatId: r['chat_id'] as String,
          title: r['title'] as String,
          updatedAt: DateTime.tryParse(r['updated_at'] as String) ??
              DateTime.now(),
        )).toList();
  }

  /// Load full chat (with messages) only when opened
  Future<ChatSession?> loadChat(String chatId) async {
    final rows = await _d.query('chats',
        where: 'chat_id = ?', whereArgs: [chatId]);
    if (rows.isEmpty) return null;
    return ChatSession.fromJson(
        jsonDecode(rows.first['json_data'] as String));
  }

  Future<void> deleteChat(String chatId) async {
    await _d.delete('chats', where: 'chat_id = ?', whereArgs: [chatId]);
  }

  Future<int> getTotalCount() async {
    final result =
        await _d.rawQuery('SELECT COUNT(*) as cnt FROM chats');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Last Write Wins: merge remote chat into local
  Future<void> mergeRemoteChat(ChatSession remote) async {
    final local = await loadChat(remote.chatId);
    if (local == null || remote.isNewerThan(local)) {
      await saveChat(remote);
    }
    // else local is newer or equal — keep local
  }
}

/// Lightweight summary used in list (no messages loaded)
class ChatSummary {
  final String chatId;
  final String title;
  final DateTime updatedAt;
  const ChatSummary(
      {required this.chatId, required this.title, required this.updatedAt});
}
