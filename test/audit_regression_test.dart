import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_ledger/db/database_helper.dart';
import 'package:smart_ledger/pages/add_bill_page.dart';
import 'package:smart_ledger/pages/profile_page.dart';
import 'package:smart_ledger/pages/budget_page.dart';
import 'package:smart_ledger/pages/search_page.dart';
import 'package:smart_ledger/pages/ai_analysis_page.dart';
import 'package:smart_ledger/models/bill.dart';
import 'package:smart_ledger/common/global.dart';
import 'package:smart_ledger/services/llm_service.dart';
import 'package:smart_ledger/services/baidu_asr_service.dart';
import 'package:smart_ledger/services/export_service.dart';
import 'package:smart_ledger/services/settings_service.dart';

import 'test_database.dart';

http.Response reply(String text) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'content': text},
      },
    ],
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  late Directory directory;
  setUp(() async {
    directory = await setUpDatabase();
    await DatabaseHelper.instance.db;
  });
  tearDown(() async => tearDownDatabase(directory));

  test('语音服务异常明确报错而不是类型转换崩溃', () {
    for (final response in [
      http.Response('<html>bad gateway</html>', 502),
      http.Response('{}', 429),
      http.Response('not json', 200),
      http.Response('null', 200),
      http.Response('{"err_no":"3302"}', 200),
      http.Response('{"err_no":0,"result":[42]}', 200),
    ]) {
      expect(
        () => BaiduAsrService.parseResponse(response),
        throwsA(isA<AsrException>()),
      );
    }
    expect(
      BaiduAsrService.parseResponse(
        http.Response('{"err_no":0,"result":["test,"]}', 200),
      ),
      'test',
    );
  });

  test('CSV 文本转义包含分隔符、换行和公式前缀', () {
    expect(ExportService.csvText('饭, "两份"\n饮料'), '"饭, ""两份""\n饮料"');
    expect(ExportService.csvText('=1+1'), '"\'=1+1"');
    expect(ExportService.csvText('\t@SUM(A1)'), '"\'\t@SUM(A1)"');
  });

  test('AI 不合法分类归入其他，保留合法收支分类', () async {
    SettingsService.customBaseUrl = 'https://test.invalid/v1';
    SettingsService.customModel = 'test';
    SettingsService.customApiKey = 'test';
    SettingsService.mode = 'custom';
    final bills = await http.runWithClient(
      () => NlBillParser.parse('测试分类'),
      () => MockClient(
        (_) async => reply(
          jsonEncode([
            {'money': 10, 'type': 0, 'category': '工资'},
            {'money': 20, 'type': 1, 'category': '餐饮'},
            {'money': 30, 'type': 0, 'category': '未知'},
            {'money': 40, 'type': 1, 'category': '工资'},
          ]),
        ),
      ),
    );
    expect(bills.map((b) => b.category), ['其他', '其他', '其他', '工资']);
  });

  testWidgets('无效搜索金额不执行查询', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SearchPage()));
    await tester.enterText(find.byType(TextField).at(1), '100');
    await tester.enterText(find.byType(TextField).at(2), '20');
    await tester.tap(find.text('搜索').last);
    await tester.pumpAndSettle();
    expect(find.text('请输入有效金额范围，最低金额不能大于最高金额'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('预算错误保留表单，修正后保存', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: BudgetPage()));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '去设置预算'))
          .onPressed!();
    });
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'not-a-number');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('预算须为有效的非负金额'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '500');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    final now = DateTime.now();
    final budget = await tester.runAsync(
      () => DatabaseHelper.instance.getBudget(
        '${now.year}-${now.month.toString().padLeft(2, '0')}',
      ),
    );
    expect(budget?.totalBudget, 500);
    await tester.pumpAndSettle();
    expect(
      find.text('¥500.00'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data)
          .join('|'),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('生成期间账单发生变更时丢弃旧 AI 报告', (tester) async {
    SettingsService.customBaseUrl = 'https://test.invalid/v1';
    SettingsService.customModel = 'test';
    SettingsService.customApiKey = 'test';
    SettingsService.mode = 'custom';
    final now = DateTime.now();
    await tester.runAsync(
      () => DatabaseHelper.instance.insertBill(
        Bill(
          money: 10,
          type: 0,
          category: '餐饮',
          remark: '午饭',
          createTime:
              '${now.year}-${now.month.toString().padLeft(2, '0')}-01 12:00',
        ),
      ),
    );
    final response = Completer<http.Response>();
    var requested = false;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const MaterialApp(home: AiAnalysisPage()));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('生成 AI 月度报告'), 250);
        await tester.tap(find.text('生成 AI 月度报告'));
        for (var i = 0; i < 20 && !requested; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)),
          );
          await tester.pump();
        }
        expect(requested, isTrue);
        notifyDataChanged();
        response.complete(reply('# 已过期报告\n```json\n{"餐饮":100}\n```'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('已过期报告'), findsNothing);
        expect(find.textContaining('应用为'), findsNothing);
      },
      () => MockClient((_) {
        requested = true;
        return response.future;
      }),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('快速重复点击手动保存只写入一笔', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(builder: (_) => const AddBillPage()),
              ),
              child: const Text('记账'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('记账'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '25');
    final save = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
        .onPressed!;
    save();
    save();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(
      await tester.runAsync(DatabaseHelper.instance.queryBills),
      hasLength(1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('测试连接使用表单配置但不修改已保存的服务', (tester) async {
    SettingsService.customBaseUrl = 'https://saved.invalid/v1';
    SettingsService.customModel = 'saved-model';
    SettingsService.customApiKey = 'saved-test-key';
    SettingsService.mode = 'custom';
    final response = Completer<http.Response>();
    http.Request? sent;
    await http.runWithClient(
      () async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byType(TextField).at(0),
          'https://candidate.invalid/v1',
        );
        await tester.enterText(find.byType(TextField).at(1), 'candidate-model');
        await tester.enterText(
          find.byType(TextField).at(2),
          'candidate-test-key',
        );
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '测试连接'))
            .onPressed!();
        await tester.pump();
        try {
          expect(sent?.url.host, 'candidate.invalid');
          expect(SettingsService.baseUrl, 'https://saved.invalid/v1');
          expect(SettingsService.apiKey, 'saved-test-key');
        } finally {
          response.complete(reply('连接成功'));
          await tester.pumpAndSettle();
        }
      },
      () => MockClient((request) {
        sent = request;
        return response.future;
      }),
    );
    expect(tester.takeException(), isNull);
  });
}
