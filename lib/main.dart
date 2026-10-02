import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'models/sign_model.dart';
import 'screens/live_camera_screen.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await dotenv.load(fileName: '.env', isOptional: true);
    final keyLoaded = (dotenv.env['NARA_API_KEY'] ?? '').trim().isNotEmpty;
    debugPrint(
      '[NaraRouter] .env loaded. API key loaded=' + keyLoaded.toString()
      + ', model=' + (dotenv.env['NARA_MODEL'] ?? 'auto/bynara')
      + ', baseUrl=' + (dotenv.env['NARA_BASE_URL'] ?? 'https://router.bynara.id/v1'),
    );
  } catch (e) {
    debugPrint('[NaraRouter] .env load FAILED: ' + e.toString());
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
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
          visualDensity: VisualDensity.standard,
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
