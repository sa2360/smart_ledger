import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/budget.dart';
import '../services/llm_service.dart';
import '../services/settings_service.dart';
import 'widgets/chart.dart';
import 'widgets/common.dart';

/// AI 分析页：月度消费报告 + 省钱建议 + 下月预算方案（可一键应用）
class AiAnalysisPage extends StatefulWidget {
  const AiAnalysisPage({super.key});

  @override
  State<AiAnalysisPage> createState() => _AiAnalysisPageState();
}

class _AiAnalysisPageState extends State<AiAnalysisPage> {
  bool _loading = false;
  String? _report; // AI 报告（Markdown）
  Map<String, double> _plan = {};
  Map<String, double> _cateSpend = {};
  double _expense = 0, _income = 0;
  String _month = '';

  @override
  void initState() {
    super.initState();
    refreshSignal.addListener(_onSignal);
  }

  @override
  void dispose() {
    refreshSignal.removeListener(_onSignal);
    super.dispose();
  }

  void _onSignal() {
    if (mounted) {
      setState(() {
        _report = null;
        _plan = {};
      });
      _loadStats();
    }
  }

  static String _p(int n) => n.toString().padLeft(2, '0');

  Future<void> _loadStats() async {
    final now = DateTime.now();
    final month = '${now.year}-${_p(now.month)}';
    final db = DatabaseHelper.instance;
    final results = await Future.wait([
      db.sumOfMonth(0, month),
      db.sumOfMonth(1, month),
      db.categorySpendOfMonth(month),
    ]);
    if (!mounted) return;
    setState(() {
      _month = month;
      _expense = results[0] as double;
      _income = results[1] as double;
      _cateSpend = results[2] as Map<String, double>;
    });
  }

  Future<void> _analyze() async {
    if (SettingsService.apiKey.isEmpty) {
      _toast('AI 服务未就绪，请到「我的」页开启内置模型或配置自定义模型');
      return;
    }
    await _loadStats();
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final month = '${now.year}-${_p(now.month)}';
      final bills = await DatabaseHelper.instance.queryBills(month: month);
      final budget =
          await DatabaseHelper.instance.getBudget(month);
      if (bills.isEmpty) {
        _toast('本月还没有账单记录，先记几笔再来分析吧');
        return;
      }
      final (report, plan) = await MonthlyAnalyzer.analyze(
        month: month,
        bills: bills,
        monthExpense: _expense,
        monthIncome: _income,
        categorySpend: _cateSpend,
        currentBudget: budget,
      );
      setState(() {
        _report = report;
        _plan = plan;
      });
    } on LlmException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('分析失败：$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 把 AI 生成的下月预算写入数据库
  Future<void> _applyPlan() async {
    if (_plan.isEmpty) return;
    final now = DateTime.now();
    final next = now.month == 12
        ? DateTime(now.year + 1, 1)
        : DateTime(now.year, now.month + 1);
    final month = '${next.year}-${_p(next.month)}';
    final total = _plan.values.fold<double>(0, (s, v) => s + v);
    await DatabaseHelper.instance.saveBudget(Budget(
      totalBudget: total,
      cateBudget: _plan,
      month: month,
    ));
    notifyDataChanged();
    _toast('已应用 $month 预算方案，可在预算页查看');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('AI 消费分析',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('AI 正在阅读你的整月账单…',
                      style: TextStyle(color: Colors.black54)),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _statsCard(),
                const SizedBox(height: 12),
                if (_cateSpend.isNotEmpty) ...[
                  _card(Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('本月分类支出占比',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 12),
                      CategoryPieChart(data: _cateSpend),
                    ],
                  )),
                  const SizedBox(height: 12),
                ],
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF7E57C2),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14))),
                  onPressed: _analyze,
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(_report == null ? '生成 AI 月度报告' : '重新生成报告',
                      style: const TextStyle(fontSize: 16)),
                ),
                if (_report != null) ...[
                  const SizedBox(height: 14),
                  _reportCard(),
                ],
                if (_plan.isNotEmpty) _planCard(),
              ],
            ),
    );
  }

  Widget _statsCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF7E57C2), Color(0xFF5E35B1)]),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_month 收支概览',
                style: TextStyle(
                    fontSize: 12, color: Colors.white.withValues(alpha: .85))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('支出',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: .75))),
                      Text('¥${_expense.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ]),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('收入',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: .75))),
                      Text('¥${_income.toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ]),
              ),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('结余',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: .75))),
                      Text('¥${(_income - _expense).toStringAsFixed(2)}',
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white)),
                    ]),
              ),
            ]),
          ],
        ),
      );

  Widget _reportCard() => _card(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.auto_awesome, size: 18, color: Color(0xFF7E57C2)),
            SizedBox(width: 6),
            Text('AI 消费报告',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ]),
          const Divider(height: 20),
          SizedBox(
            width: double.infinity,
            child: MarkdownBody(
              data: _report!,
              selectable: true,
              styleSheet: MarkdownStyleSheet(
                h1: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                h2: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                p: const TextStyle(fontSize: 13.5, height: 1.55),
                listBullet: const TextStyle(fontSize: 13.5, height: 1.5),
              ),
            ),
          ),
        ],
      ));

  Widget _planCard() => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF7E57C2), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.account_balance_wallet,
                  size: 18, color: Color(0xFF7E57C2)),
              SizedBox(width: 6),
              Text('下月预算方案',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 10),
            ..._plan.entries.map((e) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(iconOf(e.key),
                        size: 18, color: colorOf(e.key)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.key,
                        style: const TextStyle(fontSize: 13.5))),
                    Text('¥${e.value.toStringAsFixed(2)}',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w600)),
                  ]),
                )),
            const Divider(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('合计',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              Text(
                  '¥${_plan.values.fold<double>(0, (s, v) => s + v).toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Color(0xFF7E57C2))),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7E57C2)),
                onPressed: _applyPlan,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('一键应用为下月预算'),
              ),
            ),
          ],
        ),
      );

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: child,
      );

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }
}
