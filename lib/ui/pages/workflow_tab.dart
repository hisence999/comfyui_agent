import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../mixins/unfocus_mixin.dart';
import '../../providers/settings_provider.dart';
import '../../providers/workflow_provider.dart';
import '../../utils/theme.dart';
import '../widgets/glass_container.dart';
import 'parameter_editor.dart';

class WorkflowTab extends StatefulWidget {
  const WorkflowTab({super.key});

  @override
  State<WorkflowTab> createState() => _WorkflowTabState();
}

class _WorkflowTabState extends State<WorkflowTab> with AutomaticKeepAliveClientMixin, UnfocusOnNavigationMixin {
  final TextEditingController _ipController = TextEditingController();
  final FocusNode _ipFocusNode = FocusNode(skipTraversal: true);
  final ScrollController _scrollController = ScrollController();
  String? _lastSyncedAddress;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Initial value will be set in build when settings are loaded
  }

  @override
  void dispose() {
    _ipFocusNode.dispose();
    _scrollController.dispose();
    _ipController.dispose();
    super.dispose();
  }

  /// Sync IP field with settings when settings change (e.g., after async load)
  void _syncIpFieldIfNeeded(SettingsProvider settings) {
    // Only sync when user is not actively editing
    if (_ipFocusNode.hasFocus) return;

    final savedAddress = '${settings.ipAddress}:${settings.port}';

    // Sync if this is a new address from settings (loaded from SharedPreferences)
    if (_lastSyncedAddress != savedAddress) {
      _ipController.text = savedAddress;
      _lastSyncedAddress = savedAddress;
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Handle jump to running request
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<WorkflowProvider>(context, listen: false);
      if (provider.shouldScrollToRunning) {
        provider.resetScrollRequest();
        _scrollToRunning(provider);
      }
    });

    return CustomScrollView(
      controller: _scrollController,
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
            title: const Text("AI 工作流", style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: false,
            titlePadding: const EdgeInsetsDirectional.only(start: 20, bottom: 12),
            background: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(color: Colors.transparent),
              ),
            ),
          ),
          actions: [
            IconButton(
              icon: Consumer<SettingsProvider>(
                builder: (context, settings, _) => Icon(
                  settings.themeMode == ThemeMode.dark 
                      ? CupertinoIcons.moon_fill 
                      : CupertinoIcons.sun_max_fill,
                ),
              ),
              onPressed: () {
                final settings = Provider.of<SettingsProvider>(context, listen: false);
                settings.setThemeMode(settings.themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
              },
            ),
            const SizedBox(width: 8),
          ],
        ),

        // Connection & Import Section
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: Column(
              children: [
                const SizedBox(height: 10),
                _buildTopBar(context),
                const SizedBox(height: 20),
                _buildImportButton(context),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),

        // Workflow List
        Consumer<WorkflowProvider>(
          builder: (context, provider, child) {
            final workflows = provider.savedWorkflows;
            if (workflows.isEmpty) {
              return const SliverFillRemaining(
                child: Center(child: Text('暂无导入的工作流', style: TextStyle(color: Colors.grey))),
              );
            }
            
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final wf = workflows[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildWorkflowCard(context, provider, wf),
                    );
                  },
                  childCount: workflows.length,
                ),
              ),
            );
          },
        ),
        
        // Bottom padding for nav bar
        const SliverToBoxAdapter(child: SizedBox(height: 100)),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer2<SettingsProvider, WorkflowProvider>(
      builder: (context, settings, workflow, child) {
        // Sync IP field with persisted settings (handles async load from SharedPreferences)
        _syncIpFieldIfNeeded(settings);

        return Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppTheme.softShadow(context),
          ),
          child: Row(
            children: [
              Icon(
                workflow.isConnected ? CupertinoIcons.wifi : CupertinoIcons.wifi_slash,
                color: workflow.isConnected ? Colors.green : Colors.red,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _ipController,
                  focusNode: _ipFocusNode,
                  autofocus: false,
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    hintText: 'IP:Port',
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                  onSubmitted: (value) {
                    _ipFocusNode.unfocus();
                    _connect(settings, workflow);
                  },
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.arrow_2_circlepath, size: 20),
                onPressed: () => _connect(settings, workflow),
              ),
            ],
          ),
        );
      },
    );
  }

  void _connect(SettingsProvider settings, WorkflowProvider workflow) {
    final input = _ipController.text;
    final parts = input.split(':');
    if (parts.length == 2) {
      settings.setAddress(parts[0], parts[1]);
      workflow.connect(parts[0], parts[1]);
    } else {
       settings.setAddress(parts[0], '8188');
       workflow.connect(parts[0], '8188');
    }
  }

  Widget _buildImportButton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: () async {
        FilePickerResult? result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['json'],
        );

        if (result != null) {
          File file = File(result.files.single.path!);
          String content = await file.readAsString();
          String name = result.files.single.name.replaceAll('.json', '');
          try {
             jsonDecode(content);
             Provider.of<WorkflowProvider>(context, listen: false).importWorkflow(name, content);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无效的 JSON 文件')));
          }
        }
      },
      child: Container(
        height: 80,
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isDark ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
          boxShadow: AppTheme.softShadow(context),
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.add_circled, size: 24, color: Theme.of(context).primaryColor),
              const SizedBox(width: 10),
              const Text('导入工作流', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWorkflowCard(BuildContext context, WorkflowProvider provider, dynamic wf) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = provider.currentWorkflowId == wf.id;
    // Bind progress UI strictly to runningWorkflowId
    final isRunning = provider.runningWorkflowId == wf.id && provider.isExecuting;

    return GestureDetector(
      onTap: () {
        provider.loadWorkflow(wf.id, wf.jsonContent);
        Navigator.push(context, MaterialPageRoute(builder: (context) => const ParameterEditor()));
      },
      onLongPress: () {
        HapticFeedback.heavyImpact();
        _showDeleteWorkflowDialog(context, provider, wf.id);
      },
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isDark ? Colors.black : Colors.white,
          borderRadius: BorderRadius.circular(AppTheme.cardRadius),
          border: Border.all(
            color: isEditing ? Colors.blue.withOpacity(0.5) : (isDark ? Colors.white.withOpacity(0.1) : Colors.transparent),
            width: isEditing ? 2 : 1,
          ),
          boxShadow: AppTheme.softShadow(context),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(wf.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                        const SizedBox(height: 6),
                        Text(
                          '${wf.jsonContent.length} 个节点', 
                          style: const TextStyle(fontSize: 13, color: AppTheme.secondaryTextColor)
                        ),
                        if (isRunning) ...[
                          const SizedBox(height: 12),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(CupertinoIcons.gear_alt, size: 14, color: Colors.blueAccent),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            provider.currentNodeName,
                                            style: const TextStyle(fontSize: 12, color: Colors.blueAccent, fontWeight: FontWeight.bold),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (provider.nodeStepsInfo != null)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 18.0, top: 2),
                                        child: Text(
                                          provider.nodeStepsInfo!,
                                          style: const TextStyle(fontSize: 11, color: Colors.blueAccent),
                                        ),
                                      ),
                                  ],
                                ),
                        ]
                      ],
                    ),
                  ),
                  if (isRunning)
                    IconButton(
                      icon: const Icon(CupertinoIcons.stop_circle, color: Colors.red),
                      onPressed: () => provider.cancelExecution(),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: Icon(CupertinoIcons.chevron_right, color: isDark ? Colors.grey[700] : Colors.grey[300], size: 16),
                    ),
                ],
              ),
            ),
            if (isRunning)
              Positioned.fill(
                child: IgnorePointer(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: provider.progress.clamp(0.0, 1.0),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.08),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _scrollToRunning(WorkflowProvider provider) {
    if (provider.runningWorkflowId == null) return;
    
    final index = provider.savedWorkflows.indexWhere((w) => w.id == provider.runningWorkflowId);
    if (index != -1) {
      // Estimate position: header (200) + cards (100 each)
      // This is a heuristic since we don't have item heights
      double offset = 200.0 + (index * 120.0); 
      _scrollController.animateTo(
        offset.clamp(0, _scrollController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _showDeleteWorkflowDialog(BuildContext context, WorkflowProvider provider, String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除工作流'),
        content: const Text('确定要删除这个工作流吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () {
              provider.deleteWorkflow(id);
              Navigator.pop(context);
            },
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
