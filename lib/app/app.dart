import 'package:flutter/material.dart';

import 'router.dart';
import 'theme.dart';

class UniHubApp extends StatelessWidget {
  const UniHubApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'UniHub',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      routerConfig: AppRouter.router,
    );
  }
}