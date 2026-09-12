# 📱 РОУТИНГ И АРХИТЕКТУРА ВЕБ-ВЕРСИИ MSAL+

## 🎯 Цель
Создать единую систему навигации для:
- **Mobile** (Android/iOS) — Drawer + Bottom Navigation
- **Desktop** (Web/Windows/Linux) — Permanent Sidebar
- **Telegram Mini App** — Web-версия с интеграцией в TG API

---

## 📁 Текущая структура экранов

```
lib/presentation/screens/
├── login/              → Авторизация
├── shell/              → Главная оболочка (MainShell)
├── dashboard/          → Главная страница
├── schedule/           → Расписание
├── grades/             → Оценки
│   ├── grades_screen.dart
│   ├── discipline_detail_screen.dart
│   ├── admission_manager_screen.dart
│   └── debt_manager_screen.dart
├── notes/              → Заметки
├── ai/                 → ИИ Помощник
├── mail/               → Почта
│   ├── mail_screen.dart
│   ├── mail_detail_screen.dart
│   └── compose_screen.dart
├── consultations/      → Консультации (для преподавателей)
├── homework/           → Домашние задания
├── plan/               → План восстановления
├── profile/            → Профиль пользователя
└── settings/           → Настройки
```

---

## 🔄 Проблемы текущей реализации

### ❌ MainShell ( IndexedStack )
```dart
// Сейчас все экраны загружаются сразу в памяти
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
```

**Проблемы:**
1. Нет URL-навигации (невозможно открыть прямую ссылку на страницу)
2. Все экраны в памяти одновременно
3. Нет истории переходов (кнопка "Назад" в браузере не работает)
4. Нет глубоких ссылок (deep links) для Telegram
5. Невозможно обновить страницу на конкретном экране

---

## ✅ Новая архитектура роутинга

### 📦 go_router для декларативной навигации

**Пакет:** `go_router: ^14.0.0`

#### Структура роутов:

```dart
final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    // ── Публичные роуты ──────────────────────────────────────
    GoRoute(
      path: '/login',
      name: 'login',
      builder: (_, __) => LoginScreen(),
    ),
    
    // ── Защищённые роуты (требуют авторизации) ───────────────
    ShellRoute(
      builder: (_, __, child) => MainShell(child: child),
      routes: [
        GoRoute(
          path: '/',
          redirect: (_, __) => '/dashboard',
        ),
        GoRoute(
          path: '/dashboard',
          name: 'dashboard',
          builder: (_, __) => DashboardScreen(),
        ),
        GoRoute(
          path: '/schedule',
          name: 'schedule',
          builder: (_, __) => ScheduleScreen(),
          routes: [
            GoRoute(
              path: ':date',
              builder: (_, state) => ScheduleDetailScreen(date: state.pathParameters['date']!),
            ),
          ],
        ),
        GoRoute(
          path: '/grades',
          name: 'grades',
          builder: (_, __) => GradesScreen(),
          routes: [
            GoRoute(
              path: ':disciplineId',
              name: 'discipline',
              builder: (_, state) => DisciplineDetailScreen(disciplineId: state.pathParameters['disciplineId']!),
              routes: [
                GoRoute(
                  path: 'admission',
                  name: 'admission',
                  builder: (_, __) => AdmissionManagerScreen(),
                ),
                GoRoute(
                  path: 'debt',
                  name: 'debt',
                  builder: (_, __) => DebtManagerScreen(),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/notes',
          name: 'notes',
          builder: (_, __) => NotesScreen(),
        ),
        GoRoute(
          path: '/ai',
          name: 'ai',
          builder: (_, __) => AiScreen(),
        ),
        GoRoute(
          path: '/mail',
          name: 'mail',
          builder: (_, __) => MailScreen(),
          routes: [
            GoRoute(
              path: ':messageId',
              name: 'mailDetail',
              builder: (_, state) => MailDetailScreen(messageId: state.pathParameters['messageId']!),
            ),
            GoRoute(
              path: 'compose',
              name: 'composeMail',
              builder: (_, __) => ComposeScreen(),
            ),
          ],
        ),
        GoRoute(
          path: '/consultations',
          name: 'consultations',
          builder: (_, __) => ConsultationsScreen(),
        ),
        GoRoute(
          path: '/homework',
          name: 'homework',
          builder: (_, __) => HomeworkScreen(),
        ),
        GoRoute(
          path: '/plan',
          name: 'plan',
          builder: (_, __) => RecoveryPlanScreen(),
        ),
        GoRoute(
          path: '/profile',
          name: 'profile',
          builder: (_, __) => ProfileScreen(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (_, __) => SettingsScreen(),
        ),
      ],
    ),
  ],
);
```

