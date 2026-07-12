import '../../../core/providers.dart';
// lib/presentation/screens/profile/profile_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_service.dart';
import '../../../data/services/api_service.dart';
import '../../../data/models/user_model.dart';
import '../login/login_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../data/services/local_db_service.dart';
import '../../../core/providers/scaffold_provider.dart';
import '../../../data/services/ai_service.dart';
import '../mail/compose_screen.dart';
import '../grades/grades_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../shell/main_shell.dart' show shellIndexProvider;
import '../../../app.dart' show sessionProvider;


// ── Providers ──────────────────────────────────────────────────────────────────

final _groupmatesProvider = FutureProvider<List<UserModel>>((ref) async {
  return ref.read(apiServiceProvider).getGroupmates();
});

final _passesProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  return ref.read(apiServiceProvider).getStudentPasses();
});

// Local state for privacy toggles (mirrors server state)
final _privacyProvider = StateProvider<({bool email, bool photo, bool mobile})>((ref) {
  final user = ref.read(authServiceProvider).currentUser;
  return (
    email: user?.showEmail ?? true,
    photo: user?.showPhoto ?? true,
    mobile: user?.showMobile ?? true,
  );
});

// ── Screen ─────────────────────────────────────────────────────────────────────

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.read(authServiceProvider).currentUser;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      backgroundColor: AppTheme.bgDark,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            expandedHeight: 210,
            pinned: true,
            backgroundColor: AppTheme.bgDark,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: () => ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
            ),
            flexibleSpace: FlexibleSpaceBar(background: _ProfileHero(user: user)),
            bottom: TabBar(
              controller: _tabs,
              labelColor: AppTheme.accent,
              unselectedLabelColor: AppTheme.textMuted,
              indicatorColor: AppTheme.accent,
              indicatorSize: TabBarIndicatorSize.label,
              tabs: const [Tab(text: 'Профиль'), Tab(text: 'Группа')],
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabs,
          children: [
            _ProfileTab(user: user),
            _GroupTab(),
          ],
        ),
      ),
    );
  }
}

// ── Profile Tab ────────────────────────────────────────────────────────────────

class _ProfileTab extends ConsumerWidget {
  final UserModel user;
  const _ProfileTab({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passesAsync = ref.watch(_passesProvider);
    final privacy = ref.watch(_privacyProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Academic
        _InfoCard(title: 'Академическая информация', rows: [
          _InfoRowData(Icons.school_outlined, 'Специальность', user.speciality),
          _InfoRowData(Icons.domain_outlined, 'Факультет', user.department),
          _InfoRowData(Icons.group_outlined, 'Группа', user.group),
          _InfoRowData(Icons.calendar_today_outlined, 'Курс / Семестр', 'Курс ${user.course}, Семестр ${user.semester}'),
          _InfoRowData(Icons.badge_outlined, 'Статус', user.subrole == 'COLLEGE' ? 'Студент колледжа' : 'Студент'),
        ]),
        const SizedBox(height: 14),

        // Contacts
        _InfoCard(title: 'Контакты', rows: [
          _InfoRowData(Icons.mail_outline, 'Email', user.email),
          if (user.emailCorporate.isNotEmpty)
            _InfoRowData(Icons.corporate_fare, 'Корпоративная', user.emailCorporate),
          ...user.phones.map((p) => _InfoRowData(Icons.phone_outlined, 'Телефон', p)),
        ]),
        const SizedBox(height: 14),

        // Passes
        passesAsync.when(
          loading: () => _Skeleton(height: 80),
          error: (_, __) => const SizedBox.shrink(),
          data: (d) => d.isEmpty ? const SizedBox.shrink() : _PassCard(data: d),
        ),
        const SizedBox(height: 14),

        // Privacy toggles
        _PrivacyCard(privacy: privacy, ref: ref),
        const SizedBox(height: 14),

        // Cache section
        const _SectionLabel('Хранилище'),
        const SizedBox(height: 10),
        const _CacheCard(),
        const SizedBox(height: 14),

        // Logout
        OutlinedButton.icon(
          onPressed: () => _logout(context, ref),
          icon: const Icon(Icons.logout, size: 18),
          label: const Text('Выйти из аккаунта'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.error,
            side: BorderSide(color: AppTheme.error.withOpacity(0.4)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        const Center(child: Text('MSAL+ v2.0  •  Неофициальный клиент',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11))),
        const SizedBox(height: 30),
      ],
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: const Text('Выйти?', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('Вы будете перенаправлены на экран входа.',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true),
              child: Text('Выйти', style: TextStyle(color: AppTheme.error))),
        ],
      ),
    );
    if (ok == true) {
      // 1. Auth service clears tokens, SQLite caches, mail session, myprepod cache
      await ref.read(authServiceProvider).logout();

      // 2. Invalidate ALL Riverpod data providers so new account gets fresh data
      _invalidateAllProviders(ref);
    }
  }

