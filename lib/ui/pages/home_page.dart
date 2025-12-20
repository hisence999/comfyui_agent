import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'workflow_tab.dart';
import 'gallery_tab.dart';
import 'history_tab.dart';
import '../widgets/glass_container.dart';
import '../../utils/theme.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.storage,
      Permission.photos,
    ].request();
  }

  final List<Widget> _pages = [
    const WorkflowTab(),
    const GalleryTab(),
    const HistoryTab(),
  ];

  void _onItemTapped(int index) {
    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
      _pageController.jumpToPage(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true, // Crucial for floating effects
      body: Stack(
        children: [
          // Content
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            children: _pages,
          ),

          // Floating Navigation Bar (Capsule Style)
          Positioned(
            left: 24,
            right: 24,
            bottom: 34, // Floating above bottom edge
            child: GlassContainer(
              height: 64,
              borderRadius: 32, // Full pill shape
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
                  showUnselectedLabels: false, // Cleaner capsule look
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
    );
  }
}
