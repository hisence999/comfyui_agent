import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/db_helper.dart';
import '../models/workflow.dart';
import '../utils/storage_utils.dart';
import 'history_provider.dart';

class WorkflowProvider with ChangeNotifier, WidgetsBindingObserver {
  HistoryProvider? _historyProvider;
  void setHistoryProvider(HistoryProvider hp) => _historyProvider = hp;

  final ApiService _apiService = ApiService();
  final WebSocketService _wsService = WebSocketService();

  // Platform channel for native MediaStore operations
  static const _mediaStoreChannel = MethodChannel('com.comfyui.mobile/mediastore');

  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  // State 1: Currently being edited in ParameterEditor
  Map<String, dynamic>? _currentWorkflow;
  Map<String, dynamic>? get currentWorkflow => _currentWorkflow;
  String? _currentWorkflowId;
  String? get currentWorkflowId => _currentWorkflowId;

  // State 2: Currently running on the server
  String? _runningWorkflowId;
  String? get runningWorkflowId => _runningWorkflowId;

  bool _shouldScrollToRunning = false;
  bool get shouldScrollToRunning => _shouldScrollToRunning;
  void resetScrollRequest() => _shouldScrollToRunning = false;
  void requestScrollToRunning() {
    _shouldScrollToRunning = true;
    notifyListeners();
  }
  
  List<Workflow> _savedWorkflows = [];
  List<Workflow> get savedWorkflows => _savedWorkflows;

  // Server-side node metadata
  Map<String, dynamic> _objectInfo = {};
  Map<String, dynamic> get objectInfo => _objectInfo;

  // Real-time execution status
  bool _isExecuting = false;
  bool get isExecuting => _isExecuting;
  
  int _queueRemaining = 0;
  int get queueRemaining => _queueRemaining;
  
  String? _currentNodeId;
  String? get currentNodeId => _currentNodeId;
  
  // Mapping node ID to Name
  Map<String, String> _nodeNameMap = {};
  String get currentNodeName {
    if (_currentNodeId == null) return "等待中...";
    return _nodeNameMap[_currentNodeId] ?? "节点 $_currentNodeId";
  }
  
  double _nodeProgress = 0.0;
  String? _nodeStepsInfo;
  String? get nodeStepsInfo => _nodeStepsInfo;
  int _nodesExecutedCount = 0;
  int _totalNodesInWorkflow = 0;
  
  double get progress {
    if (!_isExecuting) return 0.0;
    if (_totalNodesInWorkflow <= 0) return 0.0;
    return ((_nodesExecutedCount + _nodeProgress) / _totalNodesInWorkflow).clamp(0.0, 1.0);
  }
  
  Uint8List? _currentPreview;
  Uint8List? get currentPreview => _currentPreview;

  String? _currentPromptId;

  WorkflowProvider() {
    WidgetsBinding.instance.addObserver(this);
    _wsService.messageStream.listen(_handleWsMessage);
    _wsService.previewStream.listen((preview) {
      _currentPreview = preview;
      notifyListeners();
    });
    loadSavedWorkflows();
    _autoConnect();
  }

