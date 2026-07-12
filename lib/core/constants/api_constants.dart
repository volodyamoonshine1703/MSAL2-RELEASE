// lib/core/constants/api_constants.dart

class ApiConstants {
  ApiConstants._();

  static const String baseUrl = 'https://lk.msal.ru:3443';

  // ── Auth ──────────────────────────────────────────────────────────────────
  static const String auth        = '/auth';
  static const String authLogout  = '/auth/logout';
  static const String authRefresh = '/auth/refresh';

  // ── Schedule ──────────────────────────────────────────────────────────────
  // GET /schedule?from=YYYY-MM-DD&to=YYYY-MM-DD  ← confirmed working in original HAR
  static const String schedule = '/schedule';

  // ── Student ───────────────────────────────────────────────────────────────
  static const String studentGroup  = '/student/group';
  static const String studentPasses = '/student/passes';

  // ── Record book ───────────────────────────────────────────────────────────
  static const String recordbook = '/recordbook';

  // ── Misc ──────────────────────────────────────────────────────────────────
  static const String notifications = '/notifications';
  static const String newsPreview   = '/news/preview';

  // ── Headers (matches real browser HAR) ───────────────────────────────────
  static const Map<String, String> defaultHeaders = {
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7',
    'Content-Type': 'application/json',
    'Origin': 'https://lk.msal.ru',
    'Referer': 'https://lk.msal.ru/',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:150.0) Gecko/20100101 Firefox/150.0',
    'X-Device-Model': 'ClientType: browser, ClientName: Firefox, ClientVersion: 151.0, DeviceOS: Windows, DeviceType: desktop',
  };
}
