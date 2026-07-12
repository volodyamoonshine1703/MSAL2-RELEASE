import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/auth_service.dart';
import '../data/services/api_service.dart';
import '../data/services/ai_service.dart';
import '../data/services/local_db_service.dart';
import '../data/services/mail_service.dart';
import '../data/services/myprepod_service.dart';
import '../data/services/chat_storage_service.dart';
import '../data/services/notification_service.dart';
import '../data/services/cross_ref_service.dart';

import 'network/dio_client.dart';

final authServiceProvider = Provider((ref) => AuthService(ref.read(dioClientProvider), ref));
final apiServiceProvider = Provider((ref) => ApiService(ref));
final aiServiceProvider = Provider((ref) => AiService(ref));
final localDbServiceProvider = Provider((ref) => LocalDbService(ref));
final mailServiceProvider = Provider((ref) => MailService(ref));
final myprepodServiceProvider = Provider((ref) => MyprepodService(ref));
final chatStorageServiceProvider = Provider((ref) => ChatStorageService(ref));
final notificationServiceProvider = Provider((ref) => NotificationService(ref));
final crossRefServiceProvider = Provider((ref) => CrossRefService(ref));


final sessionProvider = FutureProvider<bool>((ref) async {
  final auth = ref.read(authServiceProvider);

  // Fast path: cached user exists → verify/restore token before showing app
  if (auth.currentUser != null) {
    if (auth.justLoggedIn) {
      auth.consumeJustLoggedIn();
      return true; // Bypass network checks right after a successful manual login
    }

    // Try checking existing session first
    try {
      final alive = await auth.checkSession().timeout(const Duration(seconds: 4));
      if (alive) return true;
    } catch (_) {}

    // Token invalid/expired — try full re-login with saved credentials
    try {
      final user = await auth.tryRestoreSession()
          .timeout(const Duration(seconds: 8));
      if (user != null && auth.isAuthenticated) return true;
    } catch (_) {}

    // Auth completely failed — show login screen
    return false;
  }

  // No cached user: try to restore with a hard 8-second timeout
  try {
    final user = await auth.tryRestoreSession()
        .timeout(const Duration(seconds: 8));
    return user != null && auth.isAuthenticated;
  } catch (_) {
    // Timeout or network error → go to login
    return false;
  }
});
