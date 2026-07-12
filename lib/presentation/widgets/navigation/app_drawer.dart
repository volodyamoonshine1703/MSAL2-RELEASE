import '../../../core/providers.dart';
// lib/presentation/widgets/navigation/app_drawer.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/auth_service.dart';
import '../../screens/shell/main_shell.dart';

class AppDrawer extends ConsumerWidget {
  final bool isPermanent;
  const AppDrawer({super.key, this.isPermanent = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.read(authServiceProvider).currentUser;
    final currentIndex = ref.watch(shellIndexProvider);

    final content = Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          // Header (Profile Section)
          _buildHeader(context, ref, user),
          
          Divider(height: 1, color: Theme.of(context).dividerColor),
          
          // Navigation Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _DrawerItem(
                  icon: Icons.dashboard_outlined,
                  selectedIcon: Icons.dashboard_rounded,
                  label: 'Главная',
                  isSelected: currentIndex == 0,
                  onTap: () => _onSelect(context, ref, 0),
                ),
                _DrawerItem(
                  icon: Icons.calendar_today_outlined,
                  selectedIcon: Icons.calendar_today_rounded,
                  label: 'Расписание',
                  isSelected: currentIndex == 1,
                  onTap: () => _onSelect(context, ref, 1),
                ),
                _DrawerItem(
                  icon: Icons.bar_chart_outlined,
                  selectedIcon: Icons.bar_chart_rounded,
                  label: 'Оценки',
                  isSelected: currentIndex == 2,
                  onTap: () => _onSelect(context, ref, 2),
                ),
                _DrawerItem(
                  icon: Icons.sticky_note_2_outlined,
                  selectedIcon: Icons.sticky_note_2_rounded,
                  label: 'Заметки',
                  isSelected: currentIndex == 3,
                  onTap: () => _onSelect(context, ref, 3),
                ),
                _DrawerItem(
                  icon: Icons.auto_awesome_outlined,
                  selectedIcon: Icons.auto_awesome_rounded,
                  label: 'ИИ Помощник',
                  isSelected: currentIndex == 4,
                  onTap: () => _onSelect(context, ref, 4),
                ),
                _DrawerItem(
                  icon: Icons.mail_outline_rounded,
                  selectedIcon: Icons.mail_rounded,
                  label: 'Почта',
                  isSelected: currentIndex == 5,
                  onTap: () => _onSelect(context, ref, 5),
                ),
                if (user?.isInstitute == true)
                  _DrawerItem(
                    icon: Icons.group_outlined,
                    selectedIcon: Icons.group_rounded,
                    label: 'Консультации',
                    isSelected: currentIndex == 6,
                    onTap: () => _onSelect(context, ref, 6),
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1, color: Theme.of(context).dividerColor),
                ),
                _DrawerItem(
                  icon: Icons.person_outline_rounded,
                  selectedIcon: Icons.person_rounded,
                  label: 'Мой профиль',
                  isSelected: currentIndex == 7,
                  onTap: () => _onSelect(context, ref, 7),
                ),
                _DrawerItem(
                  icon: Icons.settings_outlined,
                  selectedIcon: Icons.settings_rounded,
                  label: 'Настройки',
                  isSelected: currentIndex == 8,
                  onTap: () => _onSelect(context, ref, 8),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (isPermanent) return content;

    return Drawer(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      child: content,
    );
  }

  Widget _buildHeader(BuildContext context, WidgetRef ref, dynamic user) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
      decoration: BoxDecoration(
        gradient: isDark 
          ? LinearGradient(
              colors: [AppTheme.bgCard, AppTheme.bgDark.withOpacity(0.8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : LinearGradient(
              colors: [AppTheme.accent.withOpacity(0.8), AppTheme.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
                child: CircleAvatar(
                  radius: 32,
                  backgroundColor: isDark ? AppTheme.accent.withOpacity(0.2) : Colors.white24,
                  backgroundImage: user?.photoUrl != null ? NetworkImage(user!.photoUrl!) : null,
                  child: user?.photoUrl == null
                      ? Text(
                          user?.initials ?? '?',
                          style: TextStyle(
                            color: isDark ? AppTheme.accent : Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            user?.name ?? 'Пользователь',
            style: TextStyle(
              color: isDark ? AppTheme.textPrimary : Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            user?.login ?? '',
            style: TextStyle(
              color: isDark ? AppTheme.textMuted : Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _onSelect(BuildContext context, WidgetRef ref, int index) {
    ref.read(shellIndexProvider.notifier).state = index;
    if (!isPermanent) {
      Navigator.pop(context); // Close drawer
    }
  }
}

class _DrawerItem extends ConsumerWidget {
  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.isSelected = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.accent.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                isSelected ? (selectedIcon ?? icon) : icon,
                color: isSelected ? AppTheme.accent : AppTheme.textSecondary,
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? AppTheme.accent : AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
