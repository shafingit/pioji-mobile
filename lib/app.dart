import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/connectivity/connectivity_provider.dart';
import 'core/design/theme.dart';
import 'core/router/app_router.dart';
import 'core/storage/prefs.dart';
import 'features/masters/data/lookup_refresh.dart';

class TeaErpApp extends ConsumerWidget {
  const TeaErpApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Back online: load again any dropdown list that failed while offline.
    ref.listen(isOnlineProvider, (prev, next) {
      if (prev?.value == false && next.value == true) refreshFailedLookups(ref);
    });
    return MaterialApp.router(
      title: 'Pioji',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(appRouterProvider),
      // Status and navigation bar icons follow the app's theme, not only the
      // phone's, so a Light choice on a dark phone keeps them readable.
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          ),
          child: child!,
        );
      },
      locale: const Locale('en', 'IN'),
      supportedLocales: const [Locale('en', 'IN'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
    );
  }
}
