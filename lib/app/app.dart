import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/first_meeting/meeting_theme.dart';

/// Largest system text scale the app follows. Owner decision (2026-10-28):
/// larger sizes broke the pixel layouts.
const maxTextScale = 1.15;

class BalmatchumApp extends StatelessWidget {
  const BalmatchumApp({required this.router, super.key});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Balmatchum',
      debugShowCheckedModeBanner: false,
      // Every flavor ships the design theme; prod had kept the bootstrap seed.
      theme: meetingTheme(),
      routerConfig: router,
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: maxTextScale,
        child: child!,
      ),
    );
  }
}
