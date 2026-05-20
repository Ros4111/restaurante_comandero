// lib/main.dart
import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main() {
  runApp(const CashlogyApp());
}

class CashlogyApp extends StatelessWidget {
  const CashlogyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'TPV Cashlogy',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF58A6FF),
          secondary: Color(0xFF3FB950),
          surface: Color(0xFF161B22),
          error: Color(0xFFF85149),
        ),
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161B22),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
