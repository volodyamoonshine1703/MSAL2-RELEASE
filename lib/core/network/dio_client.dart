import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../constants/api_constants.dart';
import '../utils/log.dart' as logger;

final dioClientProvider = Provider<Dio>((ref) {
  final dio = Dio(BaseOptions(
    baseUrl: ApiConstants.baseUrl,
    headers: Map<String, String>.from(ApiConstants.defaultHeaders),
    connectTimeout: const Duration(seconds: 12),
    receiveTimeout: const Duration(seconds: 20),
    validateStatus: (s) => s != null && s < 500,
  ));

  // Trust lk.msal.ru and mail.msal.ru self-signed certs
  (dio.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (HttpClient client) {
    client.badCertificateCallback = (cert, host, port) =>
        host == 'lk.msal.ru' || host == 'mail.msal.ru';
    return client;
  };

  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) {
      final hasToken = options.headers['Authorization'] != null;
      logger.log('[API →] ${options.method} ${options.path}  token=${hasToken ? "✓" : "✗"}  params=${options.queryParameters}');
      return handler.next(options);
    },
    onResponse: (response, handler) {
      logger.log('[API ←] ${response.statusCode} ${response.requestOptions.path}');
      return handler.next(response);
    },
    onError: (e, handler) {
      logger.log('[API ✗] ${e.type.name} ${e.requestOptions.path}: ${e.message}');
      return handler.next(e);
    },
  ));

  return dio;
});
