# ПЛАН РЕАЛИЗАЦИИ ЗАЩИТЫ ПЕРСОНАЛЬНЫХ ДАННЫХ
## Веб-версия как транзитный посредник (без статуса оператора ПДн)

---

## 1. ЮРИДИЧЕСКАЯ АРХИТЕКТУРА

### 1.1. Статус приложения
- **Роль**: Технический посредник (транзит данных)
- **Не является**: Оператором персональных данных
- **Принцип**: Данные никогда не сохраняются на сервере приложения

### 1.2. Ключевые принципы
1. **Локальное хранение**: Все ПДн хранятся только на устройстве пользователя
2. **Анонимизация**: Работа через уникальный код без прямой идентификации
3. **Транзитность**: Сервер передаёт данные без их обработки и сохранения
4. **Отсутствие логов**: Не ведётся журналирование передаваемых данных
5. **Ephemeral sessions**: Сессии существуют только во время запроса

---

## 2. АНОНИМИЗИРОВАННЫЙ КОД ПОЛЬЗОВАТЕЛЯ

### 2.1. Формат кода
```
{INSTITUTE}_{COURSE}_{GROUP}_{RANDOM_SUFFIX}
```

**Пример**: `FAI_3_102_a7f3d9e2`

### 2.2. Генерация кода
```typescript
// Генерация на клиенте (в браузере пользователя)
function generateAnonymousCode(institute: string, course: number, group: string): string {
  const randomSuffix = crypto.randomUUID().slice(0, 8);
  return `${institute}_${course}_${group}_${randomSuffix}`;
}
```

### 2.3. Хранение кода
- **Где**: localStorage / IndexedDB устройства пользователя
- **Когда**: При первой авторизации
- **Что хранится**: Только код, НЕ ФИО, НЕ паспортные данные

---

## 3. ЛОКАЛЬНОЕ ХРАНЕНИЕ ДАННЫХ

### 3.1. Технологии
| Платформа | Технология | Шифрование |
|-----------|------------|------------|
| Web Browser | IndexedDB + AES-GCM | Web Crypto API |
| Telegram Mini App | TMA Storage + IndexedDB | Web Crypto API |
| Mobile (Flutter) | Hive / SharedPreferences | AES-256 |

### 3.2. Структура локального хранилища
```typescript
interface LocalStorage {
  // Анонимный код
  anonymousCode: string;
  
  // Временные токены (шифрованные)
  encryptedTokens: {
    lkToken: string;
    mailToken: string;
    expiresAt: number;
  };
  
  // Кеш данных (шифрованный)
  encryptedCache: {
    schedule: string;
    grades: string;
    mails: string;
    lastUpdate: number;
  };
  
  // Настройки (не ПДн)
  settings: {
    theme: 'light' | 'dark';
    notifications: boolean;
  };
}
```

### 3.3. Шифрование данных
```typescript
import { webcrypto } from 'crypto';

// Генерация ключа из пароля пользователя
async function deriveKey(password: string, salt: Uint8Array): Promise<CryptoKey> {
  const enc = new TextEncoder();
  const keyMaterial = await webcrypto.subtle.importKey(
    'raw',
    enc.encode(password),
    'PBKDF2',
    false,
    ['deriveBits', 'deriveKey']
  );
  
  return webcrypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: salt,
      iterations: 100000,
      hash: 'SHA-256'
    },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

// Шифрование данных
async function encryptData(data: string, key: CryptoKey): Promise<string> {
  const iv = webcrypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(data);
  
  const ciphertext = await webcrypto.subtle.encrypt(
    { name: 'AES-GCM', iv: iv },
    key,
    encoded
  );
  
  // Сохраняем IV + ciphertext в base64
  return btoa(String.fromCharCode(...iv) + String.fromCharCode(...new Uint8Array(ciphertext)));
}
```

---

## 4. ТРАНЗИТНЫЙ СЕРВЕР

### 4.1. Архитектура
```
┌─────────────┐      ┌──────────────────┐      ┌──────────────┐
│  Клиент     │─────▶│  Транзитный      │─────▶│  ЛК MSAL     │
│  (Browser)  │◀─────│  Прокси (Node.js)│◀─────│  mail.msal   │
└─────────────┘      └──────────────────┘      └──────────────┘
       │                      │
       │  Запрос с            │  Запрос БЕЗ
       │  анонимным кодом     │  сохранения данных
       ▼                      ▼
  Локальное              В памяти
  хранилище              (только во
                         время запроса)
```

### 4.2. Принципы работы прокси
1. **Без состояния (Stateless)**: Никаких сессий на сервере
2. **Без логов**: Отключено логирование тел запросов
3. **In-memory only**: Данные только в RAM, удаляются после ответа
4. **No persistence**: Никаких баз данных на сервере

