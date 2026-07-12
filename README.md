# MSAL+

Неофициальный альтернативный клиент для личного кабинета МГЮА ([lk.msal.ru](https://lk.msal.ru)).

## Возможности

- 📅 Расписание занятий (МЭШ-стиль)
- 📊 Оценки и успеваемость
- 📝 Домашние задания с дедлайнами и уведомлениями
- ✉️ Корпоративная почта
- 👥 Список группы с контактами
- 🤖 AI-ассистент (NVIDIA NIM)
- ☁️ Синхронизация с Google Диском
- 🔒 Управление приватностью

## Сборка

### Требования

- Flutter 3.19+
- Android SDK 36
- NDK 28.2.13676358
- AGP 8.6.1 / Kotlin 2.1.0

### Настройка

1. Склонируй репозиторий
2. Создай `android/local.properties`:
   ```
   sdk.dir=/path/to/Android/sdk
   flutter.sdk=/path/to/flutter
   ```
3. Установи зависимости:
   ```bash
   flutter pub get
   ```

### Android

```bash
flutter build apk --release
# или
flutter build appbundle --release
```

### Windows

```bash
flutter build windows --release
```

## API ключи

- **NVIDIA NIM** — ключ вводится прямо в приложении (Профиль → Интеграции). Получить: [build.nvidia.com](https://build.nvidia.com)
- **Google Drive** — авторизация через Google Sign-In внутри приложения

## Дисклеймер

Это неофициальное приложение, не аффилированное с МГЮА. Используется публичный API личного кабинета.
"# MSAL-RELEASE" 
