import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import '../widgets/glass_container.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _portController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    _ipController.text = settings.ipAddress;
    _portController.text = settings.port;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('连接设置', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _ipController,
                    decoration: const InputDecoration(labelText: 'IP 地址'),
                    onChanged: (val) => _saveSettings(),
                  ),
                  TextField(
                    controller: _portController,
                    decoration: const InputDecoration(labelText: '端口'),
                    keyboardType: TextInputType.number,
                    onChanged: (val) => _saveSettings(),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            GlassContainer(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('外观', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Consumer<SettingsProvider>(
                    builder: (context, settings, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('主题模式'),
                          CupertinoSegmentedControl<ThemeMode>(
                            children: const {
                              ThemeMode.system: Text('跟随系统'),
                              ThemeMode.light: Text('浅色'),
                              ThemeMode.dark: Text('深色'),
                            },
                            groupValue: settings.themeMode,
                            onValueChanged: (ThemeMode value) {
                              settings.setThemeMode(value);
                            },
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveSettings() {
    Provider.of<SettingsProvider>(context, listen: false).setAddress(
      _ipController.text,
      _portController.text,
    );
  }
}
