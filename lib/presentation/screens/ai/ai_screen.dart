import '../../../core/providers.dart';
// lib/presentation/screens/ai/ai_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/models/chat_model.dart';
import '../../../data/services/ai_service.dart';
import '../../../data/services/chat_storage_service.dart';

import '../../../data/services/api_service.dart';
import '../../../data/services/local_db_service.dart';
import '../../../core/providers/scaffold_provider.dart';
import '../grades/grades_screen.dart' show gradesProvider;

// ── Providers ──────────────────────────────────────────────────────────────────

final chatListProvider =
    StateNotifierProvider<ChatListNotifier, List<ChatSummary>>(
        (ref) => ChatListNotifier(ref));

class ChatListNotifier extends StateNotifier<List<ChatSummary>> {
  final Ref ref;
  ChatListNotifier(this.ref) : super([]) { load(); }

  Future<void> load() async {
    state = await ref.read(chatStorageServiceProvider).listChats();
  }

  Future<void> delete(String chatId) async {
    await ref.read(chatStorageServiceProvider).deleteChat(chatId);
    state = state.where((s) => s.chatId != chatId).toList();
  }
}

final activeChatProvider =
    StateNotifierProvider<ActiveChatNotifier, ChatSession?>(
        (ref) => ActiveChatNotifier(ref));

class ActiveChatNotifier extends StateNotifier<ChatSession?> {
  final Ref ref;
  String? pendingInitialQuery;
  ActiveChatNotifier(this.ref) : super(null);

  void open(ChatSession chat) => state = chat;
  void close() => state = null;

  Future<void> openById(String chatId) async {
    final chat = await ref.read(chatStorageServiceProvider).loadChat(chatId);
    if (chat != null) state = chat;
  }

  Future<void> createNew({String? initialQuery}) async {
    final chat = ChatSession.create();
    if (initialQuery != null) {
      chat.title = 'План закрытия долгов';
    }
    pendingInitialQuery = initialQuery;
    state = chat;
  }

  Future<void> saveAndSync() async {
    if (state == null) return;
    await ref.read(chatStorageServiceProvider).saveChat(state!);
    ref.read(chatListProvider.notifier).load();
  }
}

final _sendingProvider = StateProvider<bool>((_) => false);

// ── Root AI Screen ─────────────────────────────────────────────────────────────

class AiScreen extends ConsumerWidget {
  const AiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeChat = ref.watch(activeChatProvider);

    if (activeChat != null) {
      return _ChatView(key: ValueKey(activeChat.chatId), session: activeChat);
    }
    return const _ChatListView();
  }
}

// ── Chat List ─────────────────────────────────────────────────────────────────

class _ChatListView extends ConsumerWidget {
  const _ChatListView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats  = ref.watch(chatListProvider);

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
        ),
        title: Row(children: [
          const Text('ИИ-Ассистент'),
        ]),
        actions: [
          // Sync button
          IconButton(
            icon: const Icon(Icons.sync_outlined),
            tooltip: 'Синхронизировать',
            onPressed: () => _doSync(ref),
          ),
          IconButton(
            icon: const Icon(Icons.add_outlined),
            tooltip: 'Новый чат',
            onPressed: () async {
              await ref.read(activeChatProvider.notifier).createNew();
            },
          ),
        ],
      ),
      body: Column(children: [

        // Chat list
        Expanded(
          child: chats.isEmpty
              ? _EmptyState(
                  onNewChat: () =>
                      ref.read(activeChatProvider.notifier).createNew())
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: chats.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, color: AppTheme.divider),
                  itemBuilder: (_, i) => _ChatTile(
                    summary: chats[i],
                    onTap: () =>
                        ref.read(activeChatProvider.notifier).openById(chats[i].chatId),
                    onDelete: () =>
                        ref.read(chatListProvider.notifier).delete(chats[i].chatId),
                  ),
                ),
        ),
      ]),
      floatingActionButton: chats.isNotEmpty
          ? FloatingActionButton.extended(
              heroTag: 'fab_ai_new_chat',
              onPressed: () =>
                  ref.read(activeChatProvider.notifier).createNew(),
              backgroundColor: AppTheme.accent,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text('Новый чат',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            )
          : null,
    );
  }

  Future<void> _doSync(WidgetRef ref) async {
    await ref.read(chatListProvider.notifier).load();
  }

  Future<void> _doConnect(BuildContext context, WidgetRef ref) async {
    // Drive sync removed
  }
}

