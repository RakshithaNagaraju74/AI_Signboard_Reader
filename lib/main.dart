import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'models/sign_model.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env', isOptional: true);
    final keyLoaded =
        (dotenv.env['GROQ_API_KEY'] ?? '').trim().isNotEmpty;
    final model =
        dotenv.env['GROQ_MODEL'] ?? 'openai/gpt-oss-20b';
    final baseUrl =
        dotenv.env['GROQ_BASE_URL'] ?? 'https://api.groq.com/openai/v1';

    debugPrint(
      '[Groq] .env loaded. API key loaded=$keyLoaded, '
      'model=$model, baseUrl=$baseUrl',
    );
  } catch (e) {
    debugPrint('[Groq] .env load FAILED: ' + e.toString());
  }

  runApp(const SignboardReaderApp());
}

class SignboardReaderApp extends StatelessWidget {
  const SignboardReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SignModel(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'SightToSound',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF59D6C8),
            brightness: Brightness.dark,
            surface: const Color(0xFF111C2E),
          ).copyWith(
            primary: const Color(0xFF59D6C8),
            onPrimary: const Color(0xFF062A2A),
            secondary: const Color(0xFF9CB8FF),
            surface: const Color(0xFF111C2E),
            surfaceContainerHighest: const Color(0xFF202D43),
            outline: const Color(0xFF40516B),
          ),
          scaffoldBackgroundColor: const Color(0xFF0A1220),
          visualDensity: VisualDensity.standard,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0A1220),
            foregroundColor: Color(0xFFF4F7FC),
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          textTheme: const TextTheme(
            headlineLarge: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              height: 1.08,
            ),
            headlineMedium: TextStyle(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
            titleLarge: TextStyle(
              fontWeight: FontWeight.w750,
              letterSpacing: -0.2,
            ),
            titleMedium: TextStyle(
              fontWeight: FontWeight.w650,
            ),
            bodyLarge: TextStyle(height: 1.45),
            bodyMedium: TextStyle(height: 1.4),
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(54),
              side: const BorderSide(color: Color(0xFF40516B)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF202D43),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          progressIndicatorTheme: const ProgressIndicatorThemeData(
            color: Color(0xFF59D6C8),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
