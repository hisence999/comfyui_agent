import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../mixins/unfocus_mixin.dart';
import '../../providers/workflow_provider.dart';
import '../../utils/theme.dart';

class ParameterEditor extends StatefulWidget {
  const ParameterEditor({super.key});

  @override
  State<ParameterEditor> createState() => _ParameterEditorState();
}

class _ParameterEditorState extends State<ParameterEditor> with UnfocusOnNavigationMixin {
  Timer? _debounce;
  Map<String, dynamic> _localWorkflow = {};

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<WorkflowProvider>(context, listen: false);
    if (provider.currentWorkflow != null) {
      _localWorkflow = jsonDecode(jsonEncode(provider.currentWorkflow!));
    }
  }

  void _updateLocalState() {
    setState(() {}); // Force local UI refresh
  }

  void _onParamChanged() {
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
       final provider = Provider.of<WorkflowProvider>(context, listen: false);
       provider.loadWorkflow(provider.currentWorkflowId, _localWorkflow);
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final provider = Provider.of<WorkflowProvider>(context);

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 100.0,
            stretch: true,
            pinned: true,
            elevation: 0,
            backgroundColor: isDark ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.7),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              onPressed: () => popWithUnfocus(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text("参数调节", style: TextStyle(fontWeight: FontWeight.bold)),
              centerTitle: true,
              background: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(color: Colors.transparent),
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.play_arrow_solid, size: 20),
                onPressed: () async {
                  HapticFeedback.mediumImpact();
                  try {
                    await Provider.of<WorkflowProvider>(context, listen: false).queuePrompt();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加到队列'), duration: Duration(seconds: 1)));
                    }
                  } catch (e) {
                    if (mounted) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('运行错误'),
                          content: Text(e.toString().replaceAll('Exception: ', '')),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context), child: const Text('了解')),
                          ],
                        ),
                      );
                    }
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          if (_localWorkflow.isEmpty)
            const SliverFillRemaining(child: Center(child: Text('未加载工作流')))
          else
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final key = _localWorkflow.keys.elementAt(index);
                    final node = _localWorkflow[key] as Map<String, dynamic>;
                    return Padding(
                      key: ValueKey("node_$key"),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _buildNodeItem(node, provider.objectInfo),
                    );
                  },
                  childCount: _localWorkflow.length,
                ),
              ),
            ),
          
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildNodeItem(Map<String, dynamic> node, Map<String, dynamic> objectInfo) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputs = node['inputs'] as Map<String, dynamic>;
    final classType = node['class_type'] as String;
    final title = node['_meta']?['title'] ?? classType;

    if (classType == 'LoadImage') {
       return _buildLoadImageCard(node);
    }

    final editableKeys = inputs.keys.where((key) {
      final val = inputs[key];
      if (val is List) return false;
      if (val is String || val is num || val is bool) return true;
      return false;
    }).toList();

    if (editableKeys.isEmpty) return const SizedBox.shrink();

    // Get server metadata for this node type
    final nodeInfo = objectInfo[classType];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          subtitle: Text(classType, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedAlignment: Alignment.topLeft,
          children: editableKeys.map((key) {
            final val = inputs[key];
            
            // Check if this input has predefined options (dropdown)
            List<String>? options;
            if (nodeInfo != null && nodeInfo['input'] != null) {
              final required = nodeInfo['input']['required'] as Map?;
              final optional = nodeInfo['input']['optional'] as Map?;
              final inputMeta = required?[key] ?? optional?[key];
              if (inputMeta is List && inputMeta.isNotEmpty && inputMeta[0] is List) {
                options = List<String>.from(inputMeta[0]);
              }
            }

            return NodeInputWidget(
              key: ValueKey("${node.hashCode}_$key"),
              label: key,
              value: val,
              options: options,
              onChanged: (newVal) {
                inputs[key] = newVal;
                _updateLocalState();
                _onParamChanged();
              },
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLoadImageCard(Map<String, dynamic> node) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inputs = node['inputs'] as Map<String, dynamic>;
    final title = node['_meta']?['title'] ?? '加载图像';
    
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.black : Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.cardRadius),
        border: isDark ? Border.all(color: Colors.white.withOpacity(0.1)) : null,
        boxShadow: AppTheme.softShadow(context),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Text('LoadImage', style: TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('当前选择', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(inputs['image'].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  color: Theme.of(context).primaryColor,
                  borderRadius: BorderRadius.circular(10),
                  onPressed: () => _pickAndUploadImage(inputs),
                  child: const Text('上传', style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAndUploadImage(Map<String, dynamic> inputs) async {
    HapticFeedback.lightImpact();
    FilePickerResult? result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result != null) {
      File file = File(result.files.single.path!);
      final provider = Provider.of<WorkflowProvider>(context, listen: false);
      
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('正在上传图片...')));
      String? serverFileName = await provider.uploadImage(file);
      
      if (serverFileName != null) {
        setState(() { inputs['image'] = serverFileName; });
        _onParamChanged();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传成功')));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('上传失败')));
      }
    }
  }
}

class NodeInputWidget extends StatefulWidget {
  final String label;
  final dynamic value;
  final List<String>? options;
  final Function(dynamic) onChanged;

  const NodeInputWidget({
    super.key, 
    required this.label, 
    required this.value, 
    this.options,
    required this.onChanged
  });

  @override
  State<NodeInputWidget> createState() => _NodeInputWidgetState();
}

class _NodeInputWidgetState extends State<NodeInputWidget> {
  late TextEditingController _controller;
  String _seedMode = 'randomize';
  double? _draggingValue;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toString());
  }

  @override
  void didUpdateWidget(covariant NodeInputWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value.toString() != _controller.text && !FocusScope.of(context).hasFocus && _draggingValue == null) {
      _controller.text = widget.value.toString();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final key = widget.label;
    final value = widget.value;

    // Handle Dropdown Options (Models, LoRAs, Samplers, etc.)
    if (widget.options != null && widget.options!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Text(key, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: widget.options!.contains(value.toString()) ? value.toString() : null,
                isExpanded: true,
                dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                hint: Text('选择 $key', style: const TextStyle(fontSize: 14)),
                items: widget.options!.map((String val) {
                  return DropdownMenuItem<String>(
                    value: val,
                    child: Text(val, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                  );
                }).toList(),
                onChanged: (newVal) {
                  if (newVal != null) {
                    HapticFeedback.selectionClick();
                    _controller.text = newVal;
                    widget.onChanged(newVal);
                    setState(() {});
                  }
                },
              ),
            ),
          ),
        ],
      );
    }

    if (key == 'seed' || key == 'noise_seed') {
       return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(key, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<String>(
                  value: _seedMode,
                  isDense: true,
                  underline: const SizedBox(),
                  dropdownColor: isDark ? Colors.grey[900] : Colors.white,
                  items: ['fixed', 'increment', 'decrement', 'randomize'].map((String val) {
                    return DropdownMenuItem<String>(
                      value: val,
                      child: Text(val, style: const TextStyle(fontSize: 12)),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _seedMode = val);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(isDense: true, border: InputBorder.none),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (val) {
                      final n = num.tryParse(val);
                      if (n != null) widget.onChanged(n);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(CupertinoIcons.arrow_2_circlepath, size: 18),
                onPressed: () {
                   final rand = Random().nextInt(1000000000);
                   _controller.text = rand.toString();
                   widget.onChanged(rand);
                },
              ),
            ],
          ),
        ],
      );
    }
    
    if (key == 'denoise' || key == 'steps' || key == 'cfg') {
      double min = 0;
      double max = 1;
      bool isInt = false;
      if (key == 'steps') { min = 1; max = 100; isInt = true; }
      if (key == 'cfg') { min = 1; max = 30; isInt = true; }
      double sliderVal = _draggingValue ?? ((value is num) ? value.toDouble() : min);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(key, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
              Text(sliderVal.toStringAsFixed(isInt ? 0 : 2), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue)),
            ],
          ),
          Slider(
            value: sliderVal.clamp(min, max),
            min: min,
            max: max,
            activeColor: Colors.blue,
            onChanged: (val) {
              final finalVal = isInt ? val.round() : val;
              setState(() {
                _draggingValue = val;
                _controller.text = finalVal.toString();
              });
              widget.onChanged(finalVal);
            },
            onChangeEnd: (val) {
              setState(() => _draggingValue = null);
            },
          ),
        ],
      );
    }

    if (value is bool) {
      return Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(key, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
            CupertinoSwitch(
              value: value,
              activeColor: Colors.blue,
              onChanged: (val) {
                 widget.onChanged(val);
                 setState(() {});
              },
            ),
          ],
        ),
      );
    }

    final isLongText = (value is String && value.length > 50) || key == 'text' || key == 'prompt';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(key, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          maxLines: isLongText ? null : 1,
          keyboardType: value is num ? TextInputType.number : TextInputType.text,
          decoration: InputDecoration(
            filled: true,
            fillColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(12),
          ),
          style: const TextStyle(fontSize: 14),
          onChanged: (val) {
            if (value is num) {
              final n = num.tryParse(val);
              if (n != null) widget.onChanged(n);
            } else {
              widget.onChanged(val);
            }
          },
        ),
      ],
    );
  }
}
