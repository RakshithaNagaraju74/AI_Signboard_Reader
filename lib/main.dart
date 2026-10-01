import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/sign_model.dart';
import 'screens/live_camera_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        title: 'AI Signboard Reader',
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo, brightness: Brightness.dark),
        ),
        home: const LiveCameraScreen(),
      ),
    );
  }
}