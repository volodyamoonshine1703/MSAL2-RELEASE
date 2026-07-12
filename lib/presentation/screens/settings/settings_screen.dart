import '../../../core/providers.dart';
// lib/presentation/screens/settings/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/scaffold_provider.dart';
import '../../../data/services/ai_service.dart';
import '../schedule/schedule_screen.dart' show calendarModeProvider;

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cs = theme.colorScheme;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            leading: IconButton(
              icon: Icon(Icons.menu_rounded, color: cs.onSurface.withOpacity(0.7)),
              onPressed: () =>
                  ref.read(mainScaffoldKeyProvider).currentState?.openDrawer(),
            ),
            title: Text('Настройки',
                style: TextStyle(
                    color: cs.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Schedule view mode ──────────────────────────────────
                _SectionLabel('Вид расписания', isDark: isDark, accent: cs.primary),
                const SizedBox(height: 10),
                _ScheduleViewCard(),
                const SizedBox(height: 24),

                // ── NVIDIA NIM ───────────────────────────────────────────
                _SectionLabel('Интеграции', isDark: isDark, accent: cs.primary),
                const SizedBox(height: 10),
                const _NimIntegrationCard(),
                const SizedBox(height: 24),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends ConsumerWidget {
  final String text;
  final bool isDark;
  final Color accent;
  const _SectionLabel(this.text, {required this.isDark, required this.accent});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(left: 2),
        child: Text(text,
            style: TextStyle(
                color: accent,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.3)),
      );
}

// ── Schedule view mode ────────────────────────────────────────────────────────

class _ScheduleViewCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCalendar = ref.watch(calendarModeProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? cs.surface : Colors.white;
    final divColor = isDark ? cs.outline.withOpacity(0.2) : Colors.grey.shade200;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: divColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Режим отображения',
              style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: _ViewModeBtn(
                icon: Icons.view_week_outlined,
                label: 'Неделя',
                selected: !isCalendar,
                accent: cs.primary,
                isDark: isDark,
                onTap: () =>
                    ref.read(calendarModeProvider.notifier).state = false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ViewModeBtn(
                icon: Icons.calendar_month_outlined,
                label: 'Месяц',
                selected: isCalendar,
                accent: cs.primary,
                isDark: isDark,
                onTap: () =>
                    ref.read(calendarModeProvider.notifier).state = true,
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _ViewModeBtn extends ConsumerWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final bool isDark;
  final VoidCallback onTap;

  const _ViewModeBtn({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? accent.withOpacity(0.15)
                : (isDark ? AppTheme.bgSurface : const Color(0xFFF5F5F7)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  color: selected ? accent : AppTheme.textMuted, size: 24),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                    color: selected ? accent : AppTheme.textMuted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  )),
            ],
          ),
        ),
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
    if (result == null) return;
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;
    final cardBg = isDark ? cs.surface : Colors.white;
    final divColor = isDark ? cs.outline.withOpacity(0.2) : Colors.grey.shade200;
    const nvidiaGreen = Color(0xFF76B900);

    return GestureDetector(
      onTap: _openKeyDialog,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasKey ? nvidiaGreen.withOpacity(0.3) : divColor,
          ),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: nvidiaGreen.withOpacity(0.1),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: nvidiaGreen.withOpacity(0.2)),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.auto_awesome_outlined,
                color: nvidiaGreen, size: 20),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text('NVIDIA NIM',
                        style: TextStyle(
                            color: cs.onSurface,
                            fontSize: 13,
                            fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: (hasKey ? Colors.green : AppTheme.textMuted)
                          .withOpacity(0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(hasKey ? 'Активно' : 'Ключ не задан',
                        style: TextStyle(
                          color: hasKey ? Colors.green : AppTheme.textMuted,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(
                  hasKey
                      ? ref.read(aiServiceProvider).maskedKey
                      : 'Ключ для AI-ассистента',
                  style: TextStyle(
                      color: isDark ? AppTheme.textMuted : Colors.black45,
                      fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                if (hasKey) ...[
                  const SizedBox(height: 1),
                  Text('meta/llama-3.1-70b-instruct',
                      style: TextStyle(
                          color: isDark
                              ? AppTheme.textSecondary
                              : Colors.black54,
                          fontSize: 9),
                      overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          _saving
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: cs.primary))
              : Container(
                  constraints: const BoxConstraints(maxWidth: 110),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(7),
                    border: Border.all(color: cs.primary.withOpacity(0.3)),
                  ),
                  child: Text(
                    hasKey ? 'Изменить ключ' : 'Добавить ключ',
                    style: TextStyle(
                        color: cs.primary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    textAlign: TextAlign.center,
                  ),
                ),
        ]),
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? AppTheme.bgCard : Colors.white,
      title: const Row(children: [
        Icon(Icons.auto_awesome_outlined, color: Color(0xFF76B900), size: 20),
        SizedBox(width: 8),
        Text('NVIDIA NIM API Key', style: TextStyle(fontSize: 16)),
      ]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          'Получи бесплатный ключ на build.nvidia.com.\n'
          'Он хранится только локально на устройстве.',
          style: TextStyle(
              color: isDark ? AppTheme.textMuted : Colors.black45,
              fontSize: 12,
              height: 1.5),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: widget.controller,
          obscureText: _obscure,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'nvapi-...',
            suffixIcon: IconButton(
              icon: Icon(
                  _obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () {},
          child: Text('→ build.nvidia.com',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  decoration: TextDecoration.underline)),
        ),
      ]),
      actions: [
        if (ref.read(aiServiceProvider).hasApiKey)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text('Удалить ключ',
                style: TextStyle(color: AppTheme.error)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text('Отмена',
              style: TextStyle(
                  color: isDark ? AppTheme.textMuted : Colors.black45)),
        ),
        ElevatedButton(
          onPressed: () =>
              Navigator.pop(context, widget.controller.text.trim()),
          child: const Text('Сохранить',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }
}
