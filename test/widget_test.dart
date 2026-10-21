import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_ledger/pages/add_bill_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_ledger/db/database_helper.dart';
import 'package:smart_ledger/main.dart';
import 'package:smart_ledger/models/bill.dart';
import 'package:smart_ledger/models/budget.dart';
import 'package:smart_ledger/pages/ai_analysis_page.dart';
import 'package:smart_ledger/pages/budget_page.dart';
import 'package:smart_ledger/pages/home_page.dart';
import 'package:smart_ledger/pages/widgets/common.dart';
import 'package:smart_ledger/services/settings_service.dart';
import 'test_database.dart';

Future<void> settleDatabase(WidgetTester tester) async {
  // SQLite 的连续事务/查询需要多次真实事件循环；虚拟动画时钟不能推进文件 I/O。
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  await tester.pumpAndSettle();
}

void main() {
  late Directory directory;
  final db = DatabaseHelper.instance;
  final now = DateTime.now();
  String month(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  final thisMonth = month(now);
  final lastMonth = month(DateTime(now.year, now.month - 1));
  setUp(() async {
    directory = await setUpDatabase();
  });
  tearDown(() async {
    await tearDownDatabase(directory);
  });

  testWidgets('首页真实加载 SQLite 并区分本月、全部和今日', (tester) async {
    await tester.runAsync(
      () => db.insertBills([
        Bill(
          money: 20,
          type: 0,
          category: '餐饮',
          remark: '本月午饭',
          createTime: '$thisMonth-${now.day.toString().padLeft(2, '0')} 12:00',
        ),
        Bill(
          money: 80,
          type: 0,
          category: '交通',
          remark: '上月交通',
          createTime: '$lastMonth-01 12:00',
        ),
      ]),
    );
    await tester.pumpWidget(const MaterialApp(home: HomePage()));
    await settleDatabase(tester);
    expect(find.text('本月午饭'), findsOneWidget);
    expect(find.text('上月交通'), findsNothing);
    await tester.tap(find.text('全部'));
    await settleDatabase(tester);
    expect(find.text('上月交通'), findsOneWidget);
    await tester.tap(find.text('今日'));
    await settleDatabase(tester);
    expect(find.text('本月午饭'), findsOneWidget);
    expect(find.text('上月交通'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('分析页首次打开即显示真实统计和趋势', (tester) async {
    await tester.runAsync(
      () => db.insertBill(
        Bill(
          money: 25,
          type: 0,
          category: '餐饮',
          remark: '午饭',
          createTime: '$thisMonth-01 12:00',
        ),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: AiAnalysisPage()));
    await settleDatabase(tester);
    expect(find.text('$thisMonth 收支概览'), findsOneWidget);
    expect(find.text('¥25.00'), findsOneWidget);
    expect(find.text('近 6 个月收支趋势'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预算页可立即查看已保存的下月预算', (tester) async {
    final next = month(DateTime(now.year, now.month + 1));
    await tester.runAsync(
      () => db.saveBudget(
        Budget(totalBudget: 888, cateBudget: {'学习': 100}, month: next),
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: BudgetPage()));
    await settleDatabase(tester);
    await tester.tap(find.byTooltip('下个月'));
    await settleDatabase(tester);
    expect(find.text('预算管理（$next）'), findsOneWidget);
    expect(find.text('¥888.00'), findsOneWidget);
    expect(find.text('学习'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('深色主题下导航和账单采用主题颜色', (tester) async {
    SettingsService.themeMode = ThemeMode.dark;
    await tester.pumpWidget(const SmartLedgerApp());
    await settleDatabase(tester);
    final bar = tester.widget<BottomAppBar>(find.byType(BottomAppBar));
    final context = tester.element(find.byType(BottomAppBar));
    expect(bar.color, Theme.of(context).colorScheme.surface);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: const Scaffold(
          body: BillTile(
            bill: Bill(
              money: 10,
              type: 0,
              category: '餐饮',
              remark: '午饭',
              createTime: '2026-09-19 12:00',
            ),
          ),
        ),
      ),
    );
    final amount = tester.widget<Text>(find.text('-¥10.00'));
    expect(
      amount.style!.color,
      Theme.of(tester.element(find.byType(BillTile))).colorScheme.onSurface,
    );
    expect(tester.takeException(), isNull);
  });
  testWidgets('年度报告请求使用全年分类总额', (tester) async {
    SettingsService.customBaseUrl = 'https://test.invalid/v1/';
    SettingsService.customModel = 'test';
    SettingsService.customApiKey = 'test';
    SettingsService.mode = 'custom';
    await tester.runAsync(
      () => db.insertBills([
        Bill(
          money: 25,
          type: 0,
          category: '餐饮',
          remark: '本月',
          createTime: '$thisMonth-01 12:00',
        ),
        Bill(
          money: 75,
          type: 0,
          category: '餐饮',
          remark: '年内其他月',
          createTime: '${now.year}-${now.month == 1 ? "02" : "01"}-01 12:00',
        ),
      ]),
    );
    String? prompt;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const MaterialApp(home: AiAnalysisPage()));
        await settleDatabase(tester);
        await tester.scrollUntilVisible(find.text('年度报告'), 250);
        await tester.tap(find.text('年度报告'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('生成 AI 年度报告'), 150);
        await tester.tap(find.text('生成 AI 年度报告'));
        await settleDatabase(tester);
      },
      () => MockClient((request) async {
        expect(request.url.path, '/v1/chat/completions');
        prompt =
            (jsonDecode(request.body)['messages'] as List).last['content']
                as String;
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '# 年度消费报告'},
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    expect(prompt, contains('餐饮:100.00元'));
    expect(prompt, contains('总支出 100.0 元'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI 解析取消不入库，确认后仅保存勾选账单', (tester) async {
    SettingsService.customBaseUrl = 'https://test.invalid/v1';
    SettingsService.customModel = 'test';
    SettingsService.customApiKey = 'test';
    SettingsService.mode = 'custom';
    await http.runWithClient(
      () async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AddBillPage(),
                    ),
                  ),
                  child: const Text('打开记账'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('打开记账'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('AI 文本'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('午饭30 奶茶15'));
        await tester.ensureVisible(find.text('AI 解析并记账'));
        await tester.tap(find.text('AI 解析并记账'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('核对账单后保存'), findsOneWidget);
        expect(await tester.runAsync(db.queryBills), isEmpty);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(await tester.runAsync(db.queryBills), isEmpty);
        await tester.tap(find.text('AI 解析并记账'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byType(CheckboxListTile).last);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('确认保存 1 笔'));
        await settleDatabase(tester);
        final bills = await tester.runAsync(db.queryBills);
        expect(bills, hasLength(1));
        expect(bills!.single.money, 30);
        expect(tester.takeException(), isNull);
      },
      () => MockClient(
        (request) async => http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'content': jsonEncode([
                    {'money': 30, 'type': 0, 'category': '餐饮', 'remark': '午饭'},
                    {'money': 15, 'type': 0, 'category': '餐饮', 'remark': '奶茶'},
                  ]),
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );
  });
  testWidgets('手机尺寸下四个主页和深色模式无布局异常', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SmartLedgerApp());
    await settleDatabase(tester);
    for (final label in ['AI 分析', '预算', '我的', '首页']) {
      await tester.tap(
        find.descendant(
          of: find.byType(BottomAppBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    SettingsService.themeMode = ThemeMode.dark;
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
