# Настройка Google Sign-In для MSAL+

## Шаг 1 — Создать проект в Google Cloud Console

1. Открой https://console.cloud.google.com/
2. Нажми «Выбрать проект» → «Создать проект» → Назови «MSAL Plus»
3. Перейди в «API и сервисы» → «Включённые API» → «Включить APIs»
4. Найди и включи **Google Drive API**

## Шаг 2 — Создать OAuth credentials

### Для Android:
1. «Учётные данные» → «Создать» → «Идентификатор клиента OAuth»
2. Тип: **Android**
3. Имя пакета: `ru.msal.plus` (или то что в android/app/build.gradle)
4. SHA-1 отпечаток — получи командой:
   ```
   keytool -list -v -keystore "%USERPROFILE%\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
   ```
5. Скачай `google-services.json` → положи в `android/app/`

### Для Windows (Desktop OAuth):
1. «Учётные данные» → «Создать» → «Идентификатор клиента OAuth»
2. Тип: **Классическое приложение**
3. Скопируй **Client ID** и **Client Secret**

## Шаг 3 — Прописать Client ID в приложении

Открой `lib/data/services/drive_sync_service.dart` и замени:

```dart
final _googleSignIn = GoogleSignIn(scopes: _scopes);
```

на:

```dart
final _googleSignIn = GoogleSignIn(
  scopes: _scopes,
  // Только для Windows — вставь clientId из шага 2:
  // clientId: 'YOUR_WINDOWS_CLIENT_ID.apps.googleusercontent.com',
);
```

## Шаг 4 — Для Android добавить google-services plugin

В `android/build.gradle` добавь в dependencies:
```groovy
classpath 'com.google.gms:google-services:4.4.1'
```

В `android/app/build.gradle` добавь в самый конец:
```groovy
apply plugin: 'com.google.gms.google-services'
```

## Экранный тест (без Google Cloud)

Если нет времени настраивать — синхронизация через Google Диск будет
недоступна (кнопка войти не откроет окно), но всё остальное работает.
Ошибка не ломает приложение — обёрнута в try/catch.

