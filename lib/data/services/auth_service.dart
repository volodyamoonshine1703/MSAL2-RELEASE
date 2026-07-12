import '../../core/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/data/services/auth_service.dart
//
// HAR confirms:
//   POST /auth  { username, password }  →  { ..., access_token: "JWT...", refresh_token: "JWT..." }
//   GET  /auth  Authorization: Bearer <access_token>  →  same user object (session check)
//   All other requests: Authorization: Bearer <access_token>

import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../core/utils/log.dart' as logger;
import '../models/user_model.dart';
import '../../core/constants/api_constants.dart';
import 'local_db_service.dart';
import 'mail_service.dart';
import 'myprepod_service.dart';

class AuthException implements Exception {
  final String message;
  const AuthException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  final Dio _dio;
  late final Dio _plainDio;
  final Ref ref;

  AuthService(this._dio, this.ref) {
    _plainDio = Dio(BaseOptions(
      baseUrl: ApiConstants.baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        ...ApiConstants.defaultHeaders,
        'Authorization': null,
      },
      validateStatus: (s) => s != null && s < 500,
    ));
    (_plainDio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (HttpClient client) {
      client.badCertificateCallback = (cert, host, port) => host == 'lk.msal.ru' || host == 'mail.msal.ru';
      return client;
    };
  }

  static const _secureStorage = FlutterSecureStorage();

  String? _accessToken;
  String? _refreshToken;
  UserModel? _cachedUser;
  bool _isRefreshing = false;
  bool _justLoggedIn = false;

  bool get justLoggedIn => _justLoggedIn;
  void consumeJustLoggedIn() => _justLoggedIn = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = await _secureStorage.read(key: 'access_token');
    _refreshToken = await _secureStorage.read(key: 'refresh_token');

    _setupInterceptors();

