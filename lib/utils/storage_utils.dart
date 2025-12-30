import 'dart:io';
import 'package:path_provider/path_provider.dart';

/// 存储工具类，用于处理图片存储路径
class StorageUtils {
  /// 获取Pictures目录路径
  /// Android: /storage/emulated/0/Pictures/comfyui_client
  /// iOS: Documents/Pictures/comfyui_client
  /// 其他平台: 应用文档目录/Pictures/comfyui_client
  static Future<String> getPicturesDirectory() async {
    String basePath;
    
    if (Platform.isAndroid) {
      // Android: 使用外部存储的Pictures目录
      basePath = '/storage/emulated/0/Pictures';
    } else if (Platform.isIOS) {
      // iOS: 使用应用文档目录下的Pictures子目录
      final dir = await getApplicationDocumentsDirectory();
      basePath = '${dir.path}/Pictures';
    } else {
      // 其他平台: 使用应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      basePath = '${dir.path}/Pictures';
    }
    
    // 创建comfyui_client子目录
    final picturesDir = '$basePath/comfyui_client';
    await Directory(picturesDir).create(recursive: true);
    
    return picturesDir;
  }
  
  /// 获取图片保存的完整路径
  /// [promptId]: 提示ID，用于唯一标识图片
  /// [filename]: 原始文件名
  static Future<String> getImageSavePath(String promptId, String filename) async {
    final picturesDir = await getPicturesDirectory();
    
    // 清理文件名，移除路径分隔符
    final cleanFilename = filename.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    
    // 文件名格式: {prompt_id}_{original_filename}
    return '$picturesDir/${promptId}_$cleanFilename';
  }
  
  /// 检查图片文件是否已存在
  static Future<bool> imageExists(String promptId, String filename) async {
    try {
      final path = await getImageSavePath(promptId, filename);
      final file = File(path);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }
  
  /// 删除图片文件
  static Future<bool> deleteImageFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
  
  /// 从文件路径中提取promptId
  static String? extractPromptIdFromPath(String filePath) {
    try {
      final filename = filePath.split('/').last;
      final parts = filename.split('_');
      if (parts.isNotEmpty) {
        return parts[0];
      }
    } catch (_) {}
    return null;
  }
  
  /// 获取所有图片文件的列表
  static Future<List<File>> listImageFiles() async {
    try {
      final picturesDir = await getPicturesDirectory();
      final dir = Directory(picturesDir);
      
      if (!await dir.exists()) {
        return [];
      }
      
      final files = await dir.list().toList();
      final imageFiles = <File>[];
      
      for (var file in files) {
        if (file is File) {
          final ext = file.path.toLowerCase();
          if (ext.endsWith('.png') || ext.endsWith('.jpg') || ext.endsWith('.jpeg')) {
            imageFiles.add(file);
          }
        }
      }
      
      return imageFiles;
    } catch (_) {
      return [];
    }
  }
  
  /// 获取应用私有目录路径（用于向后兼容）
  static Future<String> getAppPrivateDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final privateDir = '${appDir.path}/comfy_images';
    await Directory(privateDir).create(recursive: true);
    return privateDir;
  }
}