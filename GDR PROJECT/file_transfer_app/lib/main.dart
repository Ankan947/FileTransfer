import 'package:flutter/material.dart';
import 'screens/transfer_queue_screen.dart';
import 'services/background_service.dart';

import 'package:flutter/foundation.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
    BackgroundService.initialize();
    BackgroundService.registerTransferTask();
  }
  
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      final exeDir = File(Platform.resolvedExecutable).parent.path;
      final serverPath = '$exeDir${Platform.pathSeparator}server.exe';
      if (File(serverPath).existsSync()) {
        final process = await Process.start(serverPath, ['--parent-pid', pid.toString()], workingDirectory: exeDir);
        process.stdout.listen((_) {});
        process.stderr.listen((_) {});
      }
    } catch (e) {
      debugPrint('Could not start server: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Resumable Transfer',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: const Color(0xFFFFCC00), // Pikachu Yellow
        scaffoldBackgroundColor: const Color(0xFFFFF9E6), // Light Yellow
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFCC00),
          foregroundColor: Colors.black87,
          elevation: 2,
        ),
        colorScheme: const ColorScheme.light(
          primary: Color(0xFFFFCC00), // Yellow
          secondary: Color(0xFFFF0000), // Red
          surface: Colors.white,
          onPrimary: Colors.black87,
          onSecondary: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFFCC00),
            foregroundColor: Colors.black87,
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFFFF0000),
          foregroundColor: Colors.white,
        ),
        tabBarTheme: const TabBarThemeData(
          labelColor: Colors.black87,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Color(0xFFFF0000),
        ),
      ),
      home: const TransferQueueScreen(),
    );
  }
}