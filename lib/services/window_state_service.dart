import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

/// ウィンドウの位置・サイズを保存・復元するサービス（デスクトップ用）
class WindowStateService with WindowListener {
  static const _minSize = Size(640, 480);
  static const _defaultSize = Size(1100, 750);

  static const _keyX = 'window_x';
  static const _keyY = 'window_y';
  static const _keyW = 'window_w';
  static const _keyH = 'window_h';
  static const _keyMaximized = 'window_maximized';

  late SharedPreferences _prefs;

  /// ウィンドウを初期化し、前回終了時の位置・サイズを復元する
  Future<void> init() async {
    await windowManager.ensureInitialized();
    _prefs = await SharedPreferences.getInstance();

    final w = _prefs.getDouble(_keyW) ?? _defaultSize.width;
    final h = _prefs.getDouble(_keyH) ?? _defaultSize.height;
    final x = _prefs.getDouble(_keyX);
    final y = _prefs.getDouble(_keyY);
    final maximized = _prefs.getBool(_keyMaximized) ?? false;

    final options = WindowOptions(
      size: Size(w, h),
      minimumSize: _minSize,
      center: x == null || y == null, // 保存値がなければ中央に表示
      title: 'SQLite Viewer',
    );

    await windowManager.waitUntilReadyToShow(options, () async {
      if (x != null && y != null) {
        await windowManager.setPosition(Offset(x, y));
      }
      if (maximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });

    // 閉じる操作をフックして、終了時にのみ状態を保存する
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);
  }

  Future<void> _saveBounds() async {
    if (await windowManager.isMaximized()) {
      // 最大化中は通常時のサイズを上書きせず、フラグのみ保存
      await _prefs.setBool(_keyMaximized, true);
      return;
    }
    await _prefs.setBool(_keyMaximized, false);
    final bounds = await windowManager.getBounds();
    await _prefs.setDouble(_keyX, bounds.left);
    await _prefs.setDouble(_keyY, bounds.top);
    await _prefs.setDouble(_keyW, bounds.width);
    await _prefs.setDouble(_keyH, bounds.height);
  }

  @override
  void onWindowClose() async {
    await _saveBounds();
    await windowManager.destroy();
  }
}
