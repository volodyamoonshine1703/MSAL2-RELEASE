# Backend Documentation — MSAL+ Application

## Overview

**MSAL+** — кроссплатформенное приложение (Flutter) для доступа к сервисам МГЮА:
- Личный кабинет студента (`lk.msal.ru:3443`)
- Корпоративная почта (`mail.msal.ru`)
- Внешний сервис рейтинга преподавателей (`myprepod.ru`)
- AI-ассистент на базе NVIDIA NIM API

**Планируется:** Веб-версия для интеграции в Telegram Mini App.

---

## Table of Contents

1. [Архитектура](#архитектура)
2. [Сетевой слой](#сетевой-слой)
3. [Сервисы](#сервисы)
   - [AuthService](#authservice)
   - [ApiService (ЛК)](#apiservice-лк)
   - [MailService (Почта)](#mailservice-почта)
   - [MyprepodService](#myprepodservice)
   - [AiService](#aiservice)
   - [OwaContactSearch](#owacontactsearch)
   - [CrossRefService](#crossrefservice)
   - [LocalDbService](#localdbservice)
4. [Модели данных](#модели-данных)
5. [API Endpoints](#api-endpoints)
6. [Аутентификация и токены](#аутентификация-и-токены)
7. [Кеширование](#кеширование)
8. [Обработка ошибок](#обработка-ошибок)
9. [Рекомендации для веб-версии](#рекомендации-для-веб-версии)

---

## Архитектура

```
lib/
├── core/
│   ├── constants/         # API константы, базовые URL
│   ├── network/           # Dio клиент, интерсепторы
│   ├── providers/         # Riverpod провайдеры
│   ├── theme/             # Темизация
│   └── utils/             # Утилиты (логирование)
├── data/
│   ├── models/            # Модели данных (User, Schedule, Grade, etc.)
│   └── services/          # Бизнес-логика и API клиенты
└── presentation/
    ├── screens/           # UI экраны
    └── widgets/           # Переиспользуемые виджеты
```

**State Management:** Flutter Riverpod  
**HTTP Client:** Dio с кастомными интерсепторами  
**Local Storage:** 
- `flutter_secure_storage` — токены, пароли
- `shared_preferences` — кеш пользователя, настройки
- `sqflite` — SQLite кеш расписания, оценок, заметок

---

## Сетевой слой

### DioClient (`lib/core/network/dio_client.dart`)

Базовая конфигурация HTTP клиента:

```dart
baseUrl: 'https://lk.msal.ru:3443'
connectTimeout: 12s
receiveTimeout: 20s
validateStatus: (s) => s < 500
```

**SSL Certificates:** Самоподписанные сертификаты для `lk.msal.ru` и `mail.msal.ru` обрабатываются через `badCertificateCallback`.

**Интерсепторы:**
1. **Logger** — логирование запросов/ответов в debug режиме
2. **Auth Injector** — автоматическое добавление `Authorization: Bearer <token>`
3. **Token Refresh** — автообновление токена при 401 ошибке

---

## Сервисы

### AuthService

**Файл:** `lib/data/services/auth_service.dart`

**Ответственность:**
- Аутентификация пользователя (login/password)
- Управление JWT токенами (access/refresh)
- Автообновление сессии
- Восстановление сессии при перезапуске приложения
- Logout с очисткой всех кешей

#### Ключевые методы:

| Метод | Описание |
|-------|----------|
| `login(username, password)` | POST `/auth` → получение токенов |
| `checkSession()` | GET `/auth` → проверка валидности токена |
| `tryRestoreSession()` | Восстановление сессии из кеша или ре-логин |
| `logout()` | Очистка токенов, кешей, сессий почты/myprepod |

#### Токены:

```json
{
  "access_token": "JWT...",
  "refresh_token": "JWT..."
}
```

**Хранение:**
- Access Token: `FlutterSecureStorage('access_token')`
- Refresh Token: `FlutterSecureStorage('refresh_token')`
- Password: `FlutterSecureStorage('saved_password')`
- Login: `SharedPreferences('saved_login')`
- User Cache: `SharedPreferences('cached_user')`

#### Auto-Refresh Logic:

1. **Preemptive refresh:** Если токен истекает через < 5 минут → обновить заранее
2. **Reactive refresh:** При получении 401 ошибки:
   - Попытка refresh через `/auth/refresh`
   - Fallback: тихий ре-логин с сохранёнными credentials
   - Повтор оригинального запроса с новым токеном

**Thread Safety:** Используется `QueuedInterceptorsWrapper` для предотвращения race conditions при одновременных 401 ответах.

---

### ApiService (ЛК)

**Файл:** `lib/data/services/api_service.dart`

**Ответственность:** Работа с API личного кабинета `lk.msal.ru:3443`

#### Ключевые методы:

##### Расписание:
```dart
Future<List<ScheduleDay>> getScheduleWeek(DateTime monday)
Stream<List<ScheduleDay>> getScheduleWeekStream(DateTime monday) // stale-while-revalidate
```
- **Endpoint:** `GET /schedule?from=YYYY-MM-DD&to=YYYY-MM-DD`
- **Merge:** Для студентов института — объединение с консультациями

##### Успеваемость:
```dart
Future<List<ProgressItem>> getProgress({bool forceRefresh})
Future<List<ProgressItem>> getProgressWithLessons({bool forceRefresh})
```
- **List Endpoint:** `GET /progress?course=X&semester=Y`
- **Details Endpoint:** `GET /progress/details?disciplineID=UUID&course=X&semester=Y`
- **Возвращает:** Посещаемость, оценки, долги (hasDebt), модули (для института)

##### Зачётная книжка:
```dart
Future<List<RecordEntry>> getRecordbook()
```
- **Endpoint:** `GET /recordbook`

##### Группа:
```dart
Future<List<UserModel>> getGroupmates()
```
- **Endpoint:** `GET /student/group`

##### Пропуска (RFID):
```dart
Future<Map<String, dynamic>> getStudentPasses()
```
- **Endpoint:** `GET /student/passes`
- **Note:** Для института возвращает `{}` (пропуски показываются в успеваемости)

##### Информация о студенте (Институт):
```dart
Future<Map<String, dynamic>> getStudentInfo()
```
- **Endpoint:** `GET /student/info`
- **Возвращает:** `{reting, passes, InstituteUrl}`

##### Домашнее задание:
```dart
Future<Map<String, dynamic>?> getHomework(lessonId, discipline, date)
```
- **Endpoint:** `GET /homework/{lessonId}`

##### Консультации:
```dart
Future<List<ConsultationSlot>> getMyConsultations(from, to)
```
- **Endpoint:** `GET /consultation/my`

##### Новости:
```dart
Future<List<Map<String, dynamic>>> getNews()
Future<void> markNewsRead(newsId)
```
- **Endpoints:** `GET /news/preview`, `POST /news/{id}/read`

##### Приватность:
```dart
Future<void> updatePrivacySettings(showEmail, showPhoto, showMobile)
```
- **Endpoint:** `PUT /student/access`

---

### MailService (Почта)

**Файл:** `lib/data/services/mail_service.dart`

**Протоколы:**
- **IMAP:** `mail.msal.ru:993` (SSL) — чтение писем
- **SMTP:** `mail.msal.ru:587` (STARTTLS) или `465` (SSL) — отправка
- **OWA API:** `https://mail.msal.ru/owa/` — отправка, поиск контактов, фото

#### Ключевые методы:

##### Подключение:
```dart
Future<void> connect(String login, [String? explicitPassword])
Future<void> disconnect()
```
- Логин: `<username>@edu.msal.ru` или полный email
- Пароль берётся из `FlutterSecureStorage('saved_password')`
- Инициализирует OWA сессию для поиска контактов

##### Папки:
```dart
Future<List<MailFolder>> listFolders()
```
- **IMAP Command:** `LIST "" "*"`

##### Список писем:
```dart
Future<List<MailMessage>> fetchMessages(String folderPath, {int limit = 50})
```
- **IMAP Command:** `FETCH (UID FLAGS ENVELOPE)`
- Возвращает последние N писем (реверсивно)

##### Чтение письма:
```dart
Future<MailMessage?> fetchMessageBody(String folderPath, int uid)
```
- **IMAP Command:** `UID FETCH (UID FLAGS ENVELOPE BODY[])`
- Извлекает: text/plain, text/html, вложения

##### Вложения:
```dart
Future<List<int>?> downloadAttachment(folderPath, uid, partIndex)
```

##### Отметка прочитанным:
```dart
Future<void> markSeen(String folderPath, int uid)
```
- **IMAP Command:** `UID STORE +FLAGS (\\Seen)`

##### Отправка письма:
```dart
Future<void> sendMessage({
  required List<String> to,
  required String subject,
  required String body,
  String? cc,
  List<File> attachments = const [],
})
```
**Приоритет отправки:**
1. **OWA API** (более надёжно, обходит SMTP ограничения)
2. **SMTP** (fallback)

##### Поиск контактов:
```dart
Future<List<MailContact>> searchContacts(String query)
```
**Источники:**
1. **OWA Corporate Directory** (приоритет)
2. **IMAP Sent Folder** (последние 200 писем)
3. **IMAP Inbox** (последние 300 писем)

---

### MyprepodService

**Файл:** `lib/data/services/myprepod_service.dart`

**Ответственность:** Парсинг рейтингов и отзывов преподавателей с `myprepod.ru`

#### 3-уровневое кеширование:

| Уровень | Хранилище | TTL |
|---------|-----------|-----|
| L1 | In-memory Map | Session |
| L2 | SQLite (`myprepod_cache`) | 30 дней |
| L3 | HTTP Fetch | — |

#### Ключевые методы:

```dart
Future<MyprepodData?> getTeacherRating(String name)
```

**Алгоритм поиска:**
1. Очистка имени от титулов (профессор, доцент, к.ю.н. и т.д.)
2. Поиск с приоритетом `uid=msal` (МГЮА-specific)
3. Fallback: глобальный поиск
4. Парсинг:
   - Рейтинг (X.X / 5)
   - Отзывы (текст, до 10 шт.)

**URLs:**
- Search: `https://myprepod.ru/?page=search&uid={uid}&search={query}`
- Profile: `https://myprepod.ru/index.php?page=res&res={resId}`

---

### AiService

**Файл:** `lib/data/services/ai_service.dart`

**Provider:** NVIDIA NIM API (OpenAI-compatible)  
**Model:** `meta/llama-3.1-70b-instruct`

#### Конфигурация:

```dart
baseUrl: 'https://integrate.api.nvidia.com/v1'
maxContextTokens: 7500
maxNewTokens: 2000
```

#### API Key:

- **Хранение:** `FlutterSecureStorage('nim_api_key')`
- **Маска для UI:** `nvapi-Ab...XyZ`

#### System Prompt:

Включает контекст:
- Данные студента (ФИО, группа, курс)
- Текущая дата/день недели
- Расписание на неделю + завтра
- Домашние задания (дедлайны)
- Общие заметки
- Успеваемость (долги, посещаемость)

#### Sliding Window:

При превышении лимита токенов:
1. Сохраняется system prompt (~500 tokens)
2. Удаляются oldest user/assistant пары
3. Добавляется новый message

#### Actions:

AI может запрашивать действия:
- `set_deadline` — установить дедлайн заметки
- `edit_note` — редактировать заметку
- `delete_note` — удалить заметку
- `none` — без действий

---

### OwaContactSearch

**Файл:** `lib/data/services/owa_contact_search.dart`

**Ответственность:** Работа с Exchange Web Services (OWA) для:
- Поиска контактов в корпоративном каталоге
- Получения фотографий профилей
- Отправки писем через OWA API

#### Сессия:

**Cookies:**
- `X-OWA-CANARY` — CSRF токен
- `X-BackEndCookie` — сессионный токен

**Фотографии:**
- **Memory Cache:** `_photoCache` Map
- **Disk Cache:** `ApplicationCacheDirectory/avatar_{md5}.jpg`
- **URL:** `https://mail.msal.ru/owa/service.svc?action=GetPersonaPhoto`

#### Поиск контактов:

```dart
Future<List<OwaContact>> findPeople(String query)
```

**SOAP Action:** `http://schemas.microsoft.com/exchange/services/2006/messages/FindPeople`

**Response:** JSON с полями:
- `personaId.Id`
- `DisplayName`
- `EmailAddress.Address`
- `Title`, `Department`, `OfficeLocation`, `PhoneNumber`

#### Отправка через OWA:

```dart
static Future<void> sendViaOwa({
  required List<String> to,
  required String subject,
  required String body,
  String? cc,
})
```

**Endpoint:** `https://mail.msal.ru/owa/service.svc`  
**SOAP Action:** `CreateItem`

---

### CrossRefService

**Файл:** `lib/data/services/cross_ref_service.dart`

**Ответственность:** Связывание данных между сервисами (ЛК + Почта)

#### Примеры использования:
- Поиск email преподавателя по имени из расписания
- Связь дисциплины с перепиской
- Автодополнение получателей при composing письма

---

### LocalDbService

**Файл:** `lib/data/services/local_db_service.dart`

**Database:** SQLite (`sqflite`)

#### Таблицы:

| Таблица | Назначение |
|---------|------------|
| `schedule_cache` | Кеш расписания (JSON) |
| `progress_cache` | Кех успеваемости |
| `homework_cache` | Кеш ДЗ |
| `notes` | Пользовательские заметки |
| `chat_history` | История AI-чата |
| `myprepod_cache` | Кеш рейтингов преподавателей |

#### TTL-based Cache:

```dart
Future<String?> getCache(String table, String key, {Duration maxAge = const Duration(hours: 1)})
```

---

## Модели данных

### Основные модели:

| Модель | Файл | Описание |
|--------|------|----------|
| `UserModel` | `user_model.dart` | Данные пользователя (ФИО, группа, курс, институт/колледж) |
| `ScheduleDay` | `schedule_model.dart` | День расписания со списком пар |
| `ScheduleLesson` | `schedule_model.dart` | Пара: время, предмет, тип, преподаватель, аудитория |
| `ProgressItem` | `grade_model.dart` | Дисциплина с посещаемостью и оценками |
| `LessonGrade` | `grade_model.dart` | Детали занятия: дата, посещаемость, оценка |
| `UniversityModule` | `grade_model.dart` | Модули/темы (для института) |
| `HomeworkModel` | `homework_model.dart` | Домашнее задание с дедлайном |
| `ConsultationSlot` | `consultation_model.dart` | Консультация преподавателя |
| `ChatMessage` | `chat_model.dart` | Сообщение AI-чата (user/assistant) |
| `MailMessage` | `mail_service.dart` | Письмо: тема, отправитель, тело, вложения |
| `MailFolder` | `mail_service.dart` | IMAP папка |
| `OwaContact` | `owa_contact_search.dart` | Контакт из корпоративного каталога |

---

## API Endpoints

### Личный кабинет (`https://lk.msal.ru:3443`)

| Method | Endpoint | Описание | Headers |
|--------|----------|----------|---------|
| POST | `/auth` | Логин | `{"username": "...", "password": "..."}` |
| GET | `/auth` | Проверка сессии | `Authorization: Bearer <token>` |
| POST | `/auth/logout` | Логаут | `Authorization: Bearer <token>` |
| POST | `/auth/refresh` | Обновление токена | `{"refresh_token": "..."}` |
| GET | `/schedule` | Расписание | `?from=YYYY-MM-DD&to=YYYY-MM-DD` |
| GET | `/progress` | Список дисциплин | `?course=X&semester=Y` |
| GET | `/progress/details` | Детали дисциплины | `?disciplineID=UUID&course=X&semester=Y` |
| GET | `/recordbook` | Зачётная книжка | — |
| GET | `/student/group` | Группа | — |
| GET | `/student/passes` | RFID пропуск | — |
| GET | `/student/info` | Инфо (институт) | — |
| PUT | `/student/access` | Настройки приватности | `{"email": bool, "photo": bool, "mobile": bool}` |
| GET | `/homework/{lessonId}` | ДЗ | — |
| GET | `/consultation/my` | Мои консультации | `?from=...&to=...` |
| GET | `/news/preview` | Новости | — |
| POST | `/news/{id}/read` | Mark news read | — |
| GET | `/notifications` | Уведомления | — |

**Default Headers:**
```json
{
  "Accept": "application/json, text/plain, */*",
  "Accept-Language": "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7",
  "Content-Type": "application/json",
  "Origin": "https://lk.msal.ru",
  "Referer": "https://lk.msal.ru/",
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:150.0) Gecko/20100101 Firefox/150.0",
  "X-Device-Model": "ClientType: browser, ClientName: Firefox, ClientVersion: 151.0, DeviceOS: Windows, DeviceType: desktop"
}
```

### Почта (`mail.msal.ru`)

| Протокол | Host | Port | SSL | Описание |
|----------|------|------|-----|----------|
| IMAP | mail.msal.ru | 993 | Yes | Чтение писем |
| SMTP | mail.msal.ru | 587 | STARTTLS | Отправка (приоритет) |
| SMTP | mail.msal.ru | 465 | SSL | Отправка (fallback) |
| HTTPS | mail.msal.ru | 443 | Yes | OWA API |

### Myprepod (`https://myprepod.ru`)

| URL | Описание |
|-----|----------|
| `/?page=search&uid={uid}&search={query}` | Поиск преподавателя |
| `/index.php?page=res&res={resId}` | Профиль преподавателя |

### NVIDIA NIM API (`https://integrate.api.nvidia.com/v1`)

| Method | Endpoint | Описание |
|--------|----------|----------|
| POST | `/chat/completions` | AI Chat Completion |

**Request:**
```json
{
  "model": "meta/llama-3.1-70b-instruct",
  "messages": [...],
  "max_tokens": 2000,
  "temperature": 0.7,
  "stream": false
}
```

---

## Аутентификация и токены

### JWT Token Flow:

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   Client    │      │  lk.msal.ru  │      │   Storage   │
└──────┬──────┘      └──────┬───────┘      └──────┬──────┘
       │                    │                     │
       │ POST /auth         │                     │
       │ {user, pass}       │                     │
       │───────────────────>│                     │
       │                    │                     │
       │  {access, refresh} │                     │
       │<───────────────────│                     │
       │                    │                     │ Save tokens
       │                    │                     │──────────>│
       │                    │                     │
       │ GET /schedule      │                     │
       │ Bearer <access>    │                     │
       │───────────────────>│                     │
       │                    │                     │
       │ 401 Unauthorized   │                     │
       │<───────────────────│                     │
       │                    │                     │
       │ POST /auth/refresh │                     │
       │ {refresh_token}    │                     │
       │───────────────────>│                     │
       │                    │                     │
       │ {new access, ref}  │                     │ Update storage
       │<───────────────────│                     │<──────────│
       │                    │                     │
       │ Replay request     │                     │
       │───────────────────>│                     │
       │ 200 OK             │                     │
       │<───────────────────│                     │
```

### Token Expiry Handling:

1. **Parse JWT payload:** Извлечение `exp` claim (Unix timestamp)
2. **Preemptive Refresh:** За 5 минут до истечения
3. **Reactive Refresh:** При 401 ошибке

---

## Кеширование

### Стратегии:

| Сервис | Стратегия | TTL |
|--------|-----------|-----|
| Расписание | Stale-while-revalidate | Бессрочно (всегда refetch) |
| Успеваемость | Live fetch | — |
| ДЗ | Live fetch | — |
| Myprepod | L1→L2→L3 | 30 дней (L2) |
| Фото контактов | Memory + Disk | Бессрочно |
| AI Chat History | SQLite | Бессрочно |

### SQLite Schema:

```sql
CREATE TABLE schedule_cache (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  timestamp INTEGER NOT NULL
);

CREATE TABLE notes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT,
  content TEXT,
  lesson_id TEXT,
  discipline TEXT,
  deadline INTEGER,
  created_at INTEGER,
  updated_at INTEGER
);

CREATE TABLE myprepod_cache (
  teacher_name TEXT PRIMARY KEY,
  rating TEXT,
  reviews TEXT,
  cached_at INTEGER
);
```

---

## Обработка ошибок

### Типы ошибок:

#### Network Errors:
```dart
DioExceptionType.connectionTimeout  // "Сервер не отвечает (таймаут)"
DioExceptionType.receiveTimeout     // "Сервер не отвечает (таймаут)"
DioExceptionType.unknown            // HandshakeException, SocketException
```

#### Auth Errors:
```dart
401 Unauthorized  // Auto-refresh or logout
403 Forbidden     // "Неверный логин или пароль"
```

#### Custom Exceptions:
```dart
class AuthException implements Exception {
  final String message;
}
```

### Retry Logic:

- **MailService:** Reconnect при IMAP/SMTP ошибках
- **ApiService:** Stale-while-revalidate для расписания
- **AuthService:** Silent re-login при failed refresh

---

## Рекомендации для веб-версии (Telegram Mini App)

### 1. Адаптация сетевого слоя

**Проблема:** `dart:io` не работает в вебе  
**Решение:** Использовать `dart:html` или универсальный HTTP клиент

```dart
// Для веба потребуется замена:
import 'package:dio/io.dart';  // ❌ Не работает в вебе
// На:
import 'package:dio/browser.dart';  // ✅ BrowserHttpClientAdapter
```

### 2. Хранение данных

| Mobile/Desktop | Web Alternative |
|----------------|-----------------|
| `FlutterSecureStorage` | `localStorage` / `sessionStorage` |
| `SharedPreferences` | `localStorage` |
| `Sqflite` | `IndexedDB` (через `sqflite_common_ffi_web`) |
| `PathProvider` | `window.localStorage` |

### 3. CORS

**Проблема:** Браузер блокирует cross-origin запросы к `lk.msal.ru:3443`  
**Решение:**
- Proxy server (Node.js/Python) для маршрутизации запросов
- Или настройка CORS на сервере МГЮА (если возможно)

### 4. Telegram Mini App Integration

**Required:**
- Telegram WebApp SDK initialization
- Theme adaptation (Telegram color scheme)
- Back button handling
- Viewport adaptation

**Example:**
```dart
// Инициализация Telegram WebApp
await TelegramWebApp.init();
final theme = TelegramWebApp.themeParams;
```

### 5. Роутинг

**Текущая структура экранов:**
```
/login              # Авторизация
/shell              # Main navigation
  /dashboard        # Главная
  /schedule         # Расписание
  /grades           # Успеваемость
  /mail             # Почта
  /profile          # Профиль
  /settings         # Настройки
  /ai               # AI-ассистент
```

**Для веба добавить:**
- Deep linking support
- Query parameters for filters
- Browser back/forward navigation

### 6. State Persistence

**Рекомендация:** Сохранять состояние при закрытии вкладки:
- Current tab index
- Filter states
- Expanded/collapsed sections

### 7. Performance

**Оптимизации для веба:**
- Lazy loading для больших списков (письма, расписание)
- Virtual scrolling
- Image lazy loading (аватарки, вложения)
- Service Worker для offline mode

---

## Приложения

### A. HAR Files Analysis

В репозитории присутствуют HAR файлы для анализа:
- `consultation_har.json` — консультации
- `consultation_har_2.json` — консультации (доп.)
- `university_grades_har.json` — успеваемость института
- `mail.msal.ru_Archive.har` — почта
- `logout.har` — логаут

### B. Тестовые скрипты

| Файл | Назначение |
|------|------------|
| `test/api_test.dart` | Тесты API endpoints |
| `test_myprepod.dart` | Тесты myprepod парсинга |
| `test_mime.dart` | Тесты MIME декодера |
| `fix_*.py` | Скрипты исправлений |

### C. Зависимости (pubspec.yaml)

**Ключевые пакеты:**
```yaml
dependencies:
  flutter_riverpod: ^2.x
  dio: ^5.x
  flutter_secure_storage: ^9.x
  shared_preferences: ^2.x
  sqflite: ^2.x
  enough_mail: ^2.x
  intl: ^0.19.x
  path_provider: ^2.x
  crypto: ^3.x
```

---

**Документация актуальна на:** Сентябрь 2025  
**Версия приложения:** 2.1.x  
**Контакты:** MSAL+ Development Team
