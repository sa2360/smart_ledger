import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/budget.dart';
import '../models/recurring.dart';

/// 数据导出与备份恢复
/// 所有数据仅存本地：CSV 用于发给 Excel 查看，JSON 用于完整备份与恢复
class ExportService {
  ExportService._();

  /// 导出全部账单为 CSV（UTF-8 BOM，Excel 直接打开中文不乱码）
  static Future<void> exportCsv() async {
    final bills = await DatabaseHelper.instance.queryBills();
    final buf = StringBuffer()
      ..writeln('金额,类型,分类,备注,时间');
    for (final b in bills) {
      buf.writeln([
        b.money.toStringAsFixed(2),
        b.isExpense ? '支出' : '收入',
        b.category,
        '"${b.remark.replaceAll('"', '""')}"',
        b.createTime,
      ].join(','));
    }
    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/一语记账单_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.csv');
    await file.writeAsString('\uFEFF${buf.toString()}', encoding: utf8);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  /// 导出全量备份（账单 + 预算 + 周期配置）
  static Future<void> exportBackup() async {
    final db = DatabaseHelper.instance;
    final now = DateTime.now();
    final data = {
      'app': 'yiyuji_ledger',
      'version': 1,
      'exported_at': now.toIso8601String(),
      'bills': [for (final b in await db.queryBills()) b.toMap()],
      'budgets': await db.rawTable('budget_table'),
      'recurrings': await db.rawTable('recurring_table'),
    };

    final dir = await getTemporaryDirectory();
    final file = File(
        '${dir.path}/一语记备份_${now.year}${_p(now.month)}${_p(now.day)}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data),
        encoding: utf8);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  /// 从备份文件恢复（覆盖现有数据），返回恢复的账单条数
  static Future<int> restoreBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    final path = result?.files.single.path;
    if (path == null) return -1; // 用户取消

    final content = await File(path).readAsString();
    final dynamic decoded;
    try {
      decoded = jsonDecode(content);
    } catch (_) {
      throw const FormatException('不是有效的备份文件');
    }
    if (decoded is! Map || decoded['app'] != 'yiyuji_ledger') {
      throw const FormatException('不是「一语记」的备份文件');
    }
    final billsRaw = (decoded['bills'] as List?) ?? const [];
    final budgetsRaw = (decoded['budgets'] as List?) ?? const [];
    final recurringsRaw = (decoded['recurrings'] as List?) ?? const [];

    final db = DatabaseHelper.instance;
    await db.clearAllForRestore();
    final bills = [
      for (final m in billsRaw)
        Bill.fromMap(Map<String, Object?>.from(m as Map)),
    ];
    // 分批插入
    for (var i = 0; i < bills.length; i += 200) {
      final end = (i + 200) < bills.length ? i + 200 : bills.length;
      await db.insertBills(bills.sublist(i, end));
    }
    for (final m in budgetsRaw) {
      await db.saveBudget(
          Budget.fromMap(Map<String, Object?>.from(m as Map)));
    }
    for (final m in recurringsRaw) {
      // 保留原 lastRun，避免恢复后重复入账
      await db.insertRecurring(
          Recurring.fromMap(Map<String, Object?>.from(m as Map)));
    }
    return bills.length;
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}