  Future<void> _autoConnect() async {
    final prefs = await SharedPreferences.getInstance();
    final ip = prefs.getString('ipAddress') ?? '127.0.0.1';
    final port = prefs.getString('port') ?? '8188';
    connect(ip, port);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _recoverStateAfterBack();
    }
  }

  Future<void> _recoverStateAfterBack() async {
    if (!_isExecuting || _currentPromptId == null) return;
    try {
      final queue = await _apiService.getQueue();
      bool isStillInQueue = false;
      final running = queue['queue_running'] as List;
      final pending = queue['queue_pending'] as List;
      if (running.any((e) => e[1] == _currentPromptId) || pending.any((e) => e[1] == _currentPromptId)) {
        isStillInQueue = true;
      }
      if (!isStillInQueue) {
        final history = await _apiService.getHistory();
        if (history.containsKey(_currentPromptId)) {
          await _handleServerHistoryItem(_currentPromptId!, history[_currentPromptId!]);
          _isExecuting = false;
          _currentNodeId = null;
          _runningWorkflowId = null;
          notifyListeners();
        }
      }
    } catch (_) {}
  }
  
  Future<void> loadSavedWorkflows() async {
    _savedWorkflows = await DatabaseHelper.instance.readAllWorkflows();
    notifyListeners();
  }

  Future<void> importWorkflow(String name, String jsonContent) async {
    final workflow = Workflow(
      id: const Uuid().v4(),
      name: name,
      content: jsonContent,
      lastModified: DateTime.now(),
    );
    await DatabaseHelper.instance.createWorkflow(workflow);
    await loadSavedWorkflows();
  }

  Future<void> deleteWorkflow(String id) async {
    await DatabaseHelper.instance.deleteWorkflow(id);
    await loadSavedWorkflows();
  }

  Future<void> connect(String ip, String port) async {
    final httpUrl = 'http://$ip:$port';
    _apiService.setBaseUrl(httpUrl);
    try {
      final isAlive = await _apiService.checkConnection().timeout(const Duration(seconds: 5));
      if (isAlive) {
        await _wsService.connect(httpUrl);
        _isConnected = true;
        _fetchObjectInfo();
        syncHistoryWithServer();
      } else {
        _isConnected = false;
      }
    } catch (e) {
      _isConnected = false;
    }
    notifyListeners();
  }

  void _buildNodeNameMap() {
    _nodeNameMap.clear();
    _currentWorkflow?.forEach((id, node) {
      String title = node['_meta']?['title'] ?? node['class_type'] ?? "未知节点";
      _nodeNameMap[id] = title;
    });
    _totalNodesInWorkflow = _currentWorkflow?.length ?? 0;
  }

  void _syncToOverlay({bool finished = false}) async {
    try {
      // Check if overlay is active before sending data
      bool isActive = await FlutterOverlayWindow.isActive();
      print('Syncing to overlay, is active: $isActive');
      
      if (isActive) {
        final payload = jsonEncode({
          'node': currentNodeName,
          'steps': nodeStepsInfo ?? "",
          'progress': progress,
          'finished': finished,
        });
        
        // shareData in version 0.5.0 doesn't return a value
        await FlutterOverlayWindow.shareData(payload);
        print('Overlay data shared successfully');
      }
    } catch (e) {
      print('Error syncing to overlay: $e');
    }
  }

  void _handleWsMessage(Map<String, dynamic> message) async {
    final type = message['type'];
    final data = message['data'];
    
    switch (type) {
      case 'status':
        if (data != null && data['status'] != null) {
          _queueRemaining = data['status']['exec_info']['queue_remaining'];
          if (_queueRemaining == 0 && !_isExecuting) {
             _currentNodeId = null;
             _currentPreview = null;
             _nodeStepsInfo = null;
             _runningWorkflowId = null;
             _syncToOverlay(finished: true);
          }
        }
        break;
      case 'execution_start':
        _isExecuting = true;
        _currentPromptId = data['prompt_id'];
        _nodesExecutedCount = 0;
        _nodeProgress = 0;
        _currentPreview = null;
        _nodeStepsInfo = null;
        _totalNodesInWorkflow = _currentWorkflow?.length ?? 0;
        _syncToOverlay();
        break;
      case 'executing':
        final nodeId = data['node'];
        if (nodeId == null) {
          _isExecuting = false;
          _currentNodeId = null;
          _currentPreview = null;
          _nodeStepsInfo = null;
          _runningWorkflowId = null;
          _syncToOverlay(finished: true);
        } else {
          _isExecuting = true;
          if (_currentNodeId != null && _currentNodeId != nodeId) {
            _nodesExecutedCount++;
          }
          _currentNodeId = nodeId;
          _nodeProgress = 0;
          _nodeStepsInfo = null;
          _syncToOverlay();
        }
        break;
      case 'progress':
        _nodeProgress = (data['value'] ?? 0) / (data['max'] ?? 1);
        _nodeStepsInfo = "步数: ${data['value']}/${data['max']}";
        _isExecuting = true;
        _syncToOverlay();
        break;
      case 'executed':
        if (data['output'] != null) {
          final output = data['output'];
          for (var nodeOut in output.values) {
            if (nodeOut is List) {
               for (var img in nodeOut) {
                 if (img is Map && img.containsKey('filename')) {
                   await _downloadAndSaveImage(img['filename'], img['subfolder'], img['type']);
                 }
               }
            } else if (nodeOut is Map && nodeOut.containsKey('images')) {
               for (var img in nodeOut['images']) {
                 await _downloadAndSaveImage(img['filename'], img['subfolder'], img['type']);
               }
            }
          }
        }
        break;
    }
    notifyListeners();
  }
  
  Future<void> _downloadAndSaveImage(String filename, String? subfolder, String? type) async {
    if (_currentPromptId == null) return;
    final path = await _downloadAndSaveImageInternal(filename, subfolder, type, _currentPromptId!);
    if (path != null) {
       final db = await DatabaseHelper.instance.database;
       await db.update('history_records', {'image_path': path}, where: 'prompt_id = ?', whereArgs: [_currentPromptId]);
       _historyProvider?.refreshHistory();
    }
  }

  Future<void> queuePrompt() async {
    if (_currentWorkflow == null) return;
    _buildNodeNameMap();
    
    // Bind running state to the specific workflow ID
    _runningWorkflowId = _currentWorkflowId;

    // Handle Seed Logic
    _currentWorkflow?.forEach((id, node) {
      if (node is Map && node['inputs'] != null) {
        final inputs = node['inputs'] as Map;
        for (var seedKey in ['seed', 'noise_seed']) {
          if (inputs.containsKey(seedKey) && inputs[seedKey] is num) {
            num currentSeed = inputs[seedKey];
            String mode = inputs['control_after_generate']?.toString() ?? 'randomize';
            if (mode == 'randomize') {
              inputs[seedKey] = Random().nextInt(1000000000);
            } else if (mode == 'increment') {
              inputs[seedKey] = currentSeed + 1;
            } else if (mode == 'decrement') {
              inputs[seedKey] = currentSeed - 1;
            }
          }
        }
      }
    });

    if (_currentWorkflowId != null) {
      try {
        final currentWf = _savedWorkflows.firstWhere((w) => w.id == _currentWorkflowId);
        currentWf.content = jsonEncode(_currentWorkflow);
        currentWf.lastModified = DateTime.now();
        await DatabaseHelper.instance.updateWorkflow(currentWf);
        await loadSavedWorkflows();
      } catch (_) {}
    }

    try {
      final response = await _apiService.queuePrompt(_currentWorkflow!, _wsService.clientId);
      final promptId = response['prompt_id'];
      
      Map<String, String> simplifiedParams = {};
      _currentWorkflow?.forEach((key, node) {
        if (node is Map && node['inputs'] != null) {
          final inputs = node['inputs'] as Map;
          final classType = node['class_type'].toString();
          if (classType.contains('CheckpointLoader') && inputs.containsKey('ckpt_name')) {
            simplifiedParams['模型'] = inputs['ckpt_name'].toString();
          } else if (classType.contains('LoraLoader') && inputs.containsKey('lora_name')) {
            simplifiedParams['LoRA'] = inputs['lora_name'].toString();
          } else if (classType.contains('CLIPTextEncode') && inputs.containsKey('text')) {
            simplifiedParams['提示词'] = inputs['text'].toString();
          }
        }
      });

      final record = {
        'prompt_id': promptId,
        'workflow_json': jsonEncode(_currentWorkflow),
        'params_json': jsonEncode(simplifiedParams),
        'image_path': '',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      await DatabaseHelper.instance.createHistory(record);
      _historyProvider?.refreshHistory();
    } catch (e) {
      _runningWorkflowId = null;
      rethrow;
    }
  }
  
  Future<void> cancelExecution() async {
    try {
      await _apiService.interrupt();
      if (_currentPromptId != null) {
        final localHistory = await DatabaseHelper.instance.readAllHistory();
        final record = localHistory.cast<Map?>().firstWhere((e) => e?['prompt_id'] == _currentPromptId, orElse: () => null);
        if (record != null) {
          await deleteHistoryWithSync(record['id'], _currentPromptId!);
        }
      }
    } catch (_) {}
    _isExecuting = false;
    _currentNodeId = null;
    _nodeStepsInfo = null;
    _runningWorkflowId = null;
    _syncToOverlay(finished: true);
    notifyListeners();
  }

  Future<void> _fetchObjectInfo() async {
    if (!_isConnected) return;
    try {
      _objectInfo = await _apiService.getObjectInfo();
      notifyListeners();
    } catch (_) {}
  }

  void loadWorkflow(String? id, Map<String, dynamic> workflow) {
    _currentWorkflowId = id;
    _currentWorkflow = workflow;

    // Only reset local UI state for this workflow, NOT global execution state
    // Execution state (_isExecuting, _currentNodeId, etc.) should be controlled by WebSocket messages
    // This preserves progress display when navigating between workflows during execution
    if (_runningWorkflowId != id) {
      // Clear preview only if this is not the running workflow
      _currentPreview = null;
    }

    _buildNodeNameMap();
    notifyListeners();
  }

  Future<String?> uploadImage(File file) async {
    return await _apiService.uploadImage(file);
  }

  Future<void> syncHistoryWithServer() async {
    if (!_isConnected) return;
    try {
      final serverHistory = await _apiService.getHistory();
      final localHistory = await DatabaseHelper.instance.readAllHistory();
      final localPromptIds = localHistory.map((e) => e['prompt_id']).toSet();
      
      for (var promptId in serverHistory.keys) {
        // 检查是否已存在本地
        if (!localPromptIds.contains(promptId)) {
          await _handleServerHistoryItem(promptId, serverHistory[promptId]);
        } else {
          // 即使prompt_id已存在，也要检查文件是否实际存在
          // 防止数据库记录存在但文件被删除的情况
          final localRecord = localHistory.firstWhere(
            (e) => e['prompt_id'] == promptId,
            orElse: () => {},
          );
          if (localRecord.isNotEmpty) {
            final imagePath = localRecord['image_path'] as String?;
            if (imagePath != null && imagePath.isNotEmpty) {
              final file = File(imagePath);
              if (!await file.exists()) {
                // 文件不存在，重新下载
                await _handleServerHistoryItem(promptId, serverHistory[promptId]);
              }
            }
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _handleServerHistoryItem(String promptId, dynamic serverItem) async {
    final outputs = serverItem['outputs'];
    if (outputs == null) return;
    
    String? firstImagePath;
    bool hasImages = false;
    
    for (var nodeOut in outputs.values) {
      if (nodeOut['images'] != null) {
        for (var img in nodeOut['images']) {
          hasImages = true;
          final filename = img['filename'] as String;
          final subfolder = img['subfolder'] as String?;
          final type = img['type'] as String?;
          
          // 检查图片是否已存在
          final exists = await StorageUtils.imageExists(promptId, filename);
          if (!exists) {
            // 只下载不存在的图片
            final path = await _downloadAndSaveImageInternal(filename, subfolder, type, promptId);
            firstImagePath ??= path;
          } else {
            // 图片已存在，获取路径
            final existingPath = await StorageUtils.getImageSavePath(promptId, filename);
            firstImagePath ??= existingPath;
          }
        }
      }
    }
    
    // 如果有图片，确保数据库中有记录
    if (hasImages && firstImagePath != null) {
      // 检查是否已存在数据库记录
      final db = await DatabaseHelper.instance.database;
      final existingRecords = await db.query(
        'history_records',
        where: 'prompt_id = ?',
        whereArgs: [promptId]
      );
      
      if (existingRecords.isEmpty) {
        // 创建新记录
        final record = {
          'prompt_id': promptId,
          'workflow_json': jsonEncode(serverItem['prompt'] ?? {}),
          'params_json': '{}',
          'image_path': firstImagePath,
          'created_at': DateTime.now().millisecondsSinceEpoch,
        };
        await DatabaseHelper.instance.createHistory(record);
        _historyProvider?.refreshHistory();
      } else {
        // 更新现有记录的图片路径（如果为空）
        final existingRecord = existingRecords.first;
        final existingImagePath = existingRecord['image_path'] as String?;
        if (existingImagePath == null || existingImagePath.isEmpty) {
          await db.update(
            'history_records',
            {'image_path': firstImagePath},
            where: 'prompt_id = ?',
            whereArgs: [promptId],
          );
          _historyProvider?.refreshHistory();
        }
      }
    }
  }

  Future<String?> _downloadAndSaveImageInternal(String filename, String? subfolder, String? type, String promptId) async {
     try {
       // 检查图片是否已存在
       final exists = await StorageUtils.imageExists(promptId, filename);
       if (exists) {
         // 如果已存在，直接返回路径
         return await StorageUtils.getImageSavePath(promptId, filename);
       }
       
       final url = _apiService.getImageUrl(filename, subfolder, type);
       final dio = Dio();
       final response = await dio.get(url, options: Options(responseType: ResponseType.bytes));
       
       // 获取保存路径（Pictures/comfyui_client目录）
       final savePath = await StorageUtils.getImageSavePath(promptId, filename);
       final file = File(savePath);
       
       // 确保目录存在
       await file.parent.create(recursive: true);
       
       // 保存图片文件
       await file.writeAsBytes(response.data);
       
       // 注意：不再调用SaverGallery.saveFile，因为Pictures/comfyui_client目录已经是系统相册可访问的
       // 这样可以避免双重保存问题
       
       return file.path;
     } catch (_) {
       return null;
     }
   }

  Future<void> deleteHistoryWithSync(int localId, String promptId) async {
    try {
      final db = await DatabaseHelper.instance.database;
      final maps = await db.query('history_records', where: 'id = ?', whereArgs: [localId]);
      if (maps.isNotEmpty) {
        final imagePath = maps.first['image_path'] as String;
        if (imagePath.isNotEmpty) {
          // 删除本地文件
          await StorageUtils.deleteImageFile(imagePath);
          // 删除系统相册中的文件
          await _deleteFromSystemGallery(imagePath);
        }
      }
      await _apiService.deleteHistoryOnServer(promptId);
      await DatabaseHelper.instance.deleteHistory(localId);
      _historyProvider?.refreshHistory();
    } catch (_) {}
  }

  /// Delete image from system MediaStore using native platform channel
  /// Performance: O(1) SQL query vs O(n²) iteration (100x+ faster)
  Future<void> _deleteFromSystemGallery(String localPath) async {
    try {
      // Only use native method on Android
      if (!Platform.isAndroid) return;

      final filename = localPath.split('/').last;

      // Use native MediaStore query for fast deletion
      final result = await _mediaStoreChannel.invokeMethod<bool>(
        'deleteImageByFilename',
        {'filename': filename},
      );

      if (result == true) {
        print('Successfully deleted from MediaStore: $filename');
      } else {
        print('Image not found in MediaStore or deletion failed: $filename');
      }
    } catch (e) {
      // Deletion from system gallery is not critical, log and continue
      print('Error deleting from system gallery: $e');
    }
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsService.dispose();
    super.dispose();
  }
}
