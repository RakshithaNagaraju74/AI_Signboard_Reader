import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/sign_model.dart';
import 'screens/live_camera_screen.dart';
import 'services/tts_service.dart';
import 'services/tflite_service.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SignboardReaderApp());
}

class SignboardReaderApp extends StatefulWidget {
  const SignboardReaderApp({super.key});
  @override
  State<SignboardReaderApp> createState() => _SignboardReaderAppState();
}

class _SignboardReaderAppState extends State<SignboardReaderApp> {
  bool loading = true;
  String? error;

  @override
  void initState() {
    super.initState();
    initialize();
  }

  Future<void> initialize() async {
    try {
      await TTSService().initialize();
      await TFLiteService().initialize();
    } catch (e) {
      error = e.toString();
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const MaterialApp(
        home: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (error != null) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'AI model initialization failed.\\n\\n$error',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      );
    }
    return ChangeNotifierProvider(
      create: (_) => SignModel(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'AI Signboard Reader',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.indigo,
            brightness: Brightness.dark,
          ),
        ),
        home: const LiveCameraScreen(),
      ),
    );
  }
}