### 4.3. Реализация прокси (Node.js + Express)
```typescript
import express from 'express';
import httpProxyMiddleware from 'http-proxy-middleware';

const app = express();

// ОТКЛЮЧАЕМ логирование тел запросов
app.use((req, res, next) => {
  const originalWrite = res.write.bind(res);
  const originalEnd = res.end.bind(res);
  
  // Логируем только метаданные (без ПДн)
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path} - Anonymous: ${req.headers['x-anonymous-code']?.slice(0, 10)}...`);
  
  next();
});

// Прокси для ЛК
app.use('/api/lk', httpProxyMiddleware({
  target: 'https://lk.msal.ru:3443',
  changeOrigin: true,
  secure: false,
  onProxyReq: (proxyReq, req, res) => {
    // Добавляем анонимный код в заголовок
    const anonCode = req.headers['x-anonymous-code'];
    if (anonCode) {
      proxyReq.setHeader('X-Anonymous-Code', anonCode);
    }
    
    // НЕ добавляем оригинальные токены в логи
    console.log(`[PROXY LK] Forwarding request - NO DATA STORED`);
  },
  onProxyRes: (proxyRes, req, res) => {
    // Данные проходят транзитом, не сохраняются
    console.log(`[PROXY LK] Response forwarded - MEMORY CLEARED`);
  }
}));