// ── Chat View ──────────────────────────────────────────────────────────────────

class _ChatView extends ConsumerStatefulWidget {
  final ChatSession session;
  const _ChatView({super.key, required this.session});

  @override
  ConsumerState<_ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<_ChatView> {
  final _ctrl   = TextEditingController();
  final _scroll = ScrollController();
  late ChatSession _session;
  bool _sending = false;
  String? _actionFeedback;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    
    final pending = ref.read(activeChatProvider.notifier).pendingInitialQuery;
    if (pending != null && _session.messages.isEmpty) {
      _ctrl.text = pending;
      ref.read(activeChatProvider.notifier).pendingInitialQuery = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _send();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _attachFile() async {
    try {
      final result = await FilePicker.platform.pickFiles();
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        final name = file.name;
        setState(() {
          _ctrl.text = _ctrl.text + '\n[Вложен файл: $name]\n';
        });
      }
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ошибка выбора файла')),
      );
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    _ctrl.clear();
    setState(() { _sending = true; _actionFeedback = null; });

    try {
      // Load context data for AI
      final hw       = await ref.read(localDbServiceProvider).getAllHomework();
      final schedule = await ref.read(apiServiceProvider).getCurrentWeek();
      final notes    = await ref.read(localDbServiceProvider).getAllGeneralNotes();
      
      // Try to load debts/grades
      dynamic grades;
      try {
        grades = await ref.read(gradesProvider.future);
      } catch (_) {}

      final result = await ref.read(aiServiceProvider).sendMessage(
        session: _session,
        userText: text,
        homework: hw,
        schedule: schedule,
        generalNotes: notes,
        grades: grades,
      );

      // Execute action if AI requested one
      if (result.action != null) {
        final feedback = await ref.read(aiServiceProvider).executeAction(result.action!);
        setState(() => _actionFeedback = feedback);
      }

      // Auto-title after first user message
      if (_session.title == 'Новый чат' &&
          _session.messages.where((m) => m.role == MessageRole.user).length == 1) {
        _session.title = text.length > 40 ? '${text.substring(0, 40)}…' : text;
      }

      // Save + sync
      await ref.read(activeChatProvider.notifier).saveAndSync();

      setState(() {});
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppTheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibleMessages =
        _session.messages.where((m) => m.role != MessageRole.system).toList();

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        title: Text(_session.title, overflow: TextOverflow.ellipsis),
        leading: BackButton(onPressed: () {
          ref.read(activeChatProvider.notifier).close();
        }),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Переименовать',
            onPressed: () => _renameDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            tooltip: 'Удалить чат',
            color: AppTheme.error,
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppTheme.bgCard,
                  title: const Text('Удалить чат?',
                      style: TextStyle(color: AppTheme.textPrimary)),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false),
                        child: const Text('Отмена')),
                    TextButton(onPressed: () => Navigator.pop(context, true),
                        child: Text('Удалить',
                            style: TextStyle(color: AppTheme.error))),
                  ],
                ),
              );
              if (ok == true) {
                await ref.read(chatListProvider.notifier).delete(_session.chatId);
                ref.read(activeChatProvider.notifier).close();
              }
            },
          ),
        ],
      ),
      body: Column(children: [
        // Action feedback chip
        if (_actionFeedback != null && _actionFeedback!.isNotEmpty)
          _ActionFeedbackBar(text: _actionFeedback!),

        // Messages
        Expanded(
          child: visibleMessages.isEmpty
              ? _WelcomeHints(onHint: (h) {
                  _ctrl.text = h;
                  _send();
                })
              : ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  itemCount: visibleMessages.length + (_sending ? 1 : 0),
                  itemBuilder: (_, i) {
                    if (i == visibleMessages.length) {
                      return const _TypingIndicator();
                    }
                    return _MessageBubble(msg: visibleMessages[i]);
                  },
                ),
        ),

        // Input bar
        _InputBar(
          ctrl: _ctrl,
          sending: _sending,
          onSend: _send,
          onAttach: _attachFile,
        ),
      ]),
    );
  }

  Future<void> _renameDialog() async {
    final ctrl = TextEditingController(text: _session.title);
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Переименовать чат',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration:
              const InputDecoration(hintText: 'Название чата'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Сохранить')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      setState(() => _session.title = result);
      await ref.read(activeChatProvider.notifier).saveAndSync();
    }
  }
}