  /// Invalidates all cached Riverpod providers across the app.
  /// This forces fresh data fetch when a new user logs in.
  void _invalidateAllProviders(WidgetRef ref) {
    // Profile
    ref.invalidate(_groupmatesProvider);
    ref.invalidate(_passesProvider);
    ref.invalidate(_privacyProvider);
    // Grades / Progress
    ref.invalidate(gradesProvider);
    // Dashboard
    ref.invalidate(todayScheduleProvider);
    ref.invalidate(progressWithLessonsProvider);
    ref.invalidate(studentInfoProvider);
    // Session
    ref.invalidate(sessionProvider);
    // Shell index (reset to home)
    ref.invalidate(shellIndexProvider);
    print('[LOGOUT] All Riverpod providers invalidated');
  }
}

// ── Privacy Card ───────────────────────────────────────────────────────────────

class _PrivacyCard extends ConsumerWidget {
  final ({bool email, bool photo, bool mobile}) privacy;
  final WidgetRef ref;
  const _PrivacyCard({required this.privacy, required this.ref});

  Future<void> _toggle(String field) async {
    final cur = ref.read(_privacyProvider);
    late ({bool email, bool photo, bool mobile}) next;

    switch (field) {
      case 'email':  next = (email: !cur.email, photo: cur.photo, mobile: cur.mobile); break;
      case 'photo':  next = (email: cur.email, photo: !cur.photo, mobile: cur.mobile); break;
      case 'mobile': next = (email: cur.email, photo: cur.photo, mobile: !cur.mobile); break;
      default: return;
    }

    ref.read(_privacyProvider.notifier).state = next;

    // Sync to server
    await ref.read(apiServiceProvider).updatePrivacySettings(
      showEmail: next.email,
      showPhoto: next.photo,
      showMobile: next.mobile,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 10, left: 2),
          child: Text('Видимость для одногруппников',
              style: TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
        Container(
          decoration: BoxDecoration(
              color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.divider)),
          child: Column(children: [
            _Toggle(icon: Icons.photo_outlined, label: 'Фотография профиля',
                subtitle: 'Одногруппники видят твоё фото',
                value: privacy.photo, onChanged: () => _toggle('photo')),
            const Divider(height: 1, color: AppTheme.divider, indent: 48),
            _Toggle(icon: Icons.mail_outline, label: 'Email адрес',
                subtitle: 'Одногруппники видят твой email',
                value: privacy.email, onChanged: () => _toggle('email')),
            const Divider(height: 1, color: AppTheme.divider, indent: 48),
            _Toggle(icon: Icons.phone_outlined, label: 'Номер телефона',
                subtitle: 'Одногруппники видят твой номер',
                value: privacy.mobile, onChanged: () => _toggle('mobile')),
          ]),
        ),
      ],
    );
  }
}

class _Toggle extends ConsumerWidget {
  final IconData icon; final String label; final String subtitle;
  final bool value; final VoidCallback onChanged;
  const _Toggle({required this.icon, required this.label, required this.subtitle,
      required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    child: Row(children: [
      Icon(icon, size: 20, color: value ? AppTheme.accent : AppTheme.textMuted),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(
            color: value ? AppTheme.textPrimary : AppTheme.textSecondary,
            fontSize: 14, fontWeight: FontWeight.w500)),
        Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
      ])),
      Switch(value: value, onChanged: (_) => onChanged(),
          activeColor: AppTheme.accent,
          activeTrackColor: AppTheme.accent.withOpacity(0.3),
          inactiveThumbColor: AppTheme.textMuted,
          inactiveTrackColor: AppTheme.bgSurface),
    ]),
  );
}

