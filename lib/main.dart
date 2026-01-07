import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'widgets/auth_gate.dart';

import 'cubit/auth/auth_cubit.dart';
import 'cubit/navigation_cubit.dart';
import 'cubit/notification/notification_cubit.dart';

import 'services/auth_service.dart';
import 'services/notification_service.dart';

import 'theme/app_colors.dart';

@pragma('vm:entry-point')
Future<void> firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  FirebaseMessaging.onBackgroundMessage(firebaseBgHandler);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiRepositoryProvider(
      providers: [
        RepositoryProvider(create: (_) => AuthService()),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider(
            create: (context) =>
            AuthCubit(context.read<AuthService>())..checkAuthStatus(),
          ),
          BlocProvider(create: (_) => NavigationCubit()),
          BlocProvider(create: (_) => NotificationCubit()),
        ],
        child: Builder(
          builder: (context) {
            NotificationService.initFCMListeners(
              context.read<NotificationCubit>(),
            );

            return MaterialApp(
              title: 'Smart Farming',
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                primaryColor: AppColors.primary,
                scaffoldBackgroundColor: AppColors.background,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: AppColors.primary,
                  primary: AppColors.primary,
                  secondary: AppColors.secondary,
                ),
                useMaterial3: true,
              ),
              home: const AuthGate(),
            );
          },
        ),
      ),
    );
  }
}
