import 'package:flutter/material.dart';

import '../../models/bill.dart';

/// 分类图标与颜色
const Map<String, IconData> categoryIcons = {
  '餐饮': Icons.restaurant,
  '交通': Icons.directions_bus,
  '购物': Icons.shopping_bag,
  '娱乐': Icons.sports_esports,
  '学习': Icons.menu_book,
  '医疗': Icons.local_hospital,
  '居住': Icons.home,
  '其他': Icons.category,
  '工资': Icons.work,
  '兼职': Icons.badge,
  '理财': Icons.savings,
  '红包': Icons.redeem,
};

const Map<String, Color> categoryColors = {
  '餐饮': Color(0xFFFF8A65),
  '交通': Color(0xFF4FC3F7),
  '购物': Color(0xFFFFB74D),
  '娱乐': Color(0xFFBA68C8),
  '学习': Color(0xFF4DB6AC),
  '医疗': Color(0xFFE57373),
  '居住': Color(0xFF90A4AE),
  '其他': Color(0xFFA1887F),
  '工资': Color(0xFF81C784),
  '兼职': Color(0xFFAED581),
  '理财': Color(0xFFFFD54F),
  '红包': Color(0xFFEF5350),
};

IconData iconOf(String category) =>
    categoryIcons[category] ?? Icons.category;

Color colorOf(String category) =>
    categoryColors[category] ?? const Color(0xFF9E9E9E);

/// 单条账单列表项
class BillTile extends StatelessWidget {
  final Bill bill;
  final VoidCallback? onTap;

  const BillTile({super.key, required this.bill, this.onTap});

  @override
  Widget build(BuildContext context) {
    final income = !bill.isExpense;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: colorOf(bill.category).withValues(alpha: .18),
              child: Icon(iconOf(bill.category),
                  size: 22, color: colorOf(bill.category)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.remark.isEmpty ? bill.category : bill.remark,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    '${bill.createTime.substring(11)} · ${bill.category}',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            Text(
              '${income ? '+' : '-'}¥${bill.money.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: income ? const Color(0xFF26A69A) : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 首页顶部统计卡片
class StatCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 4),
                Text(label,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ],
            ),
            const SizedBox(height: 6),
            Text('¥${value.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 17, fontWeight: FontWeight.bold, color: color),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
