import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:smart_ledger/main.dart';
import 'package:smart_ledger/services/settings_service.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('App 启动冒烟测试：首页正常渲染', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await SettingsService.init();
    await tester.pumpWidget(const SmartLedgerApp());
    // 固定帧推进：测试环境 SQLite 可能加载失败导致加载动画不停，
    // pumpAndSettle 会超时，这里只验证首页框架渲染
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('一语记'), findsOneWidget);
  });
}
