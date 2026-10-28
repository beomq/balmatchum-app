import 'package:flutter/material.dart';

/// Variables of design/app-v2-pen/balmatchum-app-v2.pen (2026-09-28 palette).
abstract final class MeetingColors {
  static const surface = Color(0xFFFFF4E3);
  static const raised = Color(0xFFFFFFFF);
  static const ink = Color(0xFF50301E);
  static const muted = Color(0xFF77614E);
  static const line = Color(0xFFDECCB3);
  static const primary = Color(0xFF8A6941);
  static const primaryStrong = Color(0xFF654126);
  static const soft = Color(0xFFF1E3CA);
  static const pressed = Color(0xFFF0E8DA);
  static const green = Color(0xFFEBEEDA);
  static const warningSoft = Color(0xFFFFF1CC);
  static const error = Color(0xFFA74638);
  static const backdrop = Color(0x733D291F);

  /// Pen literals without a variable: the candidate preview stage (ONB-07)
  /// and the unselected sex choice well (ONB-08).
  static const stage = Color(0xFFE8EFE5);
  static const well = Color(0xFFFFF9F0);

  /// Pen literal without a variable: the centered breed card's shadow, ink
  /// at 12% (ONB-06 `Breed Card Main`).
  static const cardShadow = Color(0x1F50301E);
}

const _font = 'Pretendard';

/// Pen type scale entries used outside the text theme (buttons, dialogs).
TextStyle meetingType(
  double size,
  double lineHeight,
  FontWeight weight, [
  Color color = MeetingColors.ink,
]) => TextStyle(
  fontFamily: _font,
  fontSize: size,
  height: lineHeight / size,
  fontWeight: weight,
  color: color,
);

final _label = meetingType(15, 20, FontWeight.w700);
const _control = BorderRadius.all(Radius.circular(12));
const _panel = BorderRadius.all(Radius.circular(16));

ThemeData meetingTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: _font,
  scaffoldBackgroundColor: MeetingColors.surface,
  colorScheme: ColorScheme.fromSeed(
    seedColor: MeetingColors.primary,
    primary: MeetingColors.primary,
    surface: MeetingColors.surface,
    onSurface: MeetingColors.ink,
    error: MeetingColors.error,
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(
      fontSize: 24,
      height: 30 / 24,
      fontWeight: FontWeight.w800,
      color: MeetingColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: MeetingColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: MeetingColors.ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, color: MeetingColors.ink),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w500,
      color: MeetingColors.muted,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.4,
      fontWeight: FontWeight.w500,
      color: MeetingColors.muted,
    ),
  ),
  // Button/Primary: primary-strong fill keeps white labels at AA contrast.
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: MeetingColors.primaryStrong,
      foregroundColor: MeetingColors.raised,
      minimumSize: const Size(double.infinity, 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      textStyle: _label,
      shape: const RoundedRectangleBorder(borderRadius: _control),
    ),
  ),
  // Button/Quiet: raised fill with a line stroke.
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 48),
      backgroundColor: MeetingColors.raised,
      foregroundColor: MeetingColors.ink,
      side: const BorderSide(color: MeetingColors.line),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      textStyle: _label,
      shape: const RoundedRectangleBorder(borderRadius: _control),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: MeetingColors.primaryStrong,
      minimumSize: const Size(44, 44),
      textStyle: _label,
      shape: const RoundedRectangleBorder(borderRadius: _control),
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
  // Dialog/Today Reward: surface panel, 16 radius, ink shadow over backdrop.
  dialogTheme: DialogThemeData(
    backgroundColor: MeetingColors.surface,
    surfaceTintColor: Colors.transparent,
    shadowColor: MeetingColors.ink,
    elevation: 4,
    barrierColor: MeetingColors.backdrop,
    shape: const RoundedRectangleBorder(borderRadius: _panel),
    titleTextStyle: meetingType(18, 24, FontWeight.w700),
    contentTextStyle: meetingType(14, 21, FontWeight.w500, MeetingColors.muted),
    actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: MeetingColors.surface,
    modalBackgroundColor: MeetingColors.surface,
    surfaceTintColor: Colors.transparent,
    shadowColor: MeetingColors.ink,
    elevation: 4,
    modalElevation: 4,
    modalBarrierColor: MeetingColors.backdrop,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: MeetingColors.ink,
    contentTextStyle: meetingType(
      14,
      20,
      FontWeight.w500,
      MeetingColors.surface,
    ),
    shape: const RoundedRectangleBorder(borderRadius: _control),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: MeetingColors.surface,
    foregroundColor: MeetingColors.ink,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    centerTitle: false,
    titleTextStyle: meetingType(18, 24, FontWeight.w700),
  ),
  // TopBar uses the pixel back icon; AppBar back buttons follow it.
  actionIconTheme: ActionIconThemeData(
    backButtonIconBuilder: (context) => Image.asset(
      'assets/first_meeting/icons/back.png',
      width: 32,
      height: 32,
      filterQuality: FilterQuality.none,
    ),
  ),
);
