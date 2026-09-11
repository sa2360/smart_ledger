import 'package:flutter/foundation.dart';

/// 全局刷新信号：记账/删除/预算变化后 +1，
/// 各页面监听该信号重新加载数据（配合 IndexedStack 保持状态）
final ValueNotifier<int> refreshSignal = ValueNotifier(0);

void notifyDataChanged() => refreshSignal.value++;
