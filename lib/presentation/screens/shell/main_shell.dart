// lib/presentation/screens/shell/main_shell.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dashboard/dashboard_screen.dart';
import '../schedule/schedule_screen.dart';
import '../grades/grades_screen.dart';
import '../notes/notes_screen.dart';
import '../ai/ai_screen.dart';
import '../mail/mail_screen.dart';
import '../consultations/consultations_screen.dart';
import '../profile/profile_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/navigation/app_drawer.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/providers/scaffold_provider.dart';

final shellIndexProvider = StateProvider<int>((ref) => 0);

class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  static const _screens = [
    DashboardScreen(),
    ScheduleScreen(),
    GradesScreen(),
    NotesScreen(),
    AiScreen(),
    MailScreen(),
    ConsultationsScreen(),
    ProfileScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(shellIndexProvider);
    final scaffoldKey = ref.watch(mainScaffoldKeyProvider);
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 800;

    if (isDesktop) {
      return Scaffold(
        key: scaffoldKey,
        body: Row(
          children: [
            SizedBox(
              width: 280,
              child: const AppDrawer(isPermanent: true),
            ),
            const VerticalDivider(width: 1, thickness: 1, color: AppTheme.divider),
            Expanded(
              child: IndexedStack(index: index, children: _screens),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: scaffoldKey,
      drawer: const AppDrawer(),
      body: IndexedStack(index: index, children: _screens),
    );
  }
}
