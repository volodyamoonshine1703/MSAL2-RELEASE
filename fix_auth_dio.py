import re

filepath = 'lib/data/services/auth_service.dart'
with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Change onError to onResponse in QueuedInterceptorsWrapper
old_interceptor = '''    _dio.interceptors.add(QueuedInterceptorsWrapper(
      onError: (DioException e, handler) async {
        if (e.response?.statusCode != 401) {
          handler.next(e);
          return;
        }
        final path = e.requestOptions.path;
        final isAuthEndpoint = path == ApiConstants.auth ||
            path == ApiConstants.authRefresh ||
            path == ApiConstants.authLogout;
        if (isAuthEndpoint) {
          handler.next(e);
          return;
        }
        // Try to refresh token and replay original request
        final retried = await _tryRefresh(e.requestOptions);
        if (retried != null) {
          handler.resolve(retried);
        } else {
          handler.next(e);
        }
      },
    ));'''

new_interceptor = '''    _dio.interceptors.add(QueuedInterceptorsWrapper(
      onResponse: (Response response, handler) async {
        if (response.statusCode != 401) {
          handler.next(response);
          return;
        }
        final path = response.requestOptions.path;
        final isAuthEndpoint = path == ApiConstants.auth ||
            path == ApiConstants.authRefresh ||
            path == ApiConstants.authLogout;
        if (isAuthEndpoint) {
          handler.next(response);
          return;
        }
        // Try to refresh token and replay original request
        final retried = await _tryRefresh(response.requestOptions);
        if (retried != null) {
          handler.next(retried); // retried is a Response, so we pass it forward as if it was the original successful response
        } else {
          handler.next(response); // pass the 401 response forward
        }
      },
    ));'''

content = content.replace(old_interceptor, new_interceptor)

# 2. Add badCertificateCallback to plain Dio in _tryRefresh
old_plain_dio = '''      try {
        // Plain Dio with no interceptors — prevents recursive 401 loops
        final plain = Dio(BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Content-Type': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ));'''

new_plain_dio = '''      try {
        // Plain Dio with no interceptors — prevents recursive 401 loops
        final plain = Dio(BaseOptions(
          baseUrl: ApiConstants.baseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 10),
          headers: {'Content-Type': 'application/json'},
          validateStatus: (s) => s != null && s < 500,
        ));
        
        (plain.httpClientAdapter as IOHttpClientAdapter).onHttpClientCreate = (HttpClient client) {
          client.badCertificateCallback = (cert, host, port) => host == 'lk.msal.ru';
          return client;
        };'''

content = content.replace(old_plain_dio, new_plain_dio)

with open(filepath, 'w', encoding='utf-8') as f:
    f.write(content)

print("Fixed auth_service.dart interceptors and plain Dio.")
