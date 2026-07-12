import 'package:flutter_riverpod/flutter_riverpod.dart';
// lib/data/services/notification_service.dart

import 'dart:io';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificationService {
  final Ref ref;
  NotificationService(this.ref);

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // flutter_local_notifications 17.x has no Windows support.
  // All methods below are no-ops on Windows until you upgrade to 18+.
  bool get _isSupported => Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isLinux;

  Future<void> init() async {
    if (_initialized) return;
    if (!_isSupported) { _initialized = true; return; }

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Moscow'));

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');

    await _plugin.initialize(
      const InitializationSettings(android: android),
    );

    // Request permissions on Android 13+
    if (Platform.isAndroid) {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }

    _initialized = true;
  }

  // ── Schedule homework deadline reminder ────────────────────────────────────

  Future<void> scheduleHomeworkReminder({
    required int id,
    required String discipline,
    required DateTime deadline,
    required String text,
  }) async {
    if (!_isSupported) return;
    if (!_initialized) await init();

    await _plugin.cancel(id);

    final deadlineDay = DateTime(deadline.year, deadline.month, deadline.day, 9, 0);
    final now = DateTime.now();
    if (deadlineDay.isBefore(now)) return;

    // 1-day-before reminder
    final dayBefore = deadlineDay.subtract(const Duration(days: 1));
    if (dayBefore.isAfter(now)) {
      await _plugin.zonedSchedule(
        id * 10 + 1,
        '📚 Завтра дедлайн',
        '$discipline: ${text.length > 60 ? text.substring(0, 60) + '...' : text}',
        tz.TZDateTime.from(dayBefore, tz.local),
        _notifDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }

    // Day-of reminder at 9:00
    if (deadlineDay.isAfter(now)) {
      await _plugin.zonedSchedule(
        id * 10 + 2,
        '🔥 Сегодня дедлайн',
        '$discipline: ${text.length > 60 ? text.substring(0, 60) + '...' : text}',
        tz.TZDateTime.from(deadlineDay, tz.local),
        _notifDetails(),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelHomeworkReminder(int id) async {
    if (!_isSupported) return;
    await _plugin.cancel(id * 10 + 1);
    await _plugin.cancel(id * 10 + 2);
  }

  Future<void> cancelAll() async {
    if (!_isSupported) return;
    await _plugin.cancelAll();
  }

  NotificationDetails _notifDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'msal_homework',
        'Домашние задания',
        channelDescription: 'Напоминания о дедлайнах домашних заданий',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      ),
    );
  }

  // ── Immediate notification (for testing) ─────────────────────────────────

  Future<void> showImmediate(String title, String body) async {
    if (!_isSupported) return;
    if (!_initialized) await init();
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      _notifDetails(),
    );
  }
}

/// Stable int ID from a lessonId string
int homeworkNotifId(String lessonId) {
  return lessonId.hashCode.abs() % 100000;
}
