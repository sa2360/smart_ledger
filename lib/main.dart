import 'package:flutter/material.dart';

import 'common/global.dart';
import 'pages/add_bill_page.dart';
import 'pages/ai_analysis_page.dart';
import 'pages/budget_page.dart';
import 'pages/home_page.dart';
import 'pages/profile_page.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.init();
  runApp(const SmartLedgerApp());
}

class SmartLedgerApp extends StatelessWidget {
  const SmartLedgerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '一语记 · 智能收支记账',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1E88E5)),
        scaffoldBackgroundColor: const Color(0xFFF3F4F6),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF3F4F6),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
      ),
      home: const MainPage(),
    );
  }
}

/// 主框架：首页 / AI 分析 / 记账 / 预算 / 我的
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _index = 0;

  static const _pages = [
    HomePage(),
    AiAnalysisPage(),
    BudgetPage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AddBillPage()));
          notifyDataChanged();
        },
        backgroundColor: const Color(0xFF1E88E5),
        shape: const CircleBorder(),
        child: const Icon(Icons.add, color: Colors.white, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        color: Colors.white,
        child: Row(
          children: [
            _item(0, Icons.home_rounded, Icons.home_outlined, '首页'),
            _item(1, Icons.insights_rounded, Icons.insights_outlined, 'AI 分析'),
            const Spacer(),
            _item(2, Icons.account_balance_wallet_rounded,
                Icons.account_balance_wallet_outlined, '预算'),
            _item(3, Icons.person_rounded, Icons.person_outline, '我的'),
          ],
        ),
      ),
    );
  }

  Widget _item(int i, IconData filled, IconData outlined, String label) {
    final selected = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _index = i),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(selected ? filled : outlined,
                size: 24,
                color: selected
                    ? const Color(0xFF1E88E5)
                    : Colors.grey.shade500),
            Text(label,
                style: TextStyle(
                    fontSize: 11,
                    color: selected
                        ? const Color(0xFF1E88E5)
                        : Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }
}