---

## 🌐 Поддержка платформ

### 1️⃣ Mobile (Android/iOS)
```dart
// Bottom Navigation Bar + Drawer
MainShell {
  Scaffold(
    body: child, // Экран из роута
    drawer: AppDrawer(),
    bottomNavigationBar: BottomNavBar(currentPath: state.location),
  )
}
```

### 2️⃣ Desktop (Web/Windows/Linux)
```dart
// Permanent Sidebar
MainShell {
  Scaffold(
    body: Row(
      children: [
        AppDrawer(isPermanent: true),
        VerticalDivider(),
        Expanded(child: child),
      ],
    ),
  )
}
```

### 3️⃣ Telegram Mini App
```dart
// Интеграция с TG API
- Используем Telegram.WebApp.ready()
- Цветовая схема через Telegram.WebApp.themeParams
- BackButton через Telegram.WebApp.BackButton
- Haptic feedback через Telegram.WebApp.HapticFeedback
- Deep links: https://t.me/your_bot/msal_plus?startapp=/grades
```

---

## 🔐 Protected Routes (Авторизация)

```dart
final authServiceProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

class AuthNotifier extends StateNotifier<AuthState> {
  AuthNotifier() : super(AuthState.initial());

  Future<void> init() async {
    // Проверка сохранённых credentials
    final hasSession = await _checkSession();
    state = state.copyWith(isAuthenticated: hasSession);
  }

  Future<bool> _checkSession() async {
    // Логика проверки сессии
  }
}

// Redirect guard
final _router = GoRouter(
  redirect: (context, state) {
    final isAuthenticated = container.read(authServiceProvider).isAuthenticated;
    final isLoggingIn = state.matchedLocation == '/login';

    if (!isAuthenticated && !isLoggingIn) {
      return '/login';
    }

    if (isAuthenticated && isLoggingIn) {
      return '/dashboard';
    }

    return null;
  },
);
```

---

## 🚀 Deep Links для Telegram

### Примеры ссылок:
```
# Открыть расписание на сегодня
https://t.me/msal_bot/app?startapp=/schedule/2025-09-12

# Открыть оценки по предмету
https://t.me/msal_bot/app?startapp=/grades/12345

# Открыть письмо
https://t.me/msal_bot/app?startapp=/mail/msg_67890

# Открыть ИИ помощника с предзаполненным запросом
https://t.me/msal_bot/app?startapp=/ai?query=расписание
```

### Обработка deep links:
```dart
import 'package:telegram_web_app/telegram_web_app.dart';

class TelegramService {
  final tg = TelegramWebApp();

  void initDeepLinks() {
    tg.onMainButtonPressed.listen((data) {
      if (data != null) {
        // data = "/grades/12345"
        context.go(data);
      }
    });
  }

  String getStartParam() {
    return tg.initDataUnsafe?.startParam ?? '';
  }
}
```

---

## 🎨 Адаптивный MainShell

