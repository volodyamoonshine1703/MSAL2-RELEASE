import 'core/providers.dart';
// lib/main.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting('ru_RU', null);

  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  if (Platform.isAndroid || Platform.isIOS) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF0D0B14),
      systemNavigationBarIconBrightness: Brightness.light,
    ));
  }

  // Create Riverpod container to read providers before runApp
  final container = ProviderContainer();

  // Init all services in parallel where possible
  await Future.wait([
    container.read(authServiceProvider).init(),
    container.read(localDbServiceProvider).init(),
    container.read(chatStorageServiceProvider).init(),
    container.read(aiServiceProvider).loadApiKey(),
  ]);

  try {
    await container.read(notificationServiceProvider).init();
  } catch (_) {}

  runApp(UncontrolledProviderScope(container: container, child: const MsalPlusApp()));
}