    // Restore cached user for instant UI
    final cached = prefs.getString('cached_user');
    if (cached != null) {
      try {
        _cachedUser = UserModel.fromJson(jsonDecode(cached));
      } catch (_) {}
    }
  }

  void _setupInterceptors() {

    // Inject Bearer token + preemptive refresh if close to expiry
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        // Preemptive refresh: if token expires within 5 minutes, refresh now
        if (_accessToken != null && _refreshToken != null && !_isRefreshing) {
          final exp = _jwtExpiry(_accessToken!);
          if (exp != null && exp.difference(DateTime.now()).inMinutes < 5) {
            try {
              await _tryRefresh(options);
            } catch (_) {}
          }
        }
        if (_accessToken != null && options.path != ApiConstants.auth) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        handler.next(options);
      },
    ));

    // Auto-refresh on 401 — thread-safe with QueuedInterceptorsWrapper
    _dio.interceptors.add(QueuedInterceptorsWrapper(
      onResponse: (Response response, handler) async {
        if (response.statusCode != 401) {
          handler.next(response);
          return;
        }
        
        final options = response.requestOptions;
        final path = options.path;
        final isAuthEndpoint = path == ApiConstants.auth ||
            path == ApiConstants.authRefresh ||
            path == ApiConstants.authLogout;
        
        if (isAuthEndpoint || options.extra['isRetry'] == true) {
          // Break infinite loop if the auth endpoints fail or if a retry fails again
          handler.next(response);
          return;
        }

        // Check if token was ALREADY refreshed by a previous request in the queue
        final requestAuth = options.headers['Authorization'] as String?;
        final requestToken = requestAuth?.replaceFirst('Bearer ', '');
        
        if (_accessToken != null && requestToken != _accessToken) {
          // Token is fresh! Replay without calling _tryRefresh
          options.headers['Authorization'] = 'Bearer $_accessToken';
          options.extra['isRetry'] = true;
          try {
            final retried = await _plainDio.fetch(options);
            handler.next(retried);
            return;
          } catch (_) {
            handler.next(response);
            return;
          }
        }

        // Try to refresh token and replay original request
        final retried = await _tryRefresh(options);
        if (retried != null) {
          handler.next(retried);
        } else {
          // Don't call logout() here — it wipes saved credentials,
          // making re-login impossible. Just clear in-memory tokens.
          _accessToken = null;
          _refreshToken = null;
          handler.next(response);
        }
      },
    ));

    // Logger only in debug mode, added once
    assert(() {
      if (!_dio.interceptors.any((i) => i is _Logger)) {
        _dio.interceptors.add(_Logger());
      }
      return true;
    }());
  }

  // ── JWT helpers ────────────────────────────────────────────────────────────

  /// Parse JWT to extract expiry timestamp. Returns null if unparseable.
  DateTime? _jwtExpiry(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      // Base64 decode the payload (handle padding)
      String payload = parts[1];
      switch (payload.length % 4) {
        case 2: payload += '=='; break;
        case 3: payload += '='; break;
      }
      final decoded = utf8.decode(base64Url.decode(payload));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      final exp = map['exp'];
      if (exp is int) return DateTime.fromMillisecondsSinceEpoch(exp * 1000);
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── Login ─────────────────────────────────────────────────────────────────

  Future<UserModel> login(String username, String password) async {
    try {
      // Send fresh login request
      final resp = await _dio.post(
        ApiConstants.auth,
        data: jsonEncode({'username': username, 'password': password}),
        options: Options(headers: {'Authorization': null}),
      );

      if (resp.statusCode == 401 || resp.statusCode == 403) {
        throw const AuthException('Неверный логин или пароль');
      }
      if (resp.statusCode != 200) {
        throw AuthException('Ошибка сервера: ${resp.statusCode}\n${resp.data}');
      }

      return _handleAuthResponse(resp.data as Map<String, dynamic>, username, password);
    } on AuthException { rethrow; }
    on DioException catch (e) {
      throw AuthException(_dioError(e));
    }
  }

  UserModel _handleAuthResponse(Map<String, dynamic> body, String username, String password) {
    // Extract tokens — field name confirmed from HAR: "access_token", "refresh_token"
    _accessToken = body['access_token'] as String?;
    _refreshToken = body['refresh_token'] as String?;

    if (_accessToken == null) {
      throw const AuthException('Сервер не вернул токен авторизации');
    }

    // User data is at root level of response (confirmed from HAR)
    final user = UserModel.fromJson(body);
    _cachedUser = user;

    // Rebuild Dio so interceptor uses the new token immediately

    // Persist everything
    _persist(username, password, user);
    
    _justLoggedIn = true;

    return user;
  }

  Future<void> _persist(String login, String password, UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_login', login);
    await _secureStorage.write(key: 'saved_password', value: password);
    await prefs.setString('cached_user', jsonEncode(user.toJson()));
    if (_accessToken != null) await _secureStorage.write(key: 'access_token', value: _accessToken!);
    if (_refreshToken != null) await _secureStorage.write(key: 'refresh_token', value: _refreshToken!);
  }

  // ── Session check ─────────────────────────────────────────────────────────

  Future<bool> checkSession() async {
    if (_accessToken == null) return false;
    try {
      final resp = await _dio
          .get(ApiConstants.auth)
          .timeout(const Duration(seconds: 6));
      if (resp.statusCode == 200 && resp.data is Map) {
        _cachedUser = UserModel.fromJson(resp.data as Map<String, dynamic>);
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ── Restore session on app start ──────────────────────────────────────────

  Future<UserModel?> tryRestoreSession() async {
    // Already have cached user from init()
    if (_accessToken != null) {
      // Proactively refresh the token so the very first API call doesn't 401
      // This is especially needed on Windows where the app keeps running
      if (_refreshToken != null) {
        try {
          await _tryRefresh(RequestOptions(
            path: '', method: 'GET',
            baseUrl: ApiConstants.baseUrl,
          )).timeout(const Duration(seconds: 6));
        } catch (_) {}
      }
      final alive = await checkSession();
      if (alive) return _cachedUser;
    }

    // Try re-login with saved credentials
    final prefs = await SharedPreferences.getInstance();
    final savedLogin = prefs.getString('saved_login');
    final savedPassword = await _secureStorage.read(key: 'saved_password');
    if (savedLogin != null && savedPassword != null) {
      try {
        return await login(savedLogin, savedPassword);
      } catch (e) {
        logger.log('[AUTH] Re-login failed: $e');
      }
    }

    // Return cached user for offline mode
    return _cachedUser;
  }

  // ── Token refresh ─────────────────────────────────────────────────────────

  Future<Response?> _tryRefresh(RequestOptions original) async {
    _isRefreshing = true;
    try {
      // 1. Try refresh endpoint (only if we have a refresh token)
      if (_refreshToken != null) {
        try {
          final resp = await _plainDio.post(
            ApiConstants.authRefresh,
            data: jsonEncode({'refresh_token': _refreshToken}),
            options: Options(headers: {'Authorization': null}),
          );

          if (resp.statusCode == 200 && resp.data is Map) {
            _accessToken = resp.data['access_token'] as String?;
            _refreshToken = resp.data['refresh_token'] as String?;
            if (_accessToken != null) {
              await _secureStorage.write(key: 'access_token', value: _accessToken!);
              if (_refreshToken != null) {
                await _secureStorage.write(key: 'refresh_token', value: _refreshToken!);
              }
              original.headers['Authorization'] = 'Bearer $_accessToken';
              original.extra['isRetry'] = true;
              return await _plainDio.fetch(original);
            }
          }

          // If refresh explicitly rejected (401/400), clear refresh token
          if (resp.statusCode == 401 || resp.statusCode == 400 || resp.statusCode == 404) {
            _refreshToken = null;
            await _secureStorage.delete(key: 'refresh_token');
          }
        } catch (e) {
          logger.log('[AUTH] Refresh token attempt failed: $e');
        }
      }

      // 2. Fallback: silent re-login with saved credentials
      //    (reached both when refreshToken is null AND when refresh failed)
      final prefs = await SharedPreferences.getInstance();
      final savedLogin    = prefs.getString('saved_login');
      String? savedPassword = await _secureStorage.read(key: 'saved_password');
      savedPassword ??= await _secureStorage.read(key: 'password'); // legacy fallback

      if (savedLogin != null && savedPassword != null) {
        try {
          final loginResp = await _plainDio.post(
            ApiConstants.auth,
            data: jsonEncode({'username': savedLogin, 'password': savedPassword}),
            options: Options(headers: {'Authorization': null}),
          );
          if (loginResp.statusCode == 200 && loginResp.data is Map) {
            _accessToken = loginResp.data['access_token'] as String?;
            _refreshToken = loginResp.data['refresh_token'] as String?;
            if (_accessToken != null) {
              await _secureStorage.write(key: 'access_token', value: _accessToken!);
              if (_refreshToken != null) {
                await _secureStorage.write(key: 'refresh_token', value: _refreshToken!);
              }
              _cachedUser = UserModel.fromJson(loginResp.data as Map<String, dynamic>);
              await prefs.setString('cached_user', jsonEncode(_cachedUser!.toJson()));
              
              original.headers['Authorization'] = 'Bearer $_accessToken';
              original.extra['isRetry'] = true;
              return await _plainDio.fetch(original);
            }
          }
        } catch (e) {
          logger.log('[AUTH] Re-login fallback failed: $e');
        }
      }
    } catch (_) {}
    finally {
      _isRefreshing = false;
    }
    return null;
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> logout() async {
    try { await _dio.post(ApiConstants.authLogout).timeout(const Duration(seconds: 3)); } catch (_) {}
    // Note: logout endpoint may not exist, that's fine
    _accessToken = null;
    _refreshToken = null;
    _cachedUser = null;

    // Clear persisted auth data robustly
    try {
      final prefs = await SharedPreferences.getInstance();
      try { await _secureStorage.delete(key: 'access_token'); } catch (_) {}
      try { await _secureStorage.delete(key: 'refresh_token'); } catch (_) {}
      try { await _secureStorage.delete(key: 'saved_password'); } catch (_) {}
      try { await prefs.remove('saved_login'); } catch (_) {}
      try { await prefs.remove('cached_user'); } catch (_) {}
    } catch (_) {}

    // Clear local SQLite caches (schedule, grades, homework, attendance, etc.)
    try {
      await ref.read(localDbServiceProvider).clearAllCaches().timeout(const Duration(seconds: 2));
    } catch (_) {}

    // Disconnect mail session so old account's inbox doesn't persist
    try {
      ref.read(mailServiceProvider).disconnect().ignore();
    } catch (_) {}

    // Clear MyprepodService teacher rating cache
    try {
      ref.read(myprepodServiceProvider).clearCache();
    } catch (_) {}

    logger.log('[AUTH] Logout complete — all caches cleared');
    ref.invalidate(sessionProvider);
  }

  String _dioError(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Сервер не отвечает (таймаут). Проверь интернет.';
      case DioExceptionType.unknown:
        final msg = e.error?.toString() ?? '';
        if (msg.contains('HandshakeException') || msg.contains('CERTIFICATE'))
          return 'Ошибка SSL-сертификата сервера';
        if (msg.contains('SocketException') || msg.contains('Connection refused'))
          return 'Нет подключения к lk.msal.ru:3443';
        return 'Ошибка сети: $msg';
      default:
        return e.message ?? 'Неизвестная ошибка';
    }
  }

  UserModel? get currentUser => _cachedUser;
  bool get isAuthenticated => _cachedUser != null && _accessToken != null;
  Dio get dio => _dio;
}

class _Logger extends Interceptor {
  @override
  void onRequest(RequestOptions o, RequestInterceptorHandler h) {
    final auth = o.headers['Authorization'] as String?;
    final hasToken = auth != null && auth.startsWith('Bearer ');
    logger.log('[API →] ${o.method} ${o.path}  token=${hasToken ? "✓" : "✗"}  params=${o.queryParameters}');
    h.next(o);
  }
  @override
  void onResponse(Response r, ResponseInterceptorHandler h) {
    logger.log('[API ←] ${r.statusCode} ${r.requestOptions.path}');
    h.next(r);
  }
  @override
  void onError(DioException e, ErrorInterceptorHandler h) {
    logger.log('[API ✗] ${e.type.name} ${e.requestOptions.path}: ${e.error ?? e.message}');
    h.next(e);
  }
}
