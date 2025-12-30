# 输入法弹出问题修复计划

## 问题描述
用户报告可以100%复现以下问题：
1. 点击首页的编辑连接后，在返回图库点开图片返回，会100%触发输入法闪现
2. 类似的逻辑同样也在历史选项卡里复现

## 问题分析
通过代码分析，发现问题出现在焦点管理上：

### 根本原因
1. **参数编辑器页面** (`parameter_editor.dart`) 包含多个 `TextField` 组件：
   - 第412-421行：种子输入框
   - 第506-525行：文本输入框（用于提示词等长文本）

2. **焦点管理问题**：
   - 当用户在参数编辑器页面输入文本时，`TextField` 获取焦点并显示输入法
   - 用户点击返回按钮时，虽然调用了 `FocusScope.of(context).unfocus()`（第64行）
   - 但是当返回到图库页面并点击图片时，焦点可能被重新激活

3. **全屏图库页面** (`gallery_tab.dart`) 的问题：
   - 在 `_FullScreenGallery` 组件的返回按钮中也调用了 `FocusScope.of(context).unfocus()`（第298行）
   - 这表明系统检测到有焦点需要移除

## 解决方案

### 方案1：在页面切换时强制移除焦点
修改 `home_page.dart` 中的页面切换逻辑，确保在切换页面时移除所有焦点。

### 方案2：在全屏图库页面初始化时移除焦点
修改 `gallery_tab.dart` 中的 `_FullScreenGallery` 组件，在 `initState` 中主动移除焦点。

### 方案3：使用 FocusNode 管理焦点
为所有 TextField 添加 FocusNode，在页面销毁时主动释放焦点。

## 具体修复步骤

### 1. 修改 home_page.dart
在 `_onItemTapped` 方法中加强焦点管理：
```dart
void _onItemTapped(int index) {
  // 强制移除所有焦点
  FocusManager.instance.primaryFocus?.unfocus();
  FocusScope.of(context).unfocus();
  
  if (_currentIndex != index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.jumpToPage(index);
  }
}
```

### 2. 修改 gallery_tab.dart
在 `_FullScreenGalleryState` 的 `initState` 中移除焦点：
```dart
@override
void initState() {
  super.initState();
  _currentIndex = widget.initialIndex;
  _pageController = PageController(initialPage: widget.initialIndex);
  
  // 初始化时移除焦点
  WidgetsBinding.instance.addPostFrameCallback((_) {
    FocusManager.instance.primaryFocus?.unfocus();
  });
}
```

### 3. 修改 parameter_editor.dart
在返回按钮中加强焦点管理：
```dart
onPressed: () {
  // 移除焦点
  FocusManager.instance.primaryFocus?.unfocus();
  FocusScope.of(context).unfocus();
  
  // 延迟返回，确保焦点完全移除
  Future.delayed(const Duration(milliseconds: 50), () {
    Navigator.pop(context);
  });
},
```

## 预期效果
修复后，用户从参数编辑器页面返回时，输入法应该完全隐藏，不会在图库或历史页面闪现。

## 测试方案
1. 进入参数编辑器页面，在任意输入框中输入文字
2. 点击返回按钮返回首页
3. 切换到图库页面，点击任意图片进入全屏查看
4. 点击返回按钮，观察输入法是否闪现
5. 重复测试历史选项卡