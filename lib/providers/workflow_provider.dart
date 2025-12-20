import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../services/db_helper.dart';
import '../models/workflow.dart';
import 'history_provider.dart';

class WorkflowProvider with ChangeNotifier, WidgetsBindingObserver {
  HistoryProvider? _historyProvider;
  void setHistoryProvider(HistoryProvider hp) => _historyProvider = hp;

  final ApiService _apiService = ApiService();
  final WebSocketService _wsService = WebSocketService();
  
  bool _isConnected = false;
  bool get isConnected => _isConnected;
  
  Map<String, dynamic>? _currentWorkflow;
  Map<String, dynamic>? get currentWorkflow => _currentWorkflow;
  String? _currentWorkflowId;
  String? get currentWorkflowId => _currentWorkflowId;
  
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Re-ping server and check for missed events
      _recoverStateAfterBack();
    }
  }

  Future<void> _recoverStateAfterBack() async {
    if (!_isExecuting || _currentPromptId == null) return;
    print("Checking task status after resuming from background...");
    
    try {
      final queue = await _apiService.getQueue();
      bool isStillInQueue = false;
      
      final running = queue['queue_running'] as List;
      final pending = queue['queue_pending'] as List;
      
      if (running.any((e) => e[1] == _currentPromptId) || 
          pending.any((e) => e[1] == _currentPromptId)) {
        isStillInQueue = true;
      }

      if (!isStillInQueue) {
        // Check history
        final history = await _apiService.getHistory();
        if (history.containsKey(_currentPromptId)) {
          print("Task finished in background, triggering manual download");
          await _handleServerHistoryItem(_currentPromptId!, history[_currentPromptId!]);
          _isExecuting = false;
          _currentNodeId = null;
          notifyListeners();
        }
      }
    } catch (e) {
      print("Recovery failed: $e");
    }
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
        break;
      case 'executing':
        final nodeId = data['node'];
        if (nodeId == null) {
          _isExecuting = false;
          _currentNodeId = null;
          _currentPreview = null;
          _nodeStepsInfo = null;
        } else {
          _isExecuting = true;
          if (_currentNodeId != null && _currentNodeId != nodeId) {
            _nodesExecutedCount++;
          }
          _currentNodeId = nodeId;
          _nodeProgress = 0;
          _nodeStepsInfo = null;
        }
        break;
      case 'progress':
        _nodeProgress = (data['value'] ?? 0) / (data['max'] ?? 1);
        _nodeStepsInfo = "步数: ${data['value']}/${data['max']}";
        _isExecuting = true;
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

    // Handle Seed Logic (Automatic updates)
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
      rethrow;
    }
  }
  
  Future<void> cancelExecution() async {
    try {
      await _apiService.interrupt();
      if (_currentPromptId != null) {
        // Find local record and delete it if it's new/empty
        final localHistory = await DatabaseHelper.instance.readAllHistory();
        final record = localHistory.cast<Map?>().firstWhere((e) => e?['prompt_id'] == _currentPromptId, orElse: () => null);
        if (record != null) {
          await DatabaseHelper.instance.deleteHistory(record['id']);
          _historyProvider?.refreshHistory();
        }
      }
    } catch (_) {}
    _isExecuting = false;
    _currentNodeId = null;
    _nodeStepsInfo = null;
    notifyListeners();
  }

  Future<void> _fetchObjectInfo() async {
    if (!_isConnected) return;
    try {
      _objectInfo = await _apiService.getObjectInfo();
      notifyListeners();
    } catch (e) {
      print('Failed to fetch object info: $e');
    }
  }

  void loadWorkflow(String? id, Map<String, dynamic> workflow) {
    _currentWorkflowId = id;
    _currentWorkflow = workflow;
    _isExecuting = false;
    _currentNodeId = null;
    _nodeProgress = 0.0;
    _nodesExecutedCount = 0;
    _currentPreview = null;
    _nodeStepsInfo = null;
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
        if (!localPromptIds.contains(promptId)) {
          await _handleServerHistoryItem(promptId, serverHistory[promptId]);
        }
      }
    } catch (_) {}
  }

  Future<void> _handleServerHistoryItem(String promptId, dynamic serverItem) async {
    final outputs = serverItem['outputs'];
    if (outputs == null) return;
    String? firstImagePath;
    for (var nodeOut in outputs.values) {
      if (nodeOut['images'] != null) {
        for (var img in nodeOut['images']) {
          final path = await _downloadAndSaveImageInternal(img['filename'], img['subfolder'], img['type'], promptId);
          firstImagePath ??= path;
        }
      }
    }
    if (firstImagePath != null) {
      final record = {
        'prompt_id': promptId,
        'workflow_json': jsonEncode(serverItem['prompt'] ?? {}),
        'params_json': '{}', 
        'image_path': firstImagePath,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      };
      await DatabaseHelper.instance.createHistory(record);
      _historyProvider?.refreshHistory();
    }
  }

  Future<String?> _downloadAndSaveImageInternal(String filename, String? subfolder, String? type, String promptId) async {
     try {
      final url = _apiService.getImageUrl(filename, subfolder, type);
      final dio = Dio();
      final response = await dio.get(url, options: Options(responseType: ResponseType.bytes));
      
      // 1. Save to APP documents directory (for internal UI)
      final appDir = await getApplicationDocumentsDirectory();
      final localPath = '${appDir.path}/comfy_images';
      await Directory(localPath).create(recursive: true);
      final file = File('$localPath/${promptId}_$filename');
      if (!await file.exists()) {
        await file.writeAsBytes(response.data);
      }

      // 2. Export to Public Gallery using saver_gallery
      try {
        await SaverGallery.saveFile(
          filePath: file.path,
          fileName: "${promptId.substring(0,8)}_$filename",
          skipIfExists: false,
        );
      } catch (e) {
        print('SaverGallery error: $e');
      }

      return file.path; // Return internal path for app UI
    } catch (_) { return null; }
  }

  Future<void> deleteHistoryWithSync(int localId, String promptId) async {
    try {
      await _apiService.deleteHistoryOnServer(promptId);
      await DatabaseHelper.instance.deleteHistory(localId);
      _historyProvider?.refreshHistory();
    } catch (_) {}
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _wsService.dispose();
    super.dispose();
  }
}
