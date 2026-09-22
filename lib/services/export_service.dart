import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import 'backup_service.dart';
import 'settings_service.dart';

/// 数据导出与备份恢复
/// CSV 用于查看，JSON 备份业务数据、模板、纠错及非敏感设置
class ExportService {
  ExportService._();

  /// 导出全部账单为 CSV（UTF-8 BOM，Excel 直接打开中文不乱码）
  static Future<void> exportCsv() async {
    final bills = await DatabaseHelper.instance.queryBills();
    final buf = StringBuffer()..writeln('金额,类型,分类,备注,时间');
    for (final b in bills) {
      buf.writeln(
        [
          b.money.toStringAsFixed(2),
          b.isExpense ? '支出' : '收入',
          b.category,
          '"${b.remark.replaceAll('"', '""')}"',
          b.createTime,
        ].join(','),
      );
    }
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/一语记账单_${DateTime.now().millisecondsSinceEpoch ~/ 1000}.csv',
    );
    await file.writeAsString('\uFEFF${buf.toString()}', encoding: utf8);
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
  }

  /// 导出全量备份（账单 + 预算 + 周期配置）
  static Future<void> exportBackup() async {
    final now = DateTime.now();
    final data = await BackupService.snapshot();

    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/一语记备份_${now.year}${_p(now.month)}${_p(now.day)}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(data),
      encoding: utf8,
    );
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
    final count = await BackupService.restore(content);
    await SettingsService.init();
    return count;
  }

  static String _p(int n) => n.toString().padLeft(2, '0');
}
