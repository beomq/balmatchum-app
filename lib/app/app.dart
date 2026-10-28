import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/first_meeting/meeting_theme.dart';

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
    );
  }
}
