import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/chat_provider.dart';
import 'services/api_service.dart';
import 'services/voice_service.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.background,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final apiService = ApiService();
  final voiceService = VoiceService(apiService);

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ApiService>.value(value: apiService),
        ChangeNotifierProvider<VoiceService>.value(value: voiceService),
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProvider(apiService),
        ),
        ChangeNotifierProxyProvider2<ApiService, VoiceService, ChatProvider>(
          create: (ctx) => ChatProvider(apiService, voiceService),
          update: (ctx, api, voice, prev) =>
              prev ?? ChatProvider(api, voice),
        ),
      ],
      child: const JarvisApp(),
    ),
  );
}

class JarvisApp extends StatefulWidget {
  const JarvisApp({super.key});

  @override
  State<JarvisApp> createState() => _JarvisAppState();
}

class _JarvisAppState extends State<JarvisApp> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthProvider>().loadFromStorage();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Jarvis',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/login': (_) => const LoginScreen(),
        '/main': (_) => const MainScreen(),
      },
    );
  }
}