```dart
class MainShell extends ConsumerWidget {
  final Widget child;
  const MainShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 1024;
    final isTablet = width > 600 && width <= 1024;
    final location = GoRouterState.of(context).location;

    if (isDesktop) {
      return _DesktopLayout(child: child, currentPath: location);
    } else if (isTablet) {
      return _TabletLayout(child: child, currentPath: location);
    } else {
      return _MobileLayout(child: child, currentPath: location);
    }
  }
}

class _DesktopLayout extends StatelessWidget {
  final Widget child;
  final String currentPath;
  const _DesktopLayout({required this.child, required this.currentPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          SizedBox(
            width: 280,
            child: AppDrawer(isPermanent: true, currentPath: currentPath),
          ),
          VerticalDivider(width: 1, thickness: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  final Widget child;
  final String currentPath;
  const _MobileLayout({required this.child, required this.currentPath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: AppDrawer(currentPath: currentPath),
      body: child,
      bottomNavigationBar: BottomNavBar(currentPath: currentPath),
    );
  }
}
```

---

## 📊 Bottom Navigation Bar (Mobile)

```dart
class BottomNavBar extends StatelessWidget {
  final String currentPath;
  const BottomNavBar({required this.currentPath});

  static const _quickAccess = [
    {'path': '/dashboard', 'icon': Icons.dashboard, 'label': 'Главная'},
    {'path': '/schedule', 'icon': Icons.calendar_today, 'label': 'Расписание'},
    {'path': '/grades', 'icon': Icons.bar_chart, 'label': 'Оценки'},
    {'path': '/mail', 'icon': Icons.mail, 'label': 'Почта'},
    {'path': '/ai', 'icon': Icons.auto_awesome, 'label': 'ИИ'},
  ];

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: _quickAccess.indexWhere((item) => 
        currentPath.startsWith(item['path'] as String)
      ),
      onDestinationSelected: (index) {
        context.go(_quickAccess[index]['path'] as String);
      },
      destinations: _quickAccess.map((item) => NavigationDestination(
        icon: Icon(item['icon'] as IconData),
        label: item['label'] as String,
      )).toList(),
    );
  }
}
```

---

## 🛠 Миграция: План действий

### Этап 1: Установка зависимостей
```yaml
dependencies:
  go_router: ^14.0.0
  telegram_web_app: ^0.1.0 # Для TG Mini App
```

### Этап 2: Создание роутера
- [ ] Создать `/lib/core/router/app_router.dart`
- [ ] Определить все роуты
- [ ] Добавить guards для авторизации

### Этап 3: Рефакторинг MainShell
- [ ] Превратить MainShell в ShellRoute
- [ ] Удалить IndexedStack
- [ ] Добавить адаптивные лейауты

### Этап 4: Интеграция Telegram
- [ ] Добавить обработку initData
- [ ] Настроить deep links
- [ ] Интегрировать TG theme params

### Этап 5: Тестирование
- [ ] Проверить навигацию на mobile
- [ ] Проверить навигацию на desktop
- [ ] Проверить deep links
- [ ] Проверить работу в Telegram Mini App

---

## 📝 Примечания

### URL Strategy для Web
Для корректной работы роутинга в вебе нужно настроить сервер:

**Firebase Hosting:**
```json
{
  "hosting": {
    "rewrites": [
      { "source": "**", "destination": "/index.html" }
    ]
  }
}
```

**Nginx:**
```nginx
location / {
  try_files $uri $uri/ /index.html;
}
```

### Telegram Mini App Requirements
1. HTTPS обязательно
2. Valid SSL сертификат
3. Корректный manifest.json
4. Обработка Telegram.WebApp.ready()

---

## 🎯 Итоговая структура файлов

```
lib/
├── main.dart
├── app.dart
├── core/
│   ├── router/
│   │   ├── app_router.dart       # Конфигурация go_router
│   │   ├── routes.dart           # Определение роутов
│   │   └── guards.dart           # Auth guards
│   ├── providers.dart
│   └── ...
├── presentation/
│   ├── screens/
│   │   └── ... (без изменений)
│   ├── shells/
│   │   ├── main_shell.dart       # Адаптивная оболочка
│   │   ├── desktop_shell.dart
│   │   ├── mobile_shell.dart
│   │   └── telegram_shell.dart   # Специфика TG Mini App
│   └── widgets/
│       └── navigation/
│           ├── app_drawer.dart
│           └── bottom_nav_bar.dart
└── ...
```
