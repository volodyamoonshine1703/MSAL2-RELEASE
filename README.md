# MSAL+

Неофициальный альтернативный клиент для личного кабинета МГЮА ([lk.msal.ru](https://lk.msal.ru)).

## 🌐 Веб-версия (Кроссплатформенная)

Основная версия приложения теперь доступна как веб-приложение. Работает на всех устройствах: Android, iOS, Windows, macOS, Linux.

### Быстрый старт

```bash
cd web
npm install
npm run dev
```

Приложение будет доступно по адресу `http://localhost:5173`.

### Сборка для продакшена

```bash
cd web
npm run build
# Результат в директории web/dist/
```

### Технологии

- React 18 + TypeScript
- Vite (сборщик)
- TailwindCSS (стилизация)
- Axios (API клиент)
- Адаптивный дизайн (Mobile First)

## 📱 Мобильные и десктоп версии (Flutter)

> ⚠️ В разработке. Основной фокус сейчас на веб-версии.

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

## 🔑 Возможности

- 📅 Расписание занятий (МЭШ-стиль)
- 📊 Оценки и успеваемость
- 📝 Домашние задания с дедлайнами и уведомлениями
- ✉️ Корпоративная почта
- 👥 Список группы с контактами
- 🤖 AI-ассистент (NVIDIA NIM)
- ☁️ Синхронизация с Google Диском
- 🔒 Управление приватностью
- 🌓 Тёмная/светлая тема
- 📲 Адаптивный интерфейс для всех устройств

## 🔐 Авторизация

Используется OAuth 2.0 через личный кабинет МГЮА. При первом запуске потребуется войти в учётную запись университета. Сессия сохраняется локально.

## 🛠 API ключи

- **NVIDIA NIM** — ключ вводится прямо в приложении (Профиль → Интеграции). Получить: [build.nvidia.com](https://build.nvidia.com)
- **Google Drive** — авторизация через Google Sign-In внутри приложения

## 📂 Структура проекта

```
msal-university-app/
├── web/                    # Веб-версия (React + TypeScript)
│   ├── src/
│   │   ├── components/     # UI компоненты
│   │   ├── pages/          # Страницы приложения
│   │   ├── api/            # API клиент
│   │   └── App.tsx         # Главный компонент
│   ├── package.json
│   └── vite.config.ts
├── lib/                    # Flutter версия (в разработке)
├── android/                # Android специфичный код
├── windows/                # Windows специфичный код
└── docs/                   # Документация API
```

## 📚 Документация

- [Документация бэкенд API](BACKEND_DOCUMENTATION.md) - полное описание endpoints lk.msal.ru
- [Архитектура веб-приложения](web/README.md) - детали реализации фронтенда

## 🤝 Вклад в проект

1. Форкните репозиторий
2. Создайте ветку (`git checkout -b feature/amazing-feature`)
3. Закоммитьте изменения (`git commit -m 'Add amazing feature'`)
4. Запушьте ветку (`git push origin feature/amazing-feature`)
5. Откройте Pull Request

## 📄 Лицензия

MIT License

## ⚠️ Дисклеймер

Это неофициальное приложение, не аффилированное с МГЮА. Используется публичный API личного кабинета.
"# MSAL-RELEASE" 
