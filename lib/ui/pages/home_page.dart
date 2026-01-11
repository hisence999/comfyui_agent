import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart' as ow;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import '../../mixins/unfocus_mixin.dart';
import 'workflow_tab.dart';
import 'gallery_tab.dart';
import 'history_tab.dart';
import '../widgets/glass_container.dart';
import '../../utils/theme.dart';
import '../../providers/workflow_provider.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver, UnfocusOnNavigationMixin {
  int _currentIndex = 0;
  final PageController _pageController = PageController();
  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

  // Track notification progress update
  Timer? _progressNotificationTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotifications();
    _requestPermissions();
  }

  Future<void> _initNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/launcher_icon');
    const initSettings = InitializationSettings(android: androidInit);
    await _notificationsPlugin.initialize(initSettings);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController.dispose();
    _progressNotificationTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.storage,
      Permission.photos,
    ].request();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final workflow = Provider.of<WorkflowProvider>(context, listen: false);

    if (state == AppLifecycleState.paused) {
      if (workflow.isExecuting) {
        _showOverlayWithFallback();
      }
    } else if (state == AppLifecycleState.resumed) {
      ow.FlutterOverlayWindow.closeOverlay();
      _progressNotificationTimer?.cancel();
      _notificationsPlugin.cancel(888);
    }
  }

  /// Show overlay with retry mechanism and fallback to notification
  Future<void> _showOverlayWithFallback() async {
    bool overlayShown = false;

    // Try to show overlay with retry
    for (int attempt = 0; attempt < 3; attempt++) {
      overlayShown = await _tryShowOverlay();
      if (overlayShown) break;
      await Future.delayed(const Duration(milliseconds: 200));
    }

    // Always show progress notification as primary or fallback
    _startProgressNotification(overlayShown);
  }

  /// Start periodic progress notification updates
  void _startProgressNotification(bool overlayActive) {
    _progressNotificationTimer?.cancel();

    // Update notification every second
    _progressNotificationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final workflow = Provider.of<WorkflowProvider>(context, listen: false);

      if (!workflow.isExecuting) {
        timer.cancel();
        _notificationsPlugin.cancel(888);
        return;
      }

      _showProgressNotification(
        workflow.currentNodeName,
        workflow.nodeStepsInfo ?? '',
        workflow.progress,
        overlayActive,
      );
    });

    // Show initial notification immediately
    final workflow = Provider.of<WorkflowProvider>(context, listen: false);
    _showProgressNotification(
      workflow.currentNodeName,
      workflow.nodeStepsInfo ?? '',
      workflow.progress,
      overlayActive,
    );
  }

  /// Show notification with progress bar
  Future<void> _showProgressNotification(
    String nodeName,
    String stepsInfo,
    double progress,
    bool overlayActive,
  ) async {
    final progressPercent = (progress * 100).toInt();
    final body = overlayActive
        ? '$nodeName $stepsInfo'
        : '$nodeName $stepsInfo ($progressPercent%)';

    final androidDetails = AndroidNotificationDetails(
      'comfy_progress_channel',
      '生成进度',
      channelDescription: '显示AI图片生成进度',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showWhen: true,
      showProgress: true,
      maxProgress: 100,
      progress: progressPercent,
      // Use indeterminate when progress is 0
      indeterminate: progress <= 0,
    );

    await _notificationsPlugin.show(
      888,
      'ComfyUI 生成中',
      body,
      NotificationDetails(android: androidDetails),
    );
  }

  /// Try to show overlay, returns true if successful
  Future<bool> _tryShowOverlay() async {
    try {
      // Check if overlay permission is granted
      bool isGranted = await ow.FlutterOverlayWindow.isPermissionGranted();
      print('Overlay permission granted: $isGranted');

      if (!isGranted) {
        // Request permission if not granted
        bool? granted = await ow.FlutterOverlayWindow.requestPermission();
        print('Overlay permission request result: $granted');
        if (granted != true) {
          print('Overlay permission request denied');
          return false;
        }
        // Wait for permission to be fully granted
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // Check if overlay is already active
      bool isActive = await ow.FlutterOverlayWindow.isActive();
      print('Overlay is active: $isActive');

      if (!isActive) {
        // Show overlay with optimized configuration
        await ow.FlutterOverlayWindow.showOverlay(
          enableDrag: true,
          flag: ow.OverlayFlag.defaultFlag,
          alignment: ow.OverlayAlignment.topCenter,
          visibility: ow.NotificationVisibility.visibilityPublic,
          positionGravity: ow.PositionGravity.auto,
          height: 80,
          width: ow.WindowSize.matchParent,
        );
        print('Overlay shown successfully');

        // Wait for overlay to initialize
        await Future.delayed(const Duration(milliseconds: 200));

        // Verify overlay is active
        isActive = await ow.FlutterOverlayWindow.isActive();
        return isActive;
      }
      return true;
    } catch (e) {
      print('Error showing overlay: $e');
      return false;
    }
  }

  final List<Widget> _pages = [
    const WorkflowTab(),
    const GalleryTab(),
    const HistoryTab(),
  ];

  void _onItemTapped(int index) {
    // Use mixin method for unified focus management
    unfocusBeforeNavigation();

    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
      _pageController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.clearFocus(),
      child: Scaffold(
        extendBody: true,
        body: Stack(
          children: [
            PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: _pages,
            ),

            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 60,
              right: 60,
              child: Consumer<WorkflowProvider>(
                builder: (context, workflow, _) {
                  if (!workflow.isExecuting) return const SizedBox.shrink();
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  
                  return GestureDetector(
                    onTap: () {
                      _onItemTapped(0);
                      workflow.requestScrollToRunning();
                    },
                    child: Container(
                      height: 38,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1C1C1E) : Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(19),
                        boxShadow: AppTheme.softShadow(context),
                        border: Border.all(color: isDark ? Colors.white.withOpacity(0.1) : Colors.white.withOpacity(0.1), width: 0.5),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: workflow.progress.clamp(0.0, 1.0),
                              child: Container(
                                color: Colors.blueAccent.withOpacity(0.15),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const SizedBox(
                                  width: 10,
                                  height: 10,
                                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.blueAccent),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    "${workflow.currentNodeName} ${workflow.nodeStepsInfo ?? ""}",
                                    style: TextStyle(
                                      fontSize: 12, 
                                      fontWeight: FontWeight.w600, 
                                      color: isDark ? Colors.white : Colors.black87
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '${(workflow.progress * 100).toStringAsFixed(0)}%',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blueAccent),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            Positioned(
              left: 24,
              right: 24,
              bottom: 34,
              child: GlassContainer(
                height: 64,
                borderRadius: 32,
                blur: 25,
                opacity: 0.7,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Theme(
                  data: Theme.of(context).copyWith(
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                  ),
                  child: BottomNavigationBar(
                    currentIndex: _currentIndex,
                    onTap: _onItemTapped,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    type: BottomNavigationBarType.fixed,
                    selectedItemColor: Theme.of(context).primaryColor,
                    unselectedItemColor: Colors.grey.withOpacity(0.6),
                    showUnselectedLabels: false,
                    showSelectedLabels: false,
                    items: const [
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.flowchart_fill),
                        label: '工作流',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.collections_solid),
                        label: '图库',
                      ),
                      BottomNavigationBarItem(
                        icon: Icon(CupertinoIcons.time_solid),
                        label: '历史',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
