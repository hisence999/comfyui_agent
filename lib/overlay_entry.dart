import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

@pragma("vm:entry-point")
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: MyFloatingWidget(),
  ));
}

class MyFloatingWidget extends StatefulWidget {
  const MyFloatingWidget({super.key});

  @override
  State<MyFloatingWidget> createState() => _MyFloatingWidgetState();
}

class _MyFloatingWidgetState extends State<MyFloatingWidget> {
  String _nodeName = "准备中...";
  String _stepsInfo = "";
  double _progress = 0.0;
  bool _isFinished = false;

  @override
  void initState() {
    super.initState();
    // Listen for data from main app
    FlutterOverlayWindow.overlayListener.listen((event) {
      if (event is String) {
        try {
          final data = jsonDecode(event);
          setState(() {
            _nodeName = data['node'] ?? "ComfyUI";
            _stepsInfo = data['steps'] ?? "";
            _progress = (data['progress'] ?? 0.0).toDouble();
            _isFinished = data['finished'] ?? false;
          });
        } catch (e) {
          // Fallback if not JSON
          setState(() {
            _nodeName = event;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = _isFinished 
        ? Colors.green.withOpacity(0.9) 
        : Colors.black.withOpacity(0.8);

    return Material(
      color: Colors.transparent,
      child: Center(
        child: Container(
          width: 240,
          height: 60,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white24, width: 0.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black45,
                blurRadius: 10,
                offset: Offset(0, 4),
              )
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_isFinished)
                SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    value: _progress > 0 ? _progress : null,
                    strokeWidth: 3,
                    color: Colors.blueAccent,
                  ),
                )
              else
                const Icon(Icons.check_circle, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isFinished ? "生成完成" : _nodeName,
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 13, 
                        fontWeight: FontWeight.bold
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (!_isFinished && _stepsInfo.isNotEmpty)
                      Text(
                        _stepsInfo,
                        style: const TextStyle(
                          color: Colors.white70, 
                          fontSize: 11
                        ),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                onPressed: () async {
                  await FlutterOverlayWindow.closeOverlay();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
