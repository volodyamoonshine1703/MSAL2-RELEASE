import '../../../core/providers.dart';
// lib/presentation/screens/mail/mail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/mail_service.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/models/user_model.dart';
import 'mail_detail_screen.dart';
import 'compose_screen.dart';
import '../../widgets/contact_avatar.dart';
import '../../../core/providers/scaffold_provider.dart';

final _mailConnectedProvider = StateProvider<bool>((ref) => false);
final _selectedFolderProvider = StateProvider<String>((ref) => 'INBOX');
final _foldersProvider = FutureProvider<List<MailFolder>>((ref) async {
  if (!ref.read(mailServiceProvider).isConnected) return [];
  return ref.read(mailServiceProvider).listFolders();
});
final _messagesProvider = FutureProvider.family<List<MailMessage>, String>((ref, folder) async {
  if (!ref.read(mailServiceProvider).isConnected) return [];
  return ref.read(mailServiceProvider).fetchMessages(folder);
});

class MailScreen extends ConsumerStatefulWidget {
  const MailScreen({super.key});
  @override
  ConsumerState<MailScreen> createState() => _MailScreenState();
}

class _MailScreenState extends ConsumerState<MailScreen> {
  bool _connecting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Auto-connect when entering mail screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.read(_mailConnectedProvider) && !ref.read(mailServiceProvider).isConnected) {
        _connect();
      } else if (ref.read(mailServiceProvider).isConnected) {
        ref.read(_mailConnectedProvider.notifier).state = true;
      }
    });
  }

  Future<void> _connect() async {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return;
    final prefs = await SharedPreferences.getInstance();
    final password = prefs.getString('saved_password');
    if (password == null || password.isEmpty) {
      if (mounted) setState(() => _error = 'Не удалось получить пароль для почты');
      return;
    }
    if (mounted) setState(() { _connecting = true; _error = null; });
    try {
      String emailToUse = user.emailCorporate;
      if (emailToUse.isEmpty) {
        if (user.login.contains('@')) {
          emailToUse = user.login;
        } else if (user.isInstitute) {
          emailToUse = '${user.login}@msal.ru';
        } else {
          emailToUse = '${user.login}@edu.msal.ru';
        }
      }
      await ref.read(mailServiceProvider).connect(emailToUse, password);
      ref.read(_mailConnectedProvider.notifier).state = true;
      ref.invalidate(_foldersProvider);
    } catch (e) {
      if (mounted) setState(() => _error = 'Ошибка подключения: $e');
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = ref.watch(_mailConnectedProvider);
    if (!connected) {
      // Show loading or error state instead of a connect button
      return Scaffold(
        backgroundColor: AppTheme.bgDark,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
          ),
          title: const Text('Почта'),
        ),
        body: Center(child: _connecting
          ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const CircularProgressIndicator(color: AppTheme.accent),
              const SizedBox(height: 16),
              const Text('Подключение к почте...', style: TextStyle(color: AppTheme.textMuted, fontSize: 14)),
            ])
          : _error != null
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.mail_outline, color: AppTheme.error, size: 48),
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton.icon(onPressed: _connect, icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Повторить')),
              ])
            : const SizedBox.shrink(),
        ),
      );
    }
    return const _MailClientView();
  }
}

