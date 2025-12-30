# 存储逻辑修复实现计划

## 问题概述
1. 图片双重存储（私有目录 + 系统相册）
2. 删除逻辑不完整
3. 本地扫描目录不一致
4. 缺少去重机制
5. 离线/在线同步不完善

## 修复目标
1. 统一存储位置：`Pictures/comfyui_client`
2. 完整的删除逻辑
3. 正确的离线扫描
4. 完善的在线同步去重
5. 确保不会出现重复图片

## 需要修改的文件

### 1. `lib/providers/workflow_provider.dart`
#### 修改 `_downloadAndSaveImageInternal` 方法：
- 移除应用私有目录保存
- 改为保存到 `Pictures/comfyui_client` 目录
- 确保 `SaverGallery.saveFile` 保存到正确位置
- 添加文件存在检查

#### 修改 `deleteHistoryWithSync` 方法：
- 确保删除公共目录的文件
- 改进系统相册删除逻辑

#### 修改 `syncHistoryWithServer` 方法：
- 添加更严格的去重检查
- 检查文件是否已存在本地

#### 修改 `_handleServerHistoryItem` 方法：
- 添加文件存在检查
- 避免重复下载

### 2. `lib/providers/history_provider.dart`
#### 修改 `syncLocalImages` 方法：
- 只扫描 `Pictures/comfyui_client` 目录
- 添加去重导入逻辑
- 基于 `prompt_id` 和文件路径去重

### 3. `lib/ui/pages/gallery_tab.dart`
#### 修改路径映射逻辑：
- 更新路径显示逻辑
- 确保能正确显示公共目录的文件

### 4. 数据库改进
#### 添加唯一约束：
- 在 `history_records` 表添加 `prompt_id` 唯一约束
- 添加文件路径索引

## 具体实现步骤

### 步骤1：获取Pictures目录路径
```dart
Future<String> getPicturesDirectory() async {
  if (Platform.isAndroid) {
    return '/storage/emulated/0/Pictures/comfyui_client';
  } else if (Platform.isIOS) {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/Pictures/comfyui_client';
  }
  final dir = await getApplicationDocumentsDirectory();
  return '${dir.path}/Pictures/comfyui_client';
}
```

### 步骤2：修改图片保存逻辑
- 只保存到 `Pictures/comfyui_client` 目录
- 文件名格式：`{prompt_id}_{original_filename}`
- 保存前检查文件是否已存在

### 步骤3：修改删除逻辑
- 删除 `Pictures/comfyui_client` 目录的文件
- 删除系统相册中的对应文件
- 删除数据库记录

### 步骤4：修改本地扫描逻辑
- 只扫描 `Pictures/comfyui_client` 目录
- 导入时检查 `prompt_id` 是否已存在
- 避免重复导入

### 步骤5：修改在线同步逻辑
- 下载前检查文件是否已存在
- 基于 `prompt_id` 去重
- 避免重复下载

## 测试计划
1. 测试图片生成和保存
2. 测试本地图片扫描
3. 测试服务器同步
4. 测试删除功能
5. 测试去重逻辑
6. 测试离线/在线切换

## 风险与注意事项
1. 需要处理Android权限
2. 需要兼容不同平台
3. 需要处理文件系统错误
4. 需要确保向后兼容
5. 需要测试性能影响