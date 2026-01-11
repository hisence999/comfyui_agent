import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../../mixins/unfocus_mixin.dart';
import '../../providers/history_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../utils/theme.dart';

class GalleryTab extends StatefulWidget {
  const GalleryTab({super.key});

  @override
  State<GalleryTab> createState() => _GalleryTabState();
}

class _GalleryTabState extends State<GalleryTab> with AutomaticKeepAliveClientMixin, UnfocusOnNavigationMixin {
  final ScrollController _scrollController = ScrollController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<HistoryProvider>(context, listen: false);
      if (provider.historyItems.isEmpty) {
        provider.refreshHistory();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    
    // Trigger load more when 200px from bottom
    if (maxScroll - currentScroll <= 200) {
      final provider = Provider.of<HistoryProvider>(context, listen: false);
      if (!provider.isLoadingMore && provider.hasMore) {
        provider.loadMoreHistory();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          await Provider.of<HistoryProvider>(context, listen: false).refreshHistory();
        },
        edgeOffset: 100,
        child: CustomScrollView(
          controller: _scrollController,
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            // Frosted AppBar with Large Title
            SliverAppBar.large(
              expandedHeight: 120.0,
              stretch: true,
              pinned: false,
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
          actions: [
            IconButton(
              icon: const Icon(CupertinoIcons.refresh_bold, size: 20),
              onPressed: () {
                HapticFeedback.mediumImpact();
                Provider.of<HistoryProvider>(context, listen: false).syncLocalImages();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('正在扫描本地缺失图片...'), duration: Duration(seconds: 2)),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),

            // Gallery Grid
            Consumer<HistoryProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.imageUrls.isEmpty) {
                   return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
                }
                
                if (provider.imageUrls.isEmpty) {
                  return const SliverFillRemaining(
                    child: Center(child: Text('暂无生成图片', style: TextStyle(color: Colors.grey)))
                  );
                }

                return SliverPadding(
                  padding: const EdgeInsets.all(12),
                  sliver: SliverMasonryGrid.count(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childCount: provider.imageUrls.length,
                    itemBuilder: (context, index) {
                      final path = provider.imageUrls[index];
                      
                      return RepaintBoundary(
                        child: GestureDetector(
                          onTap: () async {
                            final imageProvider = FileImage(File(path));
                            await precacheImage(imageProvider, context);
                            if (!mounted) return;
                            Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder: (context, animation, secondaryAnimation) => _FullScreenGallery(
                                  imagePaths: provider.imageUrls,
                                  initialIndex: index,
                                ),
                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                  return FadeTransition(opacity: animation, child: child);
                                },
                              ),
                            );
                          },
                          onLongPress: () {
                            HapticFeedback.heavyImpact();
                            _showDeleteDialog(context, provider, index);
                          },
                          child: Hero(
                            tag: path,
                            child: Container(
                              decoration: BoxDecoration(
                                boxShadow: AppTheme.softShadow(context),
                                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                                child: Image.file(
                                  File(path),
                                  cacheWidth: 350,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => Container(
                                    height: 200, color: Colors.grey.withOpacity(0.2), child: const Icon(Icons.error)
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
            
            // Bottom Loading Indicator / Finish line
            Consumer<HistoryProvider>(
              builder: (context, provider, child) {
                if (provider.isLoadingMore) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: CircularProgressIndicator.adaptive()),
                    ),
                  );
                }
                if (!provider.hasMore && provider.imageUrls.isNotEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text("— 到底了 —", style: TextStyle(color: Colors.grey, fontSize: 12))),
                    ),
                  );
                }
                return const SliverToBoxAdapter(child: SizedBox(height: 100));
              },
            ),
          ],
        ),
      ),
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
            child: const Text('删除', style: TextStyle(color: Colors.red)),
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

class _FullScreenGalleryState extends State<_FullScreenGallery> with UnfocusOnNavigationMixin {
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
                  onPressed: () => popWithUnfocus(),
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
                  onPressed: () {
                    _showParams(context);
                  },
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

    // 构造公共路径提示
    String publicPath = path;
    final filename = path.split('/').last;
    
    // 如果路径包含应用私有目录，显示映射的公共路径
    if (Platform.isAndroid) {
      if (path.contains('comfy_images')) {
        // 旧路径：应用私有目录，映射到Download目录
        publicPath = "/storage/emulated/0/Download/comfyui_client/$filename";
      } else if (path.contains('Pictures/comfyui_client')) {
        // 新路径：Pictures目录，已经是公共路径
        publicPath = path;
      }
    } else if (Platform.isIOS) {
      if (path.contains('Documents/comfy_images')) {
        // 旧路径：应用私有目录
        publicPath = "应用私有目录/$filename";
      } else if (path.contains('Documents/Pictures/comfyui_client')) {
        // 新路径：Pictures目录
        publicPath = "Pictures/comfyui_client/$filename";
      }
    }

    if (context.mounted) {
      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.4,
          maxChildSize: 0.6,
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
    try {
      final folderPath = File(path).parent.path;
      // Using open_filex to open the folder
      final result = await OpenFilex.open(folderPath);
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('无法打开文件夹: ${result.message}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('打开文件夹失败，请手动在文件管理器中查看')),
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