// ── Group Tab ──────────────────────────────────────────────────────────────────

class _GroupTab extends ConsumerWidget {
  const _GroupTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(_groupmatesProvider);
    final privacy = ref.watch(_privacyProvider);

    return groupAsync.when(
      loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      error: (e, _) => Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.group_off_outlined, color: AppTheme.textMuted, size: 48),
          const SizedBox(height: 12),
          const Text('Не удалось загрузить список группы',
              style: TextStyle(color: AppTheme.textSecondary)),
          const SizedBox(height: 8),
          Text(e.toString(), style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
              textAlign: TextAlign.center, maxLines: 3),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: () => ref.refresh(_groupmatesProvider),
              child: const Text('Повторить')),
        ],
      )),
      data: (members) => members.isEmpty
          ? const Center(child: Text('Список группы пуст',
              style: TextStyle(color: AppTheme.textSecondary)))
          : RefreshIndicator(
              color: AppTheme.accent,
              backgroundColor: AppTheme.bgCard,
              onRefresh: () async => ref.refresh(_groupmatesProvider),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: members.length,
                itemBuilder: (_, i) => _GroupmateTile(
                  member: members[i],
                  showPhoto: privacy.photo,
                  showEmail: privacy.email,
                  showPhone: privacy.mobile,
                ),
              ),
            ),
    );
  }
}

class _GroupmateTile extends ConsumerWidget {
  final UserModel member;
  final bool showPhoto, showEmail, showPhone;
  const _GroupmateTile({required this.member, required this.showPhoto,
      required this.showEmail, required this.showPhone});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: AppTheme.bgCard, borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.divider)),
      child: Row(children: [
        _MemberAvatar(member: member, showPhoto: showPhoto),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(member.name,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14, fontWeight: FontWeight.w500)),
          if (showEmail && member.email.isNotEmpty) ...[
            const SizedBox(height: 3),
            Row(children: [
              const Icon(Icons.mail_outline, size: 12, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Expanded(child: Text(member.email,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                  overflow: TextOverflow.ellipsis)),
            ]),
          ],
          if (showPhone && member.phones.isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(children: [
              const Icon(Icons.phone_outlined, size: 12, color: AppTheme.textMuted),
              const SizedBox(width: 4),
              Text(member.phones.first,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ]),
          ],
        ])),
        if (member.emailCorporate.isNotEmpty || member.email.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.mail_outline_rounded, color: AppTheme.accent, size: 20),
            tooltip: 'Написать письмо',
            onPressed: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ComposeScreen(
                initialTo: member.emailCorporate.isNotEmpty ? member.emailCorporate : member.email,
              ),
            )),
          ),
      ]),
    );
  }
}

class _MemberAvatar extends ConsumerWidget {
  final UserModel member;
  final bool showPhoto;
  const _MemberAvatar({required this.member, required this.showPhoto});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final url = member.photoUrl;
    if (showPhoto && url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: CachedNetworkImage(
          imageUrl: url,
          width: 44, height: 44, fit: BoxFit.cover,
          placeholder: (_, __) => _Initials(member: member),
          errorWidget: (_, __, ___) => _Initials(member: member),
        ),
      );
    }
    return _Initials(member: member);
  }
}

