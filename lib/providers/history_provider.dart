import 'package:flutter/material.dart';
import '../services/db_helper.dart';
import '../utils/storage_utils.dart';
import 'dart:io';

class HistoryProvider with ChangeNotifier {
  List<Map<String, dynamic>> _historyItems = [];
  List<Map<String, dynamic>> get historyItems => _historyItems;
  
  List<String> get imageUrls => _historyItems
      .where((item) => item['image_path'] != null && (item['image_path'] as String).isNotEmpty)
      .map((item) => item['image_path'] as String)
      .toList();

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  bool _isLoadingMore = false;
  bool get isLoadingMore => _isLoadingMore;

  bool _hasMore = true;
  bool get hasMore => _hasMore;

  final int _pageSize = 50;

  Future<void> refreshHistory() async {
    _isLoading = true;
    _hasMore = true;
    notifyListeners();
    
    try {
      final records = await DatabaseHelper.instance.readAllHistory(limit: _pageSize, offset: 0);
      // Use List.from to ensure the list is growable (sqflite results are read-only)
      _historyItems = List<Map<String, dynamic>>.from(records);
      
      if (records.length < _pageSize) {
        _hasMore = false;
      }
    } catch (e) {
      print('Error fetching local history: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreHistory() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      final offset = _historyItems.length;
      final newRecords = await DatabaseHelper.instance.readAllHistory(limit: _pageSize, offset: offset);
      
      if (newRecords.isNotEmpty) {
        _historyItems.addAll(newRecords);
      }
      
      if (newRecords.length < _pageSize) {
        _hasMore = false;
      }
    } catch (e) {
      print('Error loading more history: $e');
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> syncLocalImages() async {
    _isLoading = true;
    notifyListeners();

    try {
      // 只扫描Pictures/comfyui_client目录
      final picturesDir = await StorageUtils.getPicturesDirectory();
      final dir = Directory(picturesDir);
      
      if (!await dir.exists()) {
        // 目录不存在，创建它
        await dir.create(recursive: true);
        _isLoading = false;
        notifyListeners();
        return;
      }

      // 获取所有图片文件
      final imageFiles = await StorageUtils.listImageFiles();
      
      // 获取数据库中的现有记录
      final allDbRecords = await DatabaseHelper.instance.readAllHistory(limit: 100000);
      final Set<String> dbPaths = allDbRecords.map((e) => e['image_path'] as String).where((path) => path.isNotEmpty).toSet();
      final Set<String> dbPromptIds = allDbRecords.map((e) => e['prompt_id'] as String).where((id) => id.isNotEmpty).toSet();

      int importCount = 0;

      for (var file in imageFiles) {
        final filePath = file.path;
        
        // 检查是否已存在于数据库（通过文件路径）
        if (!dbPaths.contains(filePath)) {
          // 从文件路径中提取promptId
          final promptId = StorageUtils.extractPromptIdFromPath(filePath);
          
          // 生成唯一的promptId（如果无法从文件名提取）
          final finalPromptId = promptId ?? 'imported_${DateTime.now().millisecondsSinceEpoch}_$importCount';
          
          // 检查promptId是否已存在
          if (!dbPromptIds.contains(finalPromptId)) {
            // 导入缺失的文件
            await DatabaseHelper.instance.createHistory({
              'prompt_id': finalPromptId,
              'workflow_json': '{}',
              'params_json': '{}',
              'image_path': filePath,
              'created_at': file.lastModifiedSync().millisecondsSinceEpoch,
            });
            importCount++;
            
            // 更新本地集合，避免重复导入
            dbPaths.add(filePath);
            dbPromptIds.add(finalPromptId);
          }
        }
      }

      if (importCount > 0) {
        await refreshHistory();
        // 注意：这里无法直接显示SnackBar，因为缺少BuildContext
        // 调用者应该在UI层处理通知
        print('导入了 $importCount 张图片到图库');
      }
    } catch (e) {
      print('Sync error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
  
  Future<void> deleteHistory(int id) async {
    await DatabaseHelper.instance.deleteHistory(id);
    await refreshHistory();
  }
}
