import 'package:flutter/material.dart';

import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/recurring.dart';
import 'widgets/common.dart';

/// 周期记账管理页：房租、订阅等固定收支自动入账
class RecurringPage extends StatefulWidget {
  const RecurringPage({super.key});

  @override
  State<RecurringPage> createState() => _RecurringPageState();
}

class _RecurringPageState extends State<RecurringPage> {
  List<Recurring> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await DatabaseHelper.instance.queryRecurrings();
    if (!mounted) return;
    setState(() {
      _list = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: const Text('周期记账',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        backgroundColor: const Color(0xFF1E88E5),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_repeat,
                          size: 56, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('还没有周期记账项',
                          style: TextStyle(color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      Text('房租、话费、视频会员这类固定收支可以自动入账',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade400)),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    for (final r in _list) _item(r),
                    const SizedBox(height: 8),
                    Center(
                      child: Text('到期后 App 启动时会自动记入账单',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                    ),
                  ],
                ),
    );
  }

  Widget _item(Recurring r) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: context.card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => _edit(r),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor:
                        colorOf(r.category).withValues(alpha: .18),
                    child: Icon(iconOf(r.category),
                        size: 22, color: colorOf(r.category)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.remark.isEmpty ? r.category : r.remark,
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          '${r.cycleLabel} · ${r.isExpense ? "支出" : "收入"}'
                          ' · 上次执行：${r.lastRun.isEmpty ? "未执行" : r.lastRun}',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${r.isExpense ? "-" : "+"}¥${r.money.toStringAsFixed(2)}',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: r.isExpense ? Colors.black87 : const Color(0xFF26A69A)),
                  ),
                  const SizedBox(width: 6),
                  Switch(
                    value: r.enabled == 1,
                    activeThumbColor: const Color(0xFF1E88E5),
                    onChanged: (v) async {
                      await DatabaseHelper.instance
                          .updateRecurring(r.copyWith(enabled: v ? 1 : 0));
                      notifyDataChanged();
                      _load();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _delete(r),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(Recurring? r) async {
    final moneyCtrl =
        TextEditingController(text: r == null ? '' : r.money.toStringAsFixed(2));
    final remarkCtrl =
        TextEditingController(text: r == null ? '' : r.remark);
    var isExpense = r?.isExpense ?? true;
    var category = r?.category ?? '餐饮';
    var cycle = r?.cycle ?? 'monthly';
    var day = r?.day ?? 1;

    const expenseCates = ['餐饮', '交通', '购物', '娱乐', '学习', '医疗', '居住', '其他'];
    const incomeCates = ['工资', '兼职', '理财', '红包', '其他'];

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(r == null ? '新建周期记账' : '编辑周期记账'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('支出')),
                    ButtonSegment(value: false, label: Text('收入')),
                  ],
                  selected: {isExpense},
                  onSelectionChanged: (s) => setDialogState(() {
                    isExpense = s.first;
                    category = isExpense ? expenseCates.first : incomeCates.first;
                  }),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: moneyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: '金额（元）', prefixText: '¥ '),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: remarkCtrl,
                  decoration: const InputDecoration(
                      labelText: '备注', hintText: '如：房租 / 视频会员'),
                ),
                const SizedBox(height: 12),
                Text('分类',
                    style: TextStyle(fontSize: 13, color: context.subtext)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: (isExpense ? expenseCates : incomeCates)
                      .map((c) => ChoiceChip(
                            label: Text(c),
                            selected: category == c,
                            onSelected: (_) =>
                                setDialogState(() => category = c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: cycle,
                  decoration: const InputDecoration(labelText: '重复周期'),
                  items: const [
                    DropdownMenuItem(value: 'daily', child: Text('每天')),
                    DropdownMenuItem(value: 'weekly', child: Text('每周')),
                    DropdownMenuItem(value: 'monthly', child: Text('每月')),
                  ],
                  onChanged: (v) => setDialogState(() => cycle = v ?? 'monthly'),
                ),
                if (cycle == 'weekly') ...[
                  const SizedBox(height: 12),
                  Text('星期',
                      style: TextStyle(fontSize: 13, color: context.subtext)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) => i + 1)
                        .map((d) => ChoiceChip(
                              label: Text('周${'一二三四五六日'[d - 1]}'),
                              selected: day == d,
                              onSelected: (_) => setDialogState(() => day = d),
                            ))
                        .toList(),
                  ),
                ],
                if (cycle == 'monthly') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: day.clamp(1, 28),
                    decoration:
                        const InputDecoration(labelText: '每月几号（1-28）'),
                    items: List.generate(28, (i) => i + 1)
                        .map((d) => DropdownMenuItem(
                            value: d, child: Text('$d 日')))
                        .toList(),
                    onChanged: (v) => setDialogState(() => day = v ?? 1),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final money = double.tryParse(moneyCtrl.text.trim());
    if (money == null || money <= 0) {
      _toast('请输入正确的金额');
      return;
    }
    final item = (r ?? const Recurring(
      money: 0,
      type: 0,
      category: '',
      remark: '',
      cycle: 'monthly',
      day: 1,
    )).copyWith(
      money: money,
      type: isExpense ? 0 : 1,
      category: category,
      remark: remarkCtrl.text.trim(),
      cycle: cycle,
      day: cycle == 'daily' ? 0 : day,
    );
    if (r == null) {
      await DatabaseHelper.instance.insertRecurring(item);
    } else {
      await DatabaseHelper.instance.updateRecurring(item);
    }
    notifyDataChanged();
    _load();
  }

  Future<void> _delete(Recurring r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除周期记账'),
        content: Text('删除「${r.remark.isEmpty ? r.category : r.remark}」后不再自动入账，'
            '已生成的账单不受影响。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await DatabaseHelper.instance.deleteRecurring(r.id!);
      notifyDataChanged();
      _load();
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }
}