class _Initials extends ConsumerWidget {
  final UserModel member;
  const _Initials({required this.member});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hue = member.name.codeUnits.fold(0, (a, b) => a + b) % 360;
    final color = HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.45).toColor();
    return Container(
      width: 44, height: 44,
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(22)),
      alignment: Alignment.center,
      child: Text(member.initials,
          style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Hero ───────────────────────────────────────────────────────────────────────

class _ProfileHero extends ConsumerWidget {
  final UserModel user;
  const _ProfileHero({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            colors: [Color(0xFF1A1030), AppTheme.bgDark],
            begin: Alignment.topCenter, end: Alignment.bottomCenter),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: OverflowBox(
        maxHeight: double.infinity,
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          const SizedBox(height: 12),
          _buildAvatar(),
          const SizedBox(height: 8),
          Text(user.name,
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(user.login,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _buildAvatar() {
    final url = user.photoUrl;
    if (url != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: CachedNetworkImage(
          imageUrl: url, width: 68, height: 68, fit: BoxFit.cover,
          placeholder: (_, __) => _gradientAvatar(),
          errorWidget: (_, __, ___) => _gradientAvatar(),
        ),
      );
    }
    return _gradientAvatar();
  }

  Widget _gradientAvatar() => Container(
    width: 68, height: 68,
    decoration: BoxDecoration(
      gradient: AppTheme.accentGradient,
      shape: BoxShape.circle,
      boxShadow: [BoxShadow(color: AppTheme.accent.withOpacity(0.4), blurRadius: 20, spreadRadius: 2)],
    ),
    alignment: Alignment.center,
    child: Text(user.initials,
        style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
  );
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _InfoRowData {
  final IconData icon; final String label; final String value;
  const _InfoRowData(this.icon, this.label, this.value);
}

class _InfoCard extends ConsumerWidget {
  final String title; final List<_InfoRowData> rows;
  const _InfoCard({required this.title, required this.rows});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 10, left: 2),
        child: Text(title,
            style: const TextStyle(color: AppTheme.accent, fontSize: 12, fontWeight: FontWeight.w600)),
      ),
      Container(
        decoration: BoxDecoration(
            color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.divider)),
        child: Column(
          children: rows.asMap().entries.map((e) => Column(children: [
            _InfoRow(e.value),
            if (e.key < rows.length - 1)
              const Divider(height: 1, color: AppTheme.divider, indent: 48),
          ])).toList(),
        ),
      ),
    ],
  );
}

class _InfoRow extends ConsumerWidget {
  final _InfoRowData data;
  const _InfoRow(this.data);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(data.icon, size: 18, color: AppTheme.accent),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(data.label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(data.value.isEmpty ? '—' : data.value,
            style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13)),
      ])),
    ]),
  );
}

class _PassCard extends ConsumerWidget {
  final Map<String, dynamic> data;
  const _PassCard({required this.data});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passNum = data['passNumber'] ?? data['pass'] ?? data['number'] ?? '—';
    final status = data['status'] ?? '';
    return _InfoCard(title: 'Электронный пропуск', rows: [
      _InfoRowData(Icons.credit_card_outlined, 'Номер пропуска', passNum.toString()),
      if (status.isNotEmpty) _InfoRowData(Icons.verified_outlined, 'Статус', status.toString()),
    ]);
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends ConsumerWidget {
  final String text;
  const _SectionLabel(this.text);
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.only(left: 2, bottom: 0),
    child: Text(text,
        style: const TextStyle(color: AppTheme.accent,
            fontSize: 12, fontWeight: FontWeight.w600)),
  );
}

// ── Cache entry data class ────────────────────────────────────────────────────

class _CacheEntry {
  final String label;
  final int rows, bytes;
  const _CacheEntry({required this.label, required this.rows, required this.bytes});
}

// ── Google Drive Integration Card ─────────────────────────────────────────────

// ── Cache Card ────────────────────────────────────────────────────────────────

class _CacheCard extends ConsumerStatefulWidget {
  const _CacheCard();
  @override
  ConsumerState<_CacheCard> createState() => _CacheCardState();
}

class _CacheCardState extends ConsumerState<_CacheCard> {
  bool _clearing = false;
  bool _expanded = false;
  // Per-table stats: {label: {rows, bytes}}
  List<_CacheEntry> _entries = [];
  int _totalBytes = 0;
  int _dbFileBytes = 0;

  @override
  void initState() {
    super.initState();
    _calcSize();
  }

