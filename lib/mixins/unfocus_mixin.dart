import 'package:flutter/material.dart';

/// Mixin for unified focus management across pages.
///
/// This mixin provides focus cleanup methods for navigation,
/// preventing issues like:
/// - Keyboard flashing when returning to previous page
/// - Focus chain confusion during tab switching
///
/// Usage:
/// ```dart
/// class _MyPageState extends State<MyPage> with UnfocusOnNavigationMixin {
///   // Your state implementation
///   // Call unfocusBeforeNavigation() or popWithUnfocus() when navigating
/// }
/// ```
mixin UnfocusOnNavigationMixin<T extends StatefulWidget> on State<T> {
  /// Clear all focus in the current scope
  void _clearFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  /// Call this before navigating away from the page
  void unfocusBeforeNavigation() {
    _clearFocus();
    FocusScope.of(context).unfocus();
  }

  /// Delayed navigation with focus cleanup
  /// Use this for pop operations to prevent keyboard flash
  Future<void> popWithUnfocus() async {
    unfocusBeforeNavigation();
    // Small delay to ensure keyboard is fully dismissed
    await Future.delayed(const Duration(milliseconds: 50));
    if (mounted) {
      Navigator.pop(context);
    }
  }

  /// Push a route with focus cleanup
  Future<R?> pushWithUnfocus<R>(Route<R> route) async {
    unfocusBeforeNavigation();
    if (mounted) {
      return Navigator.push(context, route);
    }
    return null;
  }
}

/// Extension on BuildContext for quick focus management
extension FocusContextExtension on BuildContext {
  /// Clear focus from the current context
  void clearFocus() {
    FocusManager.instance.primaryFocus?.unfocus();
    FocusScope.of(this).unfocus();
  }
}
