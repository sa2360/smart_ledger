import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';

/// 业务表整体替换；偏好设置通过数据库中的持久化待办恢复，崩溃后可重试。
class BackupService {
  static const preferenceKeys = [
    'bill_templates',
    'category_corrections',
    'theme_mode',
    'custom_base_url',
    'custom_model',
  ];

  static Future<Map<String, Object?>> snapshot() async {
    await finishPendingPreferences();
    final prefs = await SharedPreferences.getInstance();
    final db = await DatabaseHelper.instance.db;
    return db.transaction(
      (txn) async => {
        'app': 'yiyuji_ledger',
        'version': 2,
        'exported_at': DateTime.now().toIso8601String(),
        'bills': await txn.query('bill_table'),
        'budgets': await txn.query('budget_table'),
        'recurrings': await txn.query('recurring_table'),
        // API Key、token、设备标识不进入可分享的明文备份。
        'preferences': {
          for (final key in preferenceKeys) key: prefs.getString(key),
        },
      },
    );
  }

  static Future<int> restore(String content) async {
    final data = _validate(content);
    final db = await DatabaseHelper.instance.db;
    await db.transaction((txn) async {
      for (final entry in const {
        'bills': 'bill_table',
        'budgets': 'budget_table',
        'recurrings': 'recurring_table',
      }.entries) {
        await txn.delete(entry.value);
        for (final row in data[entry.key] as List<Map<String, Object?>>) {
          await txn.insert(entry.value, row);
        }
      }
      await txn.delete('restore_preferences');
      if (data['preferences'] != null) {
        await txn.insert('restore_preferences', {
          'id': 1,
          'payload': jsonEncode(data['preferences']),
        });
      }
    });
    await finishPendingPreferences();
    return (data['bills'] as List).length;
  }

  static Future<void> finishPendingPreferences() async {
    final db = await DatabaseHelper.instance.db;
    final pending = await db.query('restore_preferences');
    if (pending.isEmpty) return;
    final values = jsonDecode(pending.single['payload'] as String) as Map;
    final prefs = await SharedPreferences.getInstance();
    for (final key in preferenceKeys) {
      final value = values[key];
      final ok = value == null
          ? await prefs.remove(key)
          : await prefs.setString(key, value as String);
      if (!ok) throw Exception('设置恢复未完成，将在下次启动继续');
    }
    // 恢复接口配置时不能把旧设备的 Key 发送到新的接口；由用户重新配置。
    if (!await prefs.remove('custom_api_key') ||
        !await prefs.remove('llm_api_key') ||
        !await prefs.setString('ai_mode', 'builtin')) {
      throw Exception('设置恢复未完成，将在下次启动继续');
    }
    for (final key
        in prefs.getKeys().where((k) => k.startsWith('alert_')).toList()) {
      await prefs.remove(key);
    }
    await db.delete('restore_preferences');
  }