  String _fmt(int bytes) {
    if (bytes <= 0)          return '0 Б';
    if (bytes < 1024)        return '$bytes Б';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} КБ';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  Future<void> _calcSize() async {
    try {
      final db = ref.read(localDbServiceProvider).db;

      // Table definitions: {sqlName, friendlyLabel}
      const tables = [
        ('schedule_cache',    'Расписание'),
        ('progress_cache',    'Успеваемость'),
        ('homework',          'Домашние задания'),
        ('lecture_attendance','Явки на лекции'),
        ('manual_attendance', 'Ручные отметки'),
        ('debt_deadlines',    'Дедлайны долгов'),
        ('progress_notes',    'Заметки'),
      ];

      final entries = <_CacheEntry>[];
      int total = 0;

      for (final (table, label) in tables) {
        try {
          final r = await db.rawQuery('SELECT COUNT(*) as c FROM $table');
          final rows = (r.first['c'] as int?) ?? 0;
          if (rows == 0) continue;
          // Estimate size: get average row size via page_count * page_size
          final pageRes = await db.rawQuery(
              "SELECT SUM(payload) as sz FROM dbstat WHERE name = ?", [table]);
          final bytes = (pageRes.first['sz'] as int?) ?? rows * 256; // fallback ~256B/row
          entries.add(_CacheEntry(label: label, rows: rows, bytes: bytes));
          total += bytes;
        } catch (_) {}
      }

      // Actual DB file size
      int dbFile = 0;
      try {
        final dbPath = await getDatabasesPath();
        final f = File(p.join(dbPath, 'msal_plus_v2.db'));
        if (await f.exists()) dbFile = await f.length();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _entries     = entries;
          _totalBytes  = total > 0 ? total : dbFile;
          _dbFileBytes = dbFile;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _entries = []; _totalBytes = 0; });
    }
  }

  Future<void> _clear() async {
    setState(() => _clearing = true);
    try {
      final db = ref.read(localDbServiceProvider).db;
      for (final t in ['schedule_cache', 'progress_cache']) {
        try { await db.delete(t); } catch (_) {}
      }
      await _calcSize();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Кэш расписания и оценок очищен')),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalLabel = _dbFileBytes > 0
        ? _fmt(_dbFileBytes)
        : (_totalBytes > 0 ? _fmt(_totalBytes) : '…');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.divider),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header row
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accent.withOpacity(0.2)),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.storage_outlined,
              color: AppTheme.accent, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Кэш приложения',
              style: TextStyle(color: AppTheme.textPrimary,
                  fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(totalLabel,
              style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ])),
        const SizedBox(width: 8),
        _clearing
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppTheme.accent))
            : GestureDetector(
                onTap: _clear,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.error.withOpacity(0.3)),
                  ),
                  child: const Text('Очистить',
                      style: TextStyle(color: AppTheme.error,
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
        ]),      // closes Row(children: [
      ]),        // closes Column(children: [
    );
  }
}

class _Skeleton extends ConsumerWidget {
  final double height;
  const _Skeleton({required this.height});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Container(
    height: height,
    decoration: BoxDecoration(color: AppTheme.bgCard, borderRadius: BorderRadius.circular(14)),
  );
}


// ── NVIDIA NIM Integration Card ───────────────────────────────────────────────

class _NimIntegrationCard extends ConsumerStatefulWidget {
  const _NimIntegrationCard();
  @override
  ConsumerState<_NimIntegrationCard> createState() => _NimIntegrationCardState();
}

class _NimIntegrationCardState extends ConsumerState<_NimIntegrationCard> {
  bool _saving = false;

