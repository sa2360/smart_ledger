import '../common/global.dart';
import '../db/database_helper.dart';
import '../models/bill.dart';
import '../models/recurring.dart';

/// 周期记账执行服务
/// App 启动 / 首页刷新时检查所有启用的周期项，
/// 把从上次执行日到今天之间的每一期补记入账（支持错过若干天后一次性补齐）。
class RecurringService {
  RecurringService._();

  /// 执行所有到期任务，返回本次补记的账单条数
  static Future<int> runDueBills() async {
    final db = DatabaseHelper.instance;
    final list = await db.queryRecurrings(enabledOnly: true);
    final today = _dateOnly(DateTime.now());
    var inserted = 0;

    for (final r in list) {
      final last = r.lastRun.isEmpty ? null : DateTime.tryParse(r.lastRun);
      var cursor = last;
      var changed = false;
      var guard = 0;

      // 逐期推进：每一期生成一条账单，直到下一期超过今天
      while (guard++ < 400) {
        final next = _nextDue(r, cursor, today);
        if (next == null || next.isAfter(today)) break;
        final t = next;
        await db.insertBill(Bill(
          money: r.money,
          type: r.type,
          category: r.category,
          remark: r.remark.isEmpty ? '周期记账' : r.remark,
          createTime:
              '${t.year}-${_p(t.month)}-${_p(t.day)} 08:00',
        ));
        inserted++;
        cursor = next;
        changed = true;
      }
      if (changed) {
        await db.updateRecurring(r.copyWith(
          lastRun:
              '${cursor!.year}-${_p(cursor.month)}-${_p(cursor.day)}',
        ));
      }
    }

    if (inserted > 0) notifyDataChanged();
    return inserted;
  }

  /// 计算下一次应执行的日期；无法计算时返回 null
  static DateTime? _nextDue(Recurring r, DateTime? last, DateTime today) {
    switch (r.cycle) {
      case 'daily':
        return last ?? today;
      case 'weekly':
        if (last == null) {
          // 锚定本周的目标星期几；若已过则从下周开始
          final monday = today.subtract(Duration(days: today.weekday - 1));
          var candidate = monday.add(Duration(days: r.day - 1));
          if (candidate.isBefore(today)) candidate = candidate.add(const Duration(days: 7));
          return candidate;
        }
        return last.add(const Duration(days: 7));
      case 'monthly':
      default:
        if (last == null) {
          final day = r.day.clamp(1, 28);
          var candidate = DateTime(today.year, today.month, day);
          if (candidate.isBefore(today)) {
            candidate = _addMonth(candidate, day);
          }
          return candidate;
        }
        return _addMonth(last, r.day.clamp(1, 28));
    }
  }

  static DateTime _addMonth(DateTime from, int day) {
    final y = from.month == 12 ? from.year + 1 : from.year;
    final m = from.month == 12 ? 1 : from.month + 1;
    return DateTime(y, m, day);
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _p(int n) => n.toString().padLeft(2, '0');
}
