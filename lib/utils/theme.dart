// lib/utils/theme.dart
import 'package:flutter/material.dart';

class AppTheme {
  static const colorFondo       = Color(0xFF0D0D0D);
  static const colorSuperficie  = Color(0xFF1A1A1A);
  static const colorTarjeta     = Color(0xFF242424);
  static const colorPrimario    = Color(0xFF2979FF);
  static const colorAcento      = Color(0xFFFF1744);
  static const colorTexto       = Colors.white;
  static const colorTextoGris   = Color(0xFFAAAAAA);
  static const colorCategorias  = Color(0xFF1565C0);
  static const colorProductoNormal = Colors.white;
  static const colorProductoPersonalizable = Color(0xFFFF1744);
  static const colorLineasNuevas = Color(0xFFFF1744);
  static const colorLineasViejas = Colors.white;

  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: colorFondo,
    colorScheme: const ColorScheme.dark(
      primary:   colorPrimario,
      secondary: colorAcento,
      surface:   colorSuperficie,
    ),
    textTheme: const TextTheme(
      bodyLarge:  TextStyle(color: colorTexto,     fontSize: 18),
      bodyMedium: TextStyle(color: colorTexto,     fontSize: 16),
      titleLarge: TextStyle(color: colorTexto,     fontSize: 22, fontWeight: FontWeight.bold),
      labelLarge: TextStyle(color: colorTexto,     fontSize: 18, fontWeight: FontWeight.w600),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colorPrimario,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF111111),
      foregroundColor: colorTexto,
      elevation: 0,
      titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colorTexto),
    ),
    dividerColor: Color(0xFF333333),
  );
}