  Future<void> _openKeyDialog() async {
    final ctrl = TextEditingController(
        text: ref.read(aiServiceProvider).hasApiKey ? ref.read(aiServiceProvider).apiKey : '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => _NimKeyDialog(controller: ctrl),
    );
    if (result == null) return; // dismissed
    setState(() => _saving = true);
    try {
      if (result.isEmpty) {
        await ref.read(aiServiceProvider).clearApiKey();
      } else {
        await ref.read(aiServiceProvider).saveApiKey(result);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasKey = ref.read(aiServiceProvider).hasApiKey;
    return _IntegrationCard(
      icon: Icons.auto_awesome_outlined,
      iconColor: const Color(0xFF76B900), // NVIDIA green
      title: 'NVIDIA NIM',
      subtitle: hasKey
          ? ref.read(aiServiceProvider).maskedKey
          : 'Ключ для AI-ассистента',
      statusLabel: hasKey ? 'Активно' : 'Ключ не задан',
      connected: hasKey,
      extraInfo: hasKey ? 'meta/llama-3.1-70b-instruct' : null,
      actionLabel: hasKey ? 'Изменить ключ' : 'Добавить ключ',
      actionColor: AppTheme.accent,
      loading: _saving,
      onAction: _openKeyDialog,
    );
  }
}

// ── NIM Key Dialog ────────────────────────────────────────────────────────────

class _NimKeyDialog extends ConsumerStatefulWidget {
  final TextEditingController controller;
  const _NimKeyDialog({required this.controller});
  @override
  ConsumerState<_NimKeyDialog> createState() => _NimKeyDialogState();
}

class _NimKeyDialogState extends ConsumerState<_NimKeyDialog> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Row(children: [
        Icon(Icons.auto_awesome_outlined, color: Color(0xFF76B900), size: 20),
        SizedBox(width: 8),
        Text('NVIDIA NIM API Key',
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text(
          'Получи бесплатный ключ на build.nvidia.com.\n'
          'Он хранится только локально на устройстве.',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.5),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: widget.controller,
          obscureText: _obscure,
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13,
              fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'nvapi-...',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            filled: true,
            fillColor: AppTheme.bgSurface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.divider)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppTheme.accent)),
            suffixIcon: IconButton(
              icon: Icon(_obscure ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
                  color: AppTheme.textMuted, size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // Link hint
        GestureDetector(
          onTap: () {
            // Could open URL launcher, but for now just a label
          },
          child: const Text('→ build.nvidia.com',
              style: TextStyle(color: AppTheme.accent, fontSize: 12,
                  decoration: TextDecoration.underline)),
        ),
      ]),
      actions: [
        if (ref.read(aiServiceProvider).hasApiKey)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: const Text('Удалить ключ',
                style: TextStyle(color: AppTheme.error)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Отмена',
              style: TextStyle(color: AppTheme.textMuted)),
        ),
        ElevatedButton(
          onPressed: () => Navigator.pop(context, widget.controller.text.trim()),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
          child: const Text('Сохранить',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}

// ── Generic Integration Card ──────────────────────────────────────────────────

class _IntegrationCard extends ConsumerWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String statusLabel;
  final bool connected;
  final String? extraInfo;
  final String actionLabel;
  final Color actionColor;
  final bool loading;
  final VoidCallback onAction;
  final VoidCallback? onTap;

  const _IntegrationCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.statusLabel,
    required this.connected,
    this.extraInfo,
    required this.actionLabel,
    required this.actionColor,
    required this.loading,
    required this.onAction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: connected
                ? iconColor.withOpacity(0.3)
                : AppTheme.divider,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          // Icon
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: iconColor.withOpacity(0.2)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          // Text info — Flexible prevents overflow
          Flexible(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(child: Text(title,
                    style: const TextStyle(color: AppTheme.textPrimary,
                        fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: (connected ? Colors.green : AppTheme.textMuted).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                        color: connected ? Colors.green : AppTheme.textMuted,
                        fontSize: 9, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: const TextStyle(color: AppTheme.textMuted, fontSize: 10),
                  overflow: TextOverflow.ellipsis, maxLines: 1),
              if (extraInfo != null) ...[
                const SizedBox(height: 1),
                Text(extraInfo!,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 9),
                    overflow: TextOverflow.ellipsis),
              ],
            ],
          )),
          const SizedBox(width: 6),
          // Action button — constrained width
          loading
              ? const SizedBox(width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2,
                      color: AppTheme.accent))
              : GestureDetector(
                  onTap: onAction,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 110),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: actionColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: actionColor.withOpacity(0.3)),
                    ),
                    child: Text(actionLabel,
                        style: TextStyle(color: actionColor,
                            fontSize: 11, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        textAlign: TextAlign.center),
                  ),
                ),
        ]),       // Row children: [...]
      ),          // Container child: Row(...)
    );            // return Container(...)
  }               // build()
}                 // class _IntegrationCard