// Прокси для почты
app.use('/api/mail', httpProxyMiddleware({
  target: 'https://mail.msal.ru',
  changeOrigin: true,
  secure: false,
  // Аналогично - без сохранения данных
}));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({ 
    status: 'ok', 
    message: 'Transit proxy - no data stored',
    timestamp: new Date().toISOString()
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Transit proxy running on port ${PORT}`);
  console.log('⚠️  NO DATA PERSISTENCE - STATELESS MODE');
});
```

### 4.4. Конфигурация безопасности
```bash
# .env для продакшена
NODE_ENV=production
DISABLE_LOGS=true
NO_DATABASE=true
EPHEMERAL_SESSIONS=true
```

---

## 5. АВТОРИЗАЦИЯ БЕЗ СОХРАНЕНИЯ ПДН

### 5.1. Поток авторизации
```
1. Пользователь вводит логин/пароль → ТОЛЬКО в браузере
2. Браузер получает токены от ЛК MSAL → Шифрует и сохраняет локально
3. Генерируется анонимный код → Сохраняется локально
4. Все дальнейшие запросы → Через анонимный код + локальные токены
```

### 5.2. Код авторизации (клиент)
```typescript
class AuthManager {
  private storage: LocalStorage;
  
  async login(username: string, password: string): Promise<void> {
    // 1. Прямой запрос к ЛК (через наш прокси БЕЗ сохранения)
    const response = await fetch('/api/lk/auth', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        // НЕ отправляем ПДн на наш сервер
      },
      body: JSON.stringify({ username, password })
    });
    
    const { tokens, user } = await response.json();
    
    // 2. Генерируем анонимный код
    const anonCode = this.generateAnonymousCode(user.institute, user.course, user.group);
    
    // 3. Шифруем и сохраняем ТОЛЬКО локально
    await this.storage.save({
      anonymousCode: anonCode,
      encryptedTokens: await this.encryptTokens(tokens),
      // НЕ сохраняем ФИО, паспорт, etc.
    });
    
    // 4. Очищаем память
    tokens = null;
    user = null;
  }
  
  private generateAnonymousCode(institute: string, course: number, group: string): string {
    const suffix = crypto.randomUUID().slice(0, 8);
    return `${institute}_${course}_${group}_${suffix}`;
  }
}
```

---

## 6. ВЫПИЛИВАНИЕ НЕЙРО-ФУНКЦИЙ

### 6.1. Что удаляем
- ❌ AI-помощник
- ❌ Анализ успеваемости через ML
- ❌ Рекомендации на основе данных
- ❌ Любые внешние API нейросетей (OpenAI, etc.)

### 6.2. Чем заменяем
- ✅ Статические правила (if-else логика)
- ✅ Локальные вычисления без отправки данных
- ✅ Простая фильтрация и сортировка

### 6.3. Пример замены
```typescript
// БЫЛО (с AI)
async function getStudyRecommendations(studentId: string): Promise<string> {
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    body: JSON.stringify({ student_data: ... }) // ❌ Отправка ПДн
  });
  return response.data.choices[0].message.content;
}

// СТАЛО (без AI)
function getStudyAdvice(grades: Grade[]): string {
  const avgGrade = grades.reduce((sum, g) => sum + g.value, 0) / grades.length;
  
  if (avgGrade >= 4.5) {
    return 'Отличная работа! Продолжайте в том же духе.';
  } else if (avgGrade >= 3.5) {
    return 'Хороший результат. Обратите внимание на предметы с оценкой ниже 4.';
  } else {
    return 'Рекомендуется уделить больше времени учёбе.';
  }
  // ✅ Всё считается локально, данные никуда не отправляются
}
```

---

## 7. TELEGRAM MINI APP ИНТЕГРАЦИЯ

### 7.1. Особенности TMA
- Использует `Telegram.WebApp` SDK
- Данные хранятся в `localStorage` внутри WebView Telegram
- Анонимный код генерируется один раз при первом запуске

### 7.2. Инициализация
```typescript
import WebApp from '@twa-dev/sdk';

class TmaInitializer {
  async init(): Promise<void> {
    WebApp.ready();
    
    // Проверяем наличие анонимного кода
    const storedCode = localStorage.getItem('anonymous_code');
    
    if (!storedCode) {
      // Первый запуск - запрашиваем данные у пользователя
      const userData = WebApp.initDataUnsafe.user;
      
      // Генерируем код на основе данных Telegram (НЕ сохраняем сами данные)
      const anonCode = this.generateFromTgData(userData);
      localStorage.setItem('anonymous_code', anonCode);
    }
    
    // Готово к работе
    WebApp.expand();
  }
  
  private generateFromTgData(user: any): string {
    // Используем ID Telegram как часть суффикса (НЕ как идентификатор)
    const suffix = `tg_${user.id.toString().slice(-6)}`;
    return `MSAL_1_000_${suffix}`; // Дефолтные значения, пользователь уточнит
  }
}
```

---

## 8. МЕРЫ БЕЗОПАСНОСТИ

### 8.1. На клиенте
- ✅ Шифрование всех данных перед сохранением
- ✅ Автоочистка памяти после использования
- ✅ HTTPS только
- ✅ Content Security Policy (CSP)
- ✅ Защита от XSS (санитизация ввода)

### 8.2. На сервере
- ✅ Отключено логирование тел запросов
- ✅ Нет баз данных
- ✅ Stateless архитектура
- ✅ Rate limiting (защита от DDoS)
- ✅ Минимальные права доступа

### 8.3. Юридические меры
- ✅ Публичная оферта с описанием архитектуры
- ✅ Политика конфиденциальности (no data collection)
- ✅ Документация о транзитном статусе
- ✅ Disclaimer в интерфейсе приложения

---

## 9. ПЛАН РЕАЛИЗАЦИИ

### Этап 1: Подготовка (1-2 дня)
- [ ] Удалить все AI-сервисы из кода
- [ ] Создать новый Flutter проект для веб-версии
- [ ] Настроить структуру папок

### Этап 2: Локальное хранилище (2-3 дня)
- [ ] Реализовать шифрование на Web Crypto API
- [ ] Создать абстракцию для localStorage/IndexedDB
- [ ] Интегрировать с Flutter Web

### Этап 3: Транзитный прокси (2-3 дня)
- [ ] Развернуть Node.js сервер
- [ ] Настроить http-proxy-middleware
- [ ] Отключить логирование
- [ ] Протестировать stateless режим

### Этап 4: Авторизация (2-3 дня)
- [ ] Реализовать поток без сохранения ПДн
- [ ] Генерация анонимного кода
- [ ] Тесты безопасности

### Этап 5: Telegram Mini App (2-3 дня)
- [ ] Интеграция @twa-dev/sdk
- [ ] Адаптация под Telegram UI
- [ ] Deep links

### Этап 6: Тестирование и документация (2-3 дня)
- [ ] Penetration testing
- [ ] Аудит безопасности
- [ ] Юридическая документация
- [ ] Публикация

**Итого**: ~11-17 дней

---

## 10. ЧЕК-ЛИСТ БЕЗОПАСНОСТИ

### Перед запуском проверить:
- [ ] На сервере НЕТ баз данных с ПДн
- [ ] Логи не содержат тел запросов
- [ ] Все данные на клиенте зашифрованы
- [ ] AI-функции полностью удалены
- [ ] Анонимный код не позволяет деанонимизировать
- [ ] HTTPS настроен правильно
- [ ] CSP заголовки установлены
- [ ] Юридическая документация опубликована

---

## 11. ОТВЕТСТВЕННОСТЬ

### Что делает приложение:
- ✅ Предоставляет интерфейс для доступа к ЛК MSAL
- ✅ Хранит данные ТОЛЬКО на устройстве пользователя
- ✅ Передаёт запросы транзитом без сохранения

### Что НЕ делает приложение:
- ❌ Не собирает персональные данные
- ❌ Не хранит данные на сервере
- ❌ Не обрабатывает данные (кроме транзита)
- ❌ Не передаёт данные третьим лицам
- ❌ Не использует нейросети

**Статус**: Технический посредник, не оператор ПДн (152-ФЗ РФ)

---

## 12. КОНТАКТЫ ДЛЯ ЮРИДИЧЕСКОЙ КОНСУЛЬТАЦИИ

Рекомендуется проконсультироваться с юристом по IT-праву для:
1. Проверки соответствия 152-ФЗ
2. Составления публичной оферты
3. Подготовки политики конфиденциальности
4. Регистрации уведомления в Роскомнадзоре (если потребуется)

---

*Документ создан: $(date)*
*Версия: 1.0*
*Статус: Черновик для обсуждения*
