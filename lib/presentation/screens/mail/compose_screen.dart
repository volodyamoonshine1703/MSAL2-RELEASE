import '../../../core/providers.dart';
// lib/presentation/screens/mail/compose_screen.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/mail_service.dart';
import '../../../data/services/owa_contact_search.dart';
import '../../widgets/contact_avatar.dart';
import 'dart:typed_data';

// ── Provider для поиска адресатов ─────────────────────────────────────────────

final _contactSearchProvider =
    FutureProvider.family<List<MailContact>, String>((ref, query) async {
  if (query.trim().length < 2) return [];
  return ref.read(mailServiceProvider).searchContacts(query);
});

// ── Экран создания письма ─────────────────────────────────────────────────────

class ComposeScreen extends ConsumerStatefulWidget {
  final String? initialTo;
  final String? initialSubject;
  final String? replyBody;

  const ComposeScreen({super.key, this.initialTo, this.initialSubject, this.replyBody});

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  final _toCtrl      = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl    = TextEditingController();
  final _toFocus     = FocusNode();

  bool   _showSuggestions = false;
  String _searchQuery     = '';
  bool   _sending         = false;
  String? _error;

  final List<MailContact> _recipients  = [];
  final List<File>        _attachments = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialTo != null) {
      _recipients.add(MailContact(name: widget.initialTo!, email: widget.initialTo!));
    }
    if (widget.initialSubject != null) _subjectCtrl.text = widget.initialSubject!;
    if (widget.replyBody != null) {
      _bodyCtrl.text = '\n\n──────────────\n${widget.replyBody}';
    }

    _toCtrl.addListener(() {
      final q = _toCtrl.text.trim();
      setState(() {
        _searchQuery     = q;
        _showSuggestions = q.length >= 2;
      });
    });
  }

  @override
  void dispose() {
    _toCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  void _addRecipient(MailContact contact) {
    setState(() {
      if (!_recipients.any((r) => r.email == contact.email)) {
        _recipients.add(contact);
      }
      _toCtrl.clear();
      _showSuggestions = false;
    });
  }

  void _addManualEmail() {
    final raw = _toCtrl.text.trim();
    if (raw.contains('@')) {
      _addRecipient(MailContact(name: raw, email: raw));
    }
  }

  Future<void> _pickFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );
      if (result == null) return;
      final picked = result.files
          .where((f) => f.path != null)
          .map((f) => File(f.path!))
          .toList();
      setState(() => _attachments.addAll(picked));
    } catch (e) {
      setState(() => _error = 'Ошибка выбора файла: $e');
    }
  }

  void _removeAttachment(int index) {
    setState(() => _attachments.removeAt(index));
  }

  Future<void> _send() async {
    if (_recipients.isEmpty) {
      setState(() => _error = 'Укажите получателя');
      return;
    }
    if (_subjectCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Укажите тему письма');
      return;
    }

    setState(() { _sending = true; _error = null; });

    try {
      await ref.read(mailServiceProvider).sendMessage(
        to:          _recipients.map((r) => r.email).toList(),
        subject:     _subjectCtrl.text.trim(),
        body:        _bodyCtrl.text,
        attachments: _attachments,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Письмо отправлено')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _error = 'Ошибка: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024)       return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: const Text('Новое письмо'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Attach button
          IconButton(
            icon: const Icon(Icons.attach_file_rounded),
            tooltip: 'Прикрепить файл',
            onPressed: _pickFiles,
          ),
          // Send button
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send_rounded, size: 18),
              label: const Text('Отправить'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: AppTheme.accent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
        ],
      ),
      body: Column(children: [
        // Error banner
        if (_error != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppTheme.error.withOpacity(0.15),
            child: Row(children: [
              Icon(Icons.error_outline, color: AppTheme.error, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(_error!,
                  style: TextStyle(color: AppTheme.error, fontSize: 13))),
              GestureDetector(
                onTap: () => setState(() => _error = null),
                child: Icon(Icons.close, color: AppTheme.error, size: 16)),
            ]),
          ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // ── Кому ──────────────────────────────────────────────────
              _FieldLabel('Кому'),
              const SizedBox(height: 6),

              if (_recipients.isNotEmpty)
                Wrap(
                  spacing: 6, runSpacing: 6,
                  children: _recipients.map((r) => Chip(
                    label: Text(r.name,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 12)),
                    deleteIcon: const Icon(Icons.close, size: 14, color: AppTheme.textMuted),
                    onDeleted: () => setState(() => _recipients.remove(r)),
                    backgroundColor: AppTheme.bgSurface,
                    side: BorderSide(color: AppTheme.accent.withOpacity(0.4)),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  )).toList(),
                ),
              const SizedBox(height: 6),

              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: _showSuggestions ? AppTheme.accent : AppTheme.divider),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _toCtrl,
                        focusNode: _toFocus,
                        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                        decoration: const InputDecoration(
                          hintText: 'Введите ФИО или email...',
                          hintStyle: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onSubmitted: (_) => _addManualEmail(),
                      ),
                    ),
                    if (_toCtrl.text.contains('@'))
                      GestureDetector(
                        onTap: _addManualEmail,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppTheme.accent,
                                borderRadius: BorderRadius.circular(8)),
                            child: const Text('Добавить',
                                style: TextStyle(color: Colors.white, fontSize: 12)),
                          ),
                        ),
                      ),
                  ]),

                  if (_showSuggestions)
                    _SuggestionList(query: _searchQuery, onSelect: _addRecipient),
                ]),
              ),
              const SizedBox(height: 14),

              // ── Тема ───────────────────────────────────────────────────
              _FieldLabel('Тема'),
              const SizedBox(height: 6),
              TextField(
                controller: _subjectCtrl,
                style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                decoration: const InputDecoration(hintText: 'Тема письма...'),
              ),
              const SizedBox(height: 14),

              // ── Текст ───────────────────────────────────────────────────
              _FieldLabel('Текст'),
              const SizedBox(height: 6),
              TextField(
                controller: _bodyCtrl,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 14, height: 1.6),
                decoration: const InputDecoration(
                  hintText: 'Текст письма...',
                  alignLabelWithHint: true,
                ),
                maxLines: 14,
                minLines: 8,
              ),
              const SizedBox(height: 14),

              // ── Вложения ────────────────────────────────────────────────
              if (_attachments.isNotEmpty) ...[
                _FieldLabel('Вложения (${_attachments.length})'),
                const SizedBox(height: 8),
                ..._attachments.asMap().entries.map((entry) {
                  final i = entry.key;
                  final f = entry.value;
                  final name = f.path.split('/').last.split('\\').last;
                  int size = 0;
                  try { size = f.lengthSync(); } catch (_) {}
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                        color: AppTheme.bgCard,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.divider)),
                    child: Row(children: [
                      const Icon(Icons.insert_drive_file_outlined,
                          color: AppTheme.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(name, style: const TextStyle(
                            color: AppTheme.textPrimary, fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                        if (size > 0) Text(_formatSize(size),
                            style: const TextStyle(
                                color: AppTheme.textMuted, fontSize: 10)),
                      ])),
                      GestureDetector(
                        onTap: () => _removeAttachment(i),
                        child: const Icon(Icons.close,
                            color: AppTheme.textMuted, size: 16)),
                    ]),
                  );
                }),
                const SizedBox(height: 6),
              ],

              // ── Кнопка добавить вложение ─────────────────────────────
              GestureDetector(
                onTap: _pickFiles,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppTheme.bgSurface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.divider),
                  ),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.attach_file_rounded, color: AppTheme.textMuted, size: 16),
                    SizedBox(width: 6),
                    Text('Прикрепить файл',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12)),
                  ]),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ]),
    );
  }
}

// ── Suggestion list ───────────────────────────────────────────────────────────

class _SuggestionList extends ConsumerWidget {
  final String query;
  final ValueChanged<MailContact> onSelect;
  const _SuggestionList({required this.query, required this.onSelect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_contactSearchProvider(query));

    return Container(
      decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.divider))),
      constraints: const BoxConstraints(maxHeight: 200),
      child: async.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: SizedBox(width: 20, height: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))),
        ),
        error: (_, __) => const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Ошибка поиска',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 12))),
        data: (contacts) {
          if (contacts.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Нет совпадений. Введите email вручную.',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 12)));
          }
          return ListView.separated(
            shrinkWrap: true,
            itemCount: contacts.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppTheme.divider),
            itemBuilder: (_, i) {
              final c = contacts[i];
              return ListTile(
                dense: true,
                leading: ContactAvatar(name: c.name, email: c.email, size: 40),
                title: Text(c.name,
                    style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
                subtitle: Text(c.email,
                    style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                onTap: () => onSelect(c),
              );
            },
          );
        },
      ),
    );
  }
}

// Shared ContactAvatar is used instead of local implementation

class _FieldLabel extends ConsumerWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context, WidgetRef ref) => Text(text,
      style: const TextStyle(
          color: AppTheme.textMuted, fontSize: 11,
          fontWeight: FontWeight.w600, letterSpacing: 0.5));
}
