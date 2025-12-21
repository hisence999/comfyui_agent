import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/history_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../utils/theme.dart';

class GalleryTab extends StatefulWidget {
  const GalleryTab({super.key});

  @override
  State<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<GalleryTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HistoryProvider>(context, listen: false).refreshHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomScrollView(
      slivers: [
        // Frosted AppBar with Large Title
        SliverAppBar.large(
          expandedHeight: 120.0,
          stretch: true,
          pinned: false, // Hide completely on scroll
          floating: true,
          snap: true,
          elevation: 0,
          backgroundColor: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.7),
          flexibleSpace: FlexibleSpaceBar(
            title: const Text("生成图库", style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: false,
            titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 16),
            background: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
        ),

        // Gallery Grid
        Consumer<HistoryProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading && provider.imageUrls.isEmpty) {
               return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
            }
            
            if (provider.imageUrls.isEmpty) {
              return const SliverFillRemaining(child: Center(child: Text('暂无生成图片', style: TextStyle(color: Colors.grey))));
            }

            return SliverPadding(
              padding: const EdgeInsets.all(12),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                itemBuilder: (context, index) {
                  final path = provider.imageUrls[index];
                  return GestureDetector(
                  onTap: () async {
                    final imageProvider = FileImage(File(path));
                      await precacheImage(imageProvider, context);
                      if (!mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => _FullScreenGallery(
                            imagePaths: provider.imageUrls,
                            initialIndex: index,
                          ),
                        ),
                      );
                    },
                    onLongPress: () {
                      HapticFeedback.heavyImpact(); // Keep for long press
                      _showDeleteDialog(context, provider, index);
                    },
                    child: Hero(
                      tag: path,
                      child: Container(
                        decoration: BoxDecoration(
                          boxShadow: AppTheme.softShadow(context),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                          child: Image.file(
                            File(path),
                            cacheWidth: 300,
                            errorBuilder: (context, error, stackTrace) => Container(
                              height: 200, color: Colors.grey.withOpacity(0.2), child: const Icon(Icons.error)
                            ),
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: provider.imageUrls.length,
              ),
            );
          },
        ),
        
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  void _showDeleteDialog(BuildContext context, HistoryProvider provider, int index) {
    final path = provider.imageUrls[index];
    final item = provider.historyItems.firstWhere((element) => element['image_path'] == path);
    final promptId = item['prompt_id'] as String;
    final localId = item['id'] as int;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同步删除图片'),
        content: const Text('确定要删除这张图片及相关的云端记录吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              Provider.of<WorkflowProvider>(context, listen: false).deleteHistoryWithSync(localId, promptId);
              Navigator.pop(context);
            },
            child: const Text('同步删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class _FullScreenGallery extends StatefulWidget {
  final List<String> imagePaths;
  final int initialIndex;

  const _FullScreenGallery({required this.imagePaths, required this.initialIndex});

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PhotoViewGallery.builder(
            scrollPhysics: const BouncingScrollPhysics(),
            builder: (context, index) {
              final path = widget.imagePaths[index];
              return PhotoViewGalleryPageOptions(
                imageProvider: FileImage(File(path)),
                initialScale: PhotoViewComputedScale.contained,
                minScale: PhotoViewComputedScale.contained,
                maxScale: PhotoViewComputedScale.covered * 2,
                heroAttributes: PhotoViewHeroAttributes(tag: path),
              );
            },
            itemCount: widget.imagePaths.length,
            loadingBuilder: (context, event) => const Center(child: CircularProgressIndicator()),
            pageController: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
          ),
          
          // Back Button
          Positioned(
            top: 10,
            left: 10,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
          ),
          
          // Info Button
          Positioned(
            top: 10,
            right: 10,
            child: SafeArea(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.white, size: 20),
                  onPressed: () => _showParams(context),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showParams(BuildContext context) async {
    final path = widget.imagePaths[_currentIndex];
    final provider = Provider.of<HistoryProvider>(context, listen: false);
    final item = provider.historyItems.firstWhere((element) => element['image_path'] == path);
    
    // Get Resolution
    final file = File(path);
    String size = "未知";
    try {
      final bytes = await file.readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      size = '${frame.image.width} x ${frame.image.height}';
    } catch (_) {}

    // Construct public path hint for Android
    String publicPath = path;
    if (Platform.isAndroid && path.contains('comfy_images')) {
      final filename = path.split('/').last;
      publicPath = "/storage/emulated/0/Download/comfyui_client/$filename";
    }

    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.5,
          maxChildSize: 0.7,
          builder: (_, scrollController) => Container(
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(20),
            child: ListView(
              controller: scrollController,
              children: [
                const Text('图片属性', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                _buildInfoTag(context, '文件名', path.split('/').last),
                _buildInfoTag(context, '分辨率', size),
                _buildInfoTag(context, '公共存储路径', publicPath, isLong: true),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => _openFolder(path),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('打开所在文件夹'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent.withOpacity(0.1),
                    foregroundColor: Colors.blueAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openFolder(String path) async {
    final folderPath = File(path).parent.path;
    final Uri uri = Uri.parse("file://$folderPath");
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      // Fallback or show error
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法直接打开文件夹，请在文件管理器中查看 Download/comfyui_client')),
        );
      }
    }
  }

  Widget _buildInfoTag(BuildContext context, String label, String value, {bool isLong = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: value));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 $label')));
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.03),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(value, style: TextStyle(fontSize: 13, color: isLong ? Colors.grey : null)),
            ),
          ),
        ],
      ),
    );
  }
}
