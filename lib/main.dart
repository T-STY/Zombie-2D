import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/main_menu.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const ZombieApp());
}

class ZombieApp extends StatelessWidget {
  const ZombieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'UNDEAD SIEGE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Courier',
        scaffoldBackgroundColor: Colors.black,
      ),
      home: const MainMenuScreen(),
    );
  }
}