// ── Message Bubble ─────────────────────────────────────────────────────────────

class _MessageBubble extends ConsumerWidget {
  final ChatMessage msg;
  const _MessageBubble({required this.msg});

  bool get _isUser => msg.role == MessageRole.user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Align(
      alignment: _isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        child: GestureDetector(
          onLongPress: () {
            Clipboard.setData(ClipboardData(text: msg.content));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Скопировано')),
            );
          },
          child: Container(
            margin: EdgeInsets.only(
              top: 4, bottom: 4,
              left: _isUser ? 40 : 0,
              right: _isUser ? 0 : 40,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _isUser
                  ? AppTheme.accent
                  : AppTheme.bgCard,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(_isUser ? 16 : 4),
                bottomRight: Radius.circular(_isUser ? 4 : 16),
              ),
              border: _isUser
                  ? null
                  : Border.all(color: AppTheme.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.content,
                  style: TextStyle(
                    color: _isUser ? Colors.white : AppTheme.textPrimary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(children: [
                  Text(
                    DateFormat('HH:mm').format(msg.timestamp),
                    style: TextStyle(
                      color: _isUser
                          ? Colors.white.withOpacity(0.6)
                          : AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  ),
                  if (!_isUser) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: msg.content));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Скопировано'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      },
                      child: const Icon(Icons.copy_outlined,
                          color: AppTheme.textMuted, size: 14),
                    ),
                  ],
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Typing indicator ───────────────────────────────────────────────────────────

class _TypingIndicator extends ConsumerStatefulWidget {
  const _TypingIndicator();
  @override
  ConsumerState<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends ConsumerState<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16), topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4), bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          ...List.generate(3, (i) {
            final anim = Tween(begin: 0.3, end: 1.0).animate(
              CurvedAnimation(
                parent: _ctrl,
                curve: Interval(i * 0.2, i * 0.2 + 0.5,
                    curve: Curves.easeInOut),
              ),
            );
            return AnimatedBuilder(
              animation: anim,
              builder: (_, __) => Container(
                width: 7, height: 7,
                margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(anim.value),
                  shape: BoxShape.circle,
                ),
              ),
            );
          }),
        ]),
      ),
    );
  }
}

// ── Input Bar ──────────────────────────────────────────────────────────────────

class _InputBar extends ConsumerWidget {
  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  const _InputBar({required this.ctrl, required this.sending,
      required this.onSend, required this.onAttach});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      padding: EdgeInsets.only(
        left: 12, right: 8, top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 12,
      ),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        border: Border(top: BorderSide(color: AppTheme.divider)),
      ),
      child: Row(children: [
        // Attach file button
        GestureDetector(
          onTap: onAttach,
          child: Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: AppTheme.bgSurface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.divider),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.attach_file_rounded,
                color: AppTheme.textMuted, size: 18),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctrl,
            maxLines: 4,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.send,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Спросить ассистента...',
              hintStyle: const TextStyle(color: AppTheme.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppTheme.divider),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppTheme.divider),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: const BorderSide(color: AppTheme.accent),
              ),
              filled: true,
              fillColor: AppTheme.bgSurface,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 10),
            ),
            onSubmitted: (_) => onSend(),
          ),
        ),
        const SizedBox(width: 8),
        _SendButton(sending: sending, onSend: onSend),
      ]),
    );
  }
}