  static Map<String, Object?> _validate(String content) {
    try {
      final raw = jsonDecode(content);
      if (raw is! Map ||
          raw['app'] != 'yiyuji_ledger' ||
          ![1, 2].contains(raw['version'])) {
        throw const FormatException('备份标识或版本不支持');
      }
      final result = <String, Object?>{};
      for (final name in ['bills', 'budgets', 'recurrings']) {
        if (raw[name] is! List) throw FormatException('备份缺少 $name');
        final ids = <int>{};
        final months = <String>{};
        final rows = <Map<String, Object?>>[];
        for (final item in raw[name] as List) {
          final row = Map<String, Object?>.from(item as Map);
          final id = row['id'];
          if (id != null && (id is! int || id <= 0 || !ids.add(id))) {
            throw const FormatException('备份包含无效或重复 ID');
          }
          if (name == 'budgets') {
            final month = row['month'];
            if (month is! String ||
                !RegExp(r'^\d{4}-(0[1-9]|1[0-2])$').hasMatch(month) ||
                !months.add(month)) {
              throw const FormatException('预算月份无效或重复');
            }
            _amount(row['total_budget'], allowZero: true);
            final categories = jsonDecode(row['cate_budget'] as String) as Map;
            for (final value in categories.values) {
              _amount(value, allowZero: true);
            }
            _only(row, ['id', 'total_budget', 'cate_budget', 'month']);
          } else {
            _amount(row['money']);
            if (row['type'] is! int ||
                ![0, 1].contains(row['type']) ||
                row['category'] is! String ||
                (row['category'] as String).isEmpty ||
                row['remark'] is! String) {
              throw const FormatException('账单字段不合法');
            }
            if (name == 'bills') {
              _date(row['create_time'], time: true);
              _only(row, [
                'id',
                'money',
                'type',
                'category',
                'remark',
                'create_time',
              ]);
            } else {
              final cycle = row['cycle'];
              final day = row['day'];
              if (!['daily', 'weekly', 'monthly'].contains(cycle) ||
                  day is! int ||
                  (cycle == 'daily' && day != 0) ||
                  (cycle == 'weekly' && (day < 1 || day > 7)) ||
                  (cycle == 'monthly' && (day < 1 || day > 28)) ||
                  row['enabled'] is! int ||
                  ![0, 1].contains(row['enabled'])) {
                throw const FormatException('周期配置不合法');
              }
              if (row['last_run'] != '') _date(row['last_run']);
              _only(row, [
                'id',
                'money',
                'type',
                'category',
                'remark',
                'cycle',
                'day',
                'last_run',
                'enabled',
              ]);
            }
          }
          rows.add(row);
        }
        result[name] = rows;
      }
      if (raw['version'] == 2) {
        final prefs = Map<String, Object?>.from(raw['preferences'] as Map);
        for (final key in preferenceKeys) {
          if (!prefs.containsKey(key) ||
              (prefs[key] != null && prefs[key] is! String)) {
            throw const FormatException('备份设置不合法');
          }
        }
        if (prefs['theme_mode'] != null &&
            !['system', 'light', 'dark'].contains(prefs['theme_mode'])) {
          throw const FormatException('主题设置不合法');
        }
        for (final key in ['bill_templates', 'category_corrections']) {
          if (prefs[key] == null) continue;
          final items = jsonDecode(prefs[key] as String) as List;
          if (items.length > (key == 'bill_templates' ? 12 : 20)) {
            throw const FormatException('本地记录过多');
          }
          for (final item in items) {
            if (item is! Map || item['category'] is! String) {
              throw const FormatException('本地记录不合法');
            }
            if (key == 'bill_templates') {
              _amount(item['money']);
              if (![0, 1].contains(item['is_income']) ||
                  item['remark'] is! String) {
                throw const FormatException('模板不合法');
              }
            } else if (item['keyword'] is! String) {
              throw const FormatException('纠错记录不合法');
            }
          }
        }
        result['preferences'] = {
          for (final key in preferenceKeys) key: prefs[key],
        };
      }
      return result;
    } catch (e) {
      throw FormatException('备份校验失败，现有数据未更改：$e');
    }
  }

  static void _only(Map<String, Object?> row, List<String> keys) {
    row.removeWhere((key, _) => !keys.contains(key));
  }

  static void _amount(Object? value, {bool allowZero = false}) {
    if (value is! num ||
        !value.isFinite ||
        (allowZero ? value < 0 : value <= 0)) {
      throw const FormatException('金额必须是有限的有效数字');
    }
  }

  static void _date(Object? value, {bool time = false}) {
    final pattern = time
        ? r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$'
        : r'^\d{4}-\d{2}-\d{2}$';
    if (value is! String || !RegExp(pattern).hasMatch(value)) {
      throw const FormatException('日期格式错误');
    }
    final date = DateTime.tryParse(value);
    if (date == null ||
        date.toIso8601String().substring(0, 10) != value.substring(0, 10) ||
        (time &&
            date.toIso8601String().substring(11, 16) != value.substring(11))) {
      throw const FormatException('日期无效');
    }
  }
}
