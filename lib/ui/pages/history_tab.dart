import 'dart:io';
import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/history_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../utils/theme.dart';
import '../widgets/glass_container.dart';

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> with AutomaticKeepAliveClientMixin {
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
    
    if (maxScroll - currentScroll <= 150) {
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
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () async {
          await Provider.of<HistoryProvider>(context, listen: false).refreshHistory();
        },
        edgeOffset: 120,
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
                title: const Text("执行历史", style: TextStyle(fontWeight: FontWeight.bold)),
                centerTitle: false,
                titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 16),
                background: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),
            ),

            // History List
            Consumer<HistoryProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading && provider.historyItems.isEmpty) {
                   return const SliverFillRemaining(child: Center(child: CircularProgressIndicator()));
                }
                
                if (provider.historyItems.isEmpty) {
                  return const SliverFillRemaining(child: Center(child: Text('暂无历史记录', style: TextStyle(color: Colors.grey))));
                }

                return SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final item = provider.historyItems[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: _buildHistoryCard(context, provider, item),
                        );
                      },
                      childCount: provider.historyItems.length,
                    ),
                  ),
                );
              },
            ),
            
            // Loading more indicator
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
                if (!provider.hasMore && provider.historyItems.isNotEmpty) {
                  return const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 20),
                      child: Center(child: Text("— 已显示全部记录 —", style: TextStyle(color: Colors.grey, fontSize: 12))),
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

  Widget _buildHistoryCard(BuildContext context, HistoryProvider provider, Map<String, dynamic> item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final id = item['id'] as int;
    final promptId = item['prompt_id'] as String;
    final imagePath = item['image_path'] as String;
    final createdAt = DateTime.fromMillisecondsSinceEpoch(item['created_at'] as int);

    return GestureDetector(
      onTap: () => _showHistoryDetail(context, item),
      onLongPress: () {
        HapticFeedback.heavyImpact();
        _showDeleteHistoryDialog(context, id, promptId);
      },
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: isDark ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
          boxShadow: AppTheme.softShadow(context),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 80,
                height: 80,
                color: Colors.grey.withOpacity(0.1),
                child: imagePath.isNotEmpty && File(imagePath).existsSync()
                   ? Image.file(File(imagePath), fit: BoxFit.cover, cacheWidth: 200)
                   : const Icon(CupertinoIcons.photo, color: Colors.grey),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '任务: ${promptId.substring(0, 8)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '时间: ${_formatDateTime(createdAt)}',
                    style: const TextStyle(fontSize: 12, color: AppTheme.secondaryTextColor),
                  ),
                  const SizedBox(height: 8),
                  Container(
                     padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                     decoration: BoxDecoration(
                       color: Colors.green.withOpacity(0.1),
                       borderRadius: BorderRadius.circular(4),
                     ),
                     child: const Text('已同步本地', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, size: 14, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return "${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')} "
           "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
  }

  void _showHistoryDetail(BuildContext context, Map<String, dynamic> item) {
    Map<String, dynamic> params = {};
    try {
      params = jsonDecode(item['params_json']);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, scrollController) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.all(20),
          child: ListView(
            controller: scrollController,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('历史详情', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      // 移除焦点，防止输入法闪现
                      FocusManager.instance.primaryFocus?.unfocus();
                      FocusScope.of(context).unfocus();
                      Navigator.pop(context);
                    }
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 150),
                    child: item['image_path'].toString().isNotEmpty
                        ? Image.file(File(item['image_path']))
                        : const Icon(CupertinoIcons.photo, size: 80),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('任务 ID'),
              _buildCopyableText(context, item['prompt_id']),
              
              const SizedBox(height: 20),
              _buildSectionTitle('工作流节点解析'),
              if (item['workflow_json'].toString().isEmpty) 
                const Text('无工作流数据', style: TextStyle(color: Colors.grey))
              else
                _buildParsedWorkflow(context, item['workflow_json']),
              
              const SizedBox(height: 30),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParsedWorkflow(BuildContext context, String jsonStr) {
    try {
      final Map<String, dynamic> data = jsonDecode(jsonStr);
      List<Widget> nodeWidgets = [];
      
      data.forEach((id, node) {
        if (node is Map && node['class_type'] != null) {
          final inputs = node['inputs'] as Map? ?? {};
          final title = node['_meta']?['title'] ?? node['class_type'];
          
          List<Widget> paramChips = [];
          inputs.forEach((key, val) {
            if (val is String || val is num || val is bool) {
              paramChips.add(ActionChip(
                label: Text('$key: $val', style: const TextStyle(fontSize: 11)),
                padding: EdgeInsets.zero,
                backgroundColor: Colors.blue.withOpacity(0.03),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: val.toString()));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已复制 $key'), duration: const Duration(seconds: 1)));
                },
              ));
            }
          });

          if (paramChips.isNotEmpty) {
            nodeWidgets.add(Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 0, children: paramChips),
                ],
              ),
            ));
          }
        }
      });
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: nodeWidgets);
    } catch (e) {
      return const Text('解析工作流失败', style: TextStyle(color: Colors.red, fontSize: 12));
    }
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue)),
    );
  }

  Widget _buildCopyableText(BuildContext context, String text) {
    return GestureDetector(
      onTap: () {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已复制到剪贴板'), duration: Duration(seconds: 1)));
      },
      child: Text(text, style: const TextStyle(fontSize: 14)),
    );
  }

  void _showDeleteHistoryDialog(BuildContext context, int localId, String promptId) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同步删除'),
        content: const Text('确定要删除这条记录吗？这将同时尝试清理云端历史。'),
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