class _SendButton extends ConsumerWidget {
  final bool sending;
  final VoidCallback onSend;
  const _SendButton({required this.sending, required this.onSend});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: sending ? null : onSend,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: sending ? AppTheme.bgSurface : AppTheme.accent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: sending
            ? const SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent))
            : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
      ),
    );
  }
}

// ── Welcome hints ──────────────────────────────────────────────────────────────

class _WelcomeHints extends ConsumerWidget {
  final ValueChanged<String> onHint;
  const _WelcomeHints({required this.onHint});

  static const _hints = [
    '📅 Что у меня на этой неделе?',
    '🔥 Какие дедлайны горят сейчас?',
    '📝 Поставь дедлайн на ДЗ по гражданскому праву — пятница',
    '📊 Как улучшить посещаемость в этом семестре?',
    '🗓 Составь план подготовки к зачёту',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 68, height: 68,
              decoration: BoxDecoration(
                gradient: AppTheme.accentGradient,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accent.withOpacity(0.35),
                    blurRadius: 24, spreadRadius: 2,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: const Text('AI',
                  style: TextStyle(color: Colors.white,
                      fontSize: 24, fontWeight: FontWeight.w800)),
            ),
            const SizedBox(height: 20),
            const Text('Привет! Я твой ассистент МГЮА.',
                style: TextStyle(color: AppTheme.textPrimary,
                    fontSize: 17, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            const Text(
              'Помогу с расписанием, дедлайнами\nи управлением заметками.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ..._hints.map((h) => _HintChip(text: h, onTap: () => onHint(h))),
          ],
        ),
      ),
    );
  }
}

class _HintChip extends ConsumerWidget {
  final String text;
  final VoidCallback onTap;
  const _HintChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider),
        ),
        child: Text(text,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
      ),
    );
  }
}

// ── Chat tile ──────────────────────────────────────────────────────────────────

class _ChatTile extends ConsumerWidget {
  final ChatSummary summary;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _ChatTile({required this.summary, required this.onTap, required this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(summary.chatId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppTheme.bgCard,
            title: const Text('Удалить чат?',
                style: TextStyle(color: AppTheme.textPrimary)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('Отмена')),
              TextButton(onPressed: () => Navigator.pop(context, true),
                  child: Text('Удалить',
                      style: TextStyle(color: AppTheme.error))),
            ],
          ),
        );
      },
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.error.withOpacity(0.2),
        child: const Icon(Icons.delete_outline, color: AppTheme.error),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: const Text('AI',
              style: TextStyle(color: AppTheme.accent,
                  fontSize: 13, fontWeight: FontWeight.w700)),
        ),
        title: Text(summary.title,
            style: const TextStyle(color: AppTheme.textPrimary,
                fontSize: 14, fontWeight: FontWeight.w500),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          DateFormat('d MMM, HH:mm', 'ru_RU').format(summary.updatedAt),
          style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
        ),
        trailing: const Icon(Icons.chevron_right,
            color: AppTheme.textMuted, size: 18),
      ),
    );
  }
}

// ── Misc widgets ───────────────────────────────────────────────────────────────



class _ActionFeedbackBar extends ConsumerWidget {
  final String text;
  const _ActionFeedbackBar({required this.text});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppTheme.success.withOpacity(0.08),
      child: Row(children: [
        const Icon(Icons.check_circle_outline,
            color: AppTheme.success, size: 16),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(
                color: AppTheme.success, fontSize: 12)),
      ]),
    );
  }
}

class _EmptyState extends ConsumerWidget {
  final VoidCallback onNewChat;
  const _EmptyState({required this.onNewChat});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppTheme.accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(18),
          ),
          alignment: Alignment.center,
          child: const Text('AI',
              style: TextStyle(color: AppTheme.accent,
                  fontSize: 22, fontWeight: FontWeight.w800)),
        ),
        const SizedBox(height: 16),
        const Text('Нет чатов', style: TextStyle(
            color: AppTheme.textSecondary, fontSize: 16)),
        const SizedBox(height: 8),
        const Text('Начни новый разговор с ИИ-ассистентом',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
        const SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: onNewChat,
          icon: const Icon(Icons.add),
          label: const Text('Начать чат'),
        ),
      ]),
    );
  }
}
