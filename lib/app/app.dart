import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
      theme: appFlavor == 'dev'
          ? meetingTheme()
          : ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF58636D),
              ),
              useMaterial3: true,
            ),
      routerConfig: router,
    );
  }
}