class _ConnectView extends ConsumerWidget {
  final bool connecting;
  final String? error;
  final UserModel? user;
  final VoidCallback onConnect;
  const _ConnectView({required this.connecting, required this.error,
      required this.user, required this.onConnect});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
        ),
        title: const Text('Почта'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  gradient: AppTheme.accentGradient,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.35), blurRadius: 30)],
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.mail_rounded, color: Colors.white, size: 36),
              ),
              const SizedBox(height: 28),
              const Text('Корпоративная почта',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (user != null)
                Text(
                  user!.emailCorporate.isNotEmpty 
                      ? user!.emailCorporate 
                      : (user!.isInstitute ? '${user!.login}@msal.ru' : '${user!.login}@edu.msal.ru'),
                  style: const TextStyle(color: AppTheme.accent, fontSize: 14),
                ),
              const SizedBox(height: 8),
              const Text(
                'IMAP + SMTP  •  mail.msal.ru\nИспользуется пароль от личного кабинета',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.6),
                textAlign: TextAlign.center,
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                  ),
                  child: Text(error!,
                      style: TextStyle(color: AppTheme.error, fontSize: 12),
                      textAlign: TextAlign.center),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: connecting ? null : onConnect,
                  child: connecting
                      ? const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Подключить почту'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MailClientView extends ConsumerWidget {
  const _MailClientView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folder = ref.watch(_selectedFolderProvider);
    final foldersAsync = ref.watch(_foldersProvider);
    final messagesAsync = ref.watch(_messagesProvider(folder));

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      floatingActionButton: FloatingActionButton.extended(
              heroTag: 'fab_mail_compose',
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ComposeScreen())),
        backgroundColor: AppTheme.accent,
        icon: const Icon(Icons.edit_outlined, color: Colors.white),
        label: const Text('Написать', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
      ),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
        ),
        title: foldersAsync.maybeWhen(
          data: (folders) => Text(folders.firstWhereOrNull((f) => f.path == folder)?.name ?? 'Входящие'),
          orElse: () => const Text('Почта'),
        ),
        actions: [
          foldersAsync.maybeWhen(
            data: (folders) => PopupMenuButton<String>(
              icon: const Icon(Icons.folder_outlined),
              color: AppTheme.bgSurface,
              onSelected: (path) => ref.read(_selectedFolderProvider.notifier).state = path,
              itemBuilder: (_) => folders.map((f) => PopupMenuItem(
                value: f.path,
                child: Row(children: [
                  Icon(_icon(f.name), color: AppTheme.accent, size: 18),
                  const SizedBox(width: 10),
                  Text(f.name, style: const TextStyle(color: AppTheme.textPrimary)),
                  if ((f.unseenCount ?? 0) > 0) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(10)),
                      child: Text('${f.unseenCount}',
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ]),
              )).toList(),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_outlined),
            onPressed: () => ref.refresh(_messagesProvider(folder)),
          ),
        ],
      ),
      body: messagesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (e, _) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, color: AppTheme.error, size: 48),
            const SizedBox(height: 12),
            Text('$e', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: () => ref.refresh(_messagesProvider(folder)),
                child: const Text('Повторить')),
          ]),
        ),
        data: (messages) => messages.isEmpty
            ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.inbox_outlined, color: AppTheme.textMuted, size: 48),
                SizedBox(height: 12),
                Text('Нет писем', style: TextStyle(color: AppTheme.textSecondary)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 80),
                itemCount: messages.length,
                itemBuilder: (ctx, i) => _MessageTile(message: messages[i], folder: folder),
              ),
      ),
    );
  }

  IconData _icon(String name) {
    if (name.contains('Вход')) return Icons.inbox_rounded;
    if (name.contains('Отправл')) return Icons.send_rounded;
    if (name.contains('Черн')) return Icons.edit_outlined;
    if (name.contains('Корз')) return Icons.delete_outline;
    return Icons.folder_outlined;
  }
}

class _MessageTile extends ConsumerWidget {
  final MailMessage message;
  final String folder;
  const _MessageTile({required this.message, required this.folder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateFmt = message.date != null ? _fmt(message.date!) : '';
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.divider, width: 0.5)),
        color: message.isSeen ? Colors.transparent : AppTheme.accent.withOpacity(0.04),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: ContactAvatar(name: message.from, email: message.fromEmail, size: 44),
        title: Row(children: [
          Expanded(child: Text(message.from,
              style: TextStyle(color: AppTheme.textPrimary,
                  fontWeight: message.isSeen ? FontWeight.w400 : FontWeight.w600, fontSize: 13),
              maxLines: 1, overflow: TextOverflow.ellipsis)),
          Text(dateFmt, style: TextStyle(
              color: message.isSeen ? AppTheme.textMuted : AppTheme.accent, fontSize: 11)),
        ]),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 3),
          Text(message.subject,
              style: TextStyle(color: message.isSeen ? AppTheme.textSecondary : AppTheme.textPrimary,
                  fontSize: 13, fontWeight: message.isSeen ? FontWeight.w400 : FontWeight.w500),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          if (message.hasAttachments)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Row(children: [
                Icon(Icons.attach_file, size: 12, color: AppTheme.textMuted),
                SizedBox(width: 3),
                Text('Вложение', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
              ]),
            ),
        ]),
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => MailDetailScreen(message: message, folder: folder))),
      ),
    );
  }

  String _fmt(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day)
      return DateFormat('HH:mm').format(date);
    if (date.year == now.year) return DateFormat('d MMM', 'ru_RU').format(date);
    return DateFormat('dd.MM.yy').format(date);
  }
}

// Removed _Avatar (now using shared ContactAvatar)

extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) { if (test(e)) return e; }
    return null;
  }
}
