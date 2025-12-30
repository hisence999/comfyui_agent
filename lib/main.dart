import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/settings_provider.dart';
import 'providers/workflow_provider.dart';
import 'providers/history_provider.dart';
import 'utils/theme.dart';
import 'ui/pages/home_page.dart';
import 'overlay_entry.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  
  runApp(const MyApp());
}

// Global Entry for Overlay
@pragma("vm:entry-point")
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MyFloatingWidget(),
  ));
}

class FocusUnfocusObserver extends NavigatorObserver {
  @override
  void didPop(Route route, Route? previousRoute) {
    super.didPop(route, previousRoute);
    _clearFocus();
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    super.didPush(route, previousRoute);
    _clearFocus();
  }

  void _clearFocus() {
    // 立即清除焦点
    FocusManager.instance.primaryFocus?.unfocus();
    
    // 延迟再次检查，确保焦点被清除（处理竞态条件）
    Future.delayed(const Duration(milliseconds: 100), () {
      FocusManager.instance.primaryFocus?.unfocus();
    });
    
    // 隐藏系统输入法
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => HistoryProvider()),
        ChangeNotifierProxyProvider<HistoryProvider, WorkflowProvider>(
          create: (_) => WorkflowProvider(),
          update: (_, history, workflow) => workflow!..setHistoryProvider(history),
        ),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return MaterialApp(
            title: 'ComfyUI 助手',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: settings.themeMode,
            home: const HomePage(),
            navigatorObservers: [FocusUnfocusObserver()],
          );
        },
      ),
    );
  }
}
