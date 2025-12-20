import 'package:flutter/material.dart';
import '../services/db_helper.dart';

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

  Future<void> refreshHistory() async {
    _isLoading = true;
    notifyListeners();
    
    try {
      final records = await DatabaseHelper.instance.readAllHistory();
      // Records: id, prompt_id, workflow_json, params_json, image_path, created_at
      _historyItems = records;
    } catch (e) {
      print('Error fetching local history: $e');
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
