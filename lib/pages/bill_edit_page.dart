import 'package:flutter/material.dart';

import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../services/local_stores.dart';
import 'widgets/common.dart';

/// 账单修改 / 删除
class BillEditPage extends StatefulWidget {
  final Bill bill;
  const BillEditPage({super.key, required this.bill});

  @override
  State<BillEditPage> createState() => _BillEditPageState();
}

class _BillEditPageState extends State<BillEditPage> {
  late final Bill _bill = widget.bill;
  late final TextEditingController _moneyCtrl =
      TextEditingController(text: _bill.money.toStringAsFixed(2));
  late final TextEditingController _remarkCtrl =
      TextEditingController(text: _bill.remark);
  late bool _expense = _bill.isExpense;
  late String _category = _bill.category;

  static const _expenseCates = ['餐饮', '交通', '购物', '娱乐', '学习', '医疗', '居住', '其他'];
  static const _incomeCates = ['工资', '兼职', '理财', '红包', '其他'];

  @override
  void dispose() {
    _moneyCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: const Text('账单详情', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: context.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: colorOf(_category).withValues(alpha: .18),
                      child: Icon(iconOf(_category),
                          color: colorOf(_category)),
                    ),
                    const SizedBox(width: 12),
                    Text(_bill.createTime,
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade600)),
                  ],
                ),
                const SizedBox(height: 14),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: true, label: Text('支出')),
                    ButtonSegment(value: false, label: Text('收入')),
                  ],
                  selected: {_expense},
                  onSelectionChanged: (s) => setState(() {
                    _expense = s.first;
                    _category =
                        _expense ? _expenseCates.first : _incomeCates.first;
                  }),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _moneyCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    prefixText: '¥ ',
                    prefixStyle: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.bold),
                    filled: true,
                    fillColor: const Color(0xFFF8F9FB),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (_expense ? _expenseCates : _incomeCates)
                      .map((c) => ChoiceChip(
                            label: Text(c),
                            selected: _category == c,
                            selectedColor: colorOf(c).withValues(alpha: .25),
                            onSelected: (_) =>
                                setState(() => _category = c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _remarkCtrl,
                  decoration: InputDecoration(
                    hintText: '备注',
                    filled: true,
                    fillColor: const Color(0xFFF8F9FB),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF1E88E5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14))),
            onPressed: _save,
            child: const Text('保存修改', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final money = double.tryParse(_moneyCtrl.text.trim());
    if (money == null || money <= 0) return;
    // 分类纠错学习：用户改了分类且备注非空时记录下来，
    // 之后自然语言解析会参考这些「备注关键词→正确分类」
    if (_category != _bill.category && _remarkCtrl.text.trim().isNotEmpty) {
      await CorrectionStore.add(_remarkCtrl.text.trim(), _category);
    }
    await DatabaseHelper.instance.updateBill(_bill.copyWith(
      money: money,
      type: _expense ? 0 : 1,
      category: _category,
      remark: _remarkCtrl.text.trim(),
    ));
    notifyDataChanged();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('删除账单'),
        content: const Text('确定要删除这条账单吗？删除后不可恢复。'),
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
      await DatabaseHelper.instance.deleteBill(_bill.id!);
      notifyDataChanged();
      if (mounted) Navigator.pop(context);
    }
  }
}
