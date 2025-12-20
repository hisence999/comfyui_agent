import 'dart:io';
import 'package:dio/dio.dart';

class ApiService {
  final Dio _dio = Dio();

  String? _baseUrl;

  void setBaseUrl(String url) {
    _baseUrl = url;
    _dio.options.baseUrl = url;
  }

  Future<bool> checkConnection() async {
    try {
      final response = await _dio.get('/system_stats');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, dynamic>> queuePrompt(Map<String, dynamic> prompt, String clientId) async {
    try {
      final response = await _dio.post('/prompt', data: {
        'prompt': prompt,
        'client_id': clientId,
      });
      return response.data;
    } on DioException catch (e) {
      if (e.response != null) {
        final data = e.response?.data;
        String msg = data['node_errors']?.toString() ?? data['message'] ?? '未知校验错误';
        throw Exception("运行失败: $msg");
      }
      throw Exception('网络错误: ${e.message}');
    } catch (e) {
      throw Exception('意外错误: $e');
    }
  }

  Future<void> interrupt() async {
    try {
      await _dio.post('/interrupt');
    } catch (e) {
      throw Exception('Failed to interrupt: $e');
    }
  }

  Future<String?> uploadImage(File file) async {
    try {
      String fileName = file.path.split('/').last;
      FormData formData = FormData.fromMap({
        "image": await MultipartFile.fromFile(file.path, filename: fileName),
        "overwrite": "true",
      });
      final response = await _dio.post('/upload/image', data: formData);
      if (response.statusCode == 200) {
        return response.data['name']; // Returns the filename on server
      }
      return null;
    } catch (e) {
      print('Upload error: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> getHistory() async {
    try {
      final response = await _dio.get('/history');
      return response.data;
    } catch (e) {
      throw Exception('Failed to get history: $e');
    }
  }

  Future<void> deleteHistoryOnServer(String promptId) async {
    try {
      await _dio.post('/history', data: {"delete": [promptId]});
    } catch (e) {
      print('Failed to delete history on server: $e');
    }
  }

  Future<Map<String, dynamic>> getQueue() async {
    try {
      final response = await _dio.get('/queue');
      return response.data;
    } catch (e) {
      throw Exception('Failed to get queue: $e');
    }
  }

  Future<Map<String, dynamic>> getObjectInfo() async {
    try {
      final response = await _dio.get('/object_info');
      return response.data;
    } catch (e) {
      throw Exception('Failed to get object info: $e');
    }
  }
  
  // Helper to construct image URL
  String getImageUrl(String filename, String? subfolder, String? type) {
    if (_baseUrl == null) return '';
    final query = <String, String>{
      'filename': filename,
      if (subfolder != null) 'subfolder': subfolder,
      if (type != null) 'type': type,
    };
    final uri = Uri.parse('$_baseUrl/view').replace(queryParameters: query);
    return uri.toString();
  }
}
