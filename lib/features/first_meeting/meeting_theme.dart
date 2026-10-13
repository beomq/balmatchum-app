import 'package:flutter/material.dart';

abstract final class MeetingColors {
  static const surface = Color(0xFFFFF4E3);
  static const ink = Color(0xFF50301E);
  static const muted = Color(0xFF77614E);
  static const line = Color(0xFFDECCB3);
  static const primary = Color(0xFF8A6941);
  static const soft = Color(0xFFF1E3CA);
  static const pressed = Color(0xFFF0E8DA);
  static const green = Color(0xFFEBEEDA);
}

ThemeData meetingTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Pretendard',
  scaffoldBackgroundColor: MeetingColors.surface,
  colorScheme: ColorScheme.fromSeed(
    seedColor: MeetingColors.primary,
    primary: MeetingColors.primary,
    surface: MeetingColors.surface,
    onSurface: MeetingColors.ink,
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: MeetingColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: MeetingColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: MeetingColors.ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, color: MeetingColors.ink),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.45,
      color: MeetingColors.muted,
    ),
    bodySmall: TextStyle(fontSize: 12, height: 1.4, color: MeetingColors.muted),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 48),
      foregroundColor: MeetingColors.ink,
      side: const BorderSide(color: MeetingColors.line),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.all(16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: MeetingColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: MeetingColors.line),
    ),
  ),
);
