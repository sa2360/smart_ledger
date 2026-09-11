import 'package:flutter/material.dart';

import '../common/global.dart';
import '../services/export_service.dart';
import '../services/llm_service.dart';
import '../services/settings_service.dart';
import 'recurring_page.dart';
import 'widgets/common.dart';

/// 我的页：AI 服务配置（内置模型免配置 / 自定义模型）+ 外观 + 数据管理 + 关于信息
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  late final TextEditingController _urlCtrl =
      TextEditingController(text: SettingsService.customBaseUrl);
  late final TextEditingController _modelCtrl =
      TextEditingController(text: SettingsService.customModel);
  late final TextEditingController _keyCtrl =
      TextEditingController(text: SettingsService.customApiKey);
  bool _obscure = true;
  bool _testing = false;
  bool _dataBusy = false;

  @override
  void dispose() {
    _urlCtrl.dispose();
    _modelCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bg,
      appBar: AppBar(
        title: const Text('我的', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.auto_awesome, size: 18, color: Color(0xFF1E88E5)),
                  SizedBox(width: 6),
                  Text('AI 服务',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
                const SizedBox(height: 4),
                Text(
                  '自然语言记账、小票解析、月度报告均由 AI 完成，'
                  '推荐语种为中文。所有 Key 仅保存在本机，不会上传任何服务器。',
                  style: TextStyle(
                      fontSize: 12.5, color: Colors.grey.shade600, height: 1.5),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<int>(
                  valueListenable: SettingsService.configListenable,
                  builder: (_, _, _) => _statusChip(),
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<int>(
                  valueListenable: SettingsService.configListenable,
                  builder: (_, _, _) => Column(children: [
                    _modeTile(
                      value: 'builtin',
                      title: '内置智能模型（默认）',
                      subtitle: '开箱即用，无需任何配置',
                      icon: Icons.bolt,
                    ),
                    _modeTile(
                      value: 'custom',
                      title: '自定义模型',
                      subtitle: '使用自己的 AI 服务（OpenAI 兼容接口）',
                      icon: Icons.tune,
                    ),
                  ]),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: SettingsService.configListenable,
                  builder: (_, _, _) =>
                      SettingsService.useCustom ? _customForm() : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _appearanceCard(),
          const SizedBox(height: 14),
          _dataCard(),
          const SizedBox(height: 14),
          InkWell(
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecurringPage())),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_repeat,
                      size: 20, color: Color(0xFF1E88E5)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('周期记账',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 14)),
                        SizedBox(height: 2),
                        Text('房租、订阅等固定收支，到期自动入账',
                            style:
                                TextStyle(fontSize: 12, color: context.subtext)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.grey),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline, size: 18, color: Color(0xFF1E88E5)),
                  SizedBox(width: 6),
                  Text('关于',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                ]),
                SizedBox(height: 10),
                Text('一语记 · 智能收支记账',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                SizedBox(height: 2),
                Text('一句话，记好账',
                    style: TextStyle(
                        fontSize: 12,
                        color: Color(0xFF1E88E5),
                        fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text(
                  '· 本地 SQLite 持久化存储，断网可正常记账\n'
                  '· AI 自然语言记账 / 小票解析 / 月度分析\n'
                  '· 端上离线 OCR（ML Kit）+ 大模型语义解析\n'
                  '· 账单数据仅存本地，不上传第三方服务器',
                  style: TextStyle(fontSize: 12.5, height: 1.7),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 外观设置卡片：深色模式
  Widget _appearanceCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: context.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(children: [
              Icon(Icons.dark_mode, size: 18, color: Color(0xFF1E88E5)),
              SizedBox(width: 6),
              Text('外观',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ]),
            const SizedBox(height: 10),
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
                ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
              ],
              selected: {SettingsService.themeMode},
              onSelectionChanged: (s) => SettingsService.themeMode = s.first,
            ),
          ],
        ),
      );

  /// 数据管理卡片：导出 CSV / 备份 / 恢复
  Widget _dataCard() => Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: context.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            _dataTile(
              icon: Icons.table_view,
              title: '导出账单 CSV',
              subtitle: '生成表格文件，可发送到电脑用 Excel 查看',
              onTap: _busyGuard(() async {
                await ExportService.exportCsv();
                _toast('已生成 CSV，请在弹出的分享面板中选择保存位置');
              }),
            ),
            Divider(height: 1, color: context.divider),
            _dataTile(
              icon: Icons.backup,
              title: '备份数据',
              subtitle: '账单 + 预算 + 周期配置打包为 JSON 文件',
              onTap: _busyGuard(() async {
                await ExportService.exportBackup();
                _toast('备份已生成，请在分享面板中保存');
              }),
            ),
            Divider(height: 1, color: context.divider),
            _dataTile(
              icon: Icons.restore,
              title: '恢复备份',
              subtitle: '选择备份 JSON 文件，将覆盖当前全部数据',
              onTap: _busyGuard(_restoreFlow),
            ),
          ],
        ),
      );

  VoidCallback _busyGuard(Future<void> Function() action) => () async {
        if (_dataBusy) return;
        setState(() => _dataBusy = true);
        try {
          await action();
        } on Exception catch (e) {
          _toast(_friendlyError(e));
        } finally {
          if (mounted) setState(() => _dataBusy = false);
        }
      };

  String _friendlyError(Exception e) {
    final msg = e.toString();
    if (msg.contains('FormatException')) {
      final inner = msg.contains('FormatException: ')
          ? msg.split('FormatException: ').last
          : '文件格式不正确';
      return inner;
    }
    if (msg.contains('permission') || msg.contains('Permission')) {
      return '没有文件访问权限，请检查系统权限设置';
    }
    return '操作失败：$msg';
  }

  Future<void> _restoreFlow() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('恢复备份'),
        content: const Text('将从备份文件恢复账单、预算和周期配置，'
            '并清空当前全部数据。此操作不可撤销，确定继续吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('继续')),
        ],
      ),
    );
    if (ok != true) return;
    final count = await ExportService.restoreBackup();
    if (count < 0) {
      _toast('已取消选择文件');
      return;
    }
    notifyDataChanged();
    _toast('恢复完成，共导入 $count 条账单');
  }

  Widget _dataTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: _dataBusy ? null : onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          child: Row(children: [
            Icon(icon, size: 20, color: const Color(0xFF1E88E5)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style:
                          TextStyle(fontSize: 11.5, color: context.subtext)),
                ],
              ),
            ),
            if (_dataBusy)
              const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
      );

  Widget _statusChip() {
    final custom = SettingsService.useCustom;
    final ready = SettingsService.isReady;
    final (text, color) = !ready
        ? (
            custom ? '未配置：请填写接口地址、模型名称和 API Key' : '当前安装包未内置 AI 服务，请切换到自定义模型',
            Colors.orange
          )
        : custom
            ? ('已就绪：自定义模型（${SettingsService.model}）', Colors.green)
            : ('已就绪：内置智能模型', Colors.green);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(children: [
        Icon(ready ? Icons.check_circle : Icons.info, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text,
              style: TextStyle(fontSize: 12, color: color.shade700)),
        ),
      ]),
    );
  }

  Widget _modeTile({
    required String value,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final selected = SettingsService.mode == value;
    return InkWell(
      onTap: () => SettingsService.mode = value,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE3F2FD) : const Color(0xFFF8F9FB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? const Color(0xFF1E88E5) : Colors.transparent,
              width: 1.2),
        ),
        child: Row(children: [
          Icon(selected
              ? Icons.check_circle
              : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? const Color(0xFF1E88E5) : Colors.grey.shade400),
          const SizedBox(width: 8),
          Icon(icon, size: 18, color: selected ? const Color(0xFF1E88E5) : Colors.grey),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal)),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: 11.5, color: Colors.grey.shade600)),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _customForm() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 20),
          TextField(
            controller: _urlCtrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: '接口地址（Base URL）',
              hintText: 'https://api.example.com/v1',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _modelCtrl,
            decoration: const InputDecoration(
              labelText: '模型名称',
              hintText: '例如 gpt-4o-mini、qwen-plus 等',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _keyCtrl,
            obscureText: _obscure,
            decoration: InputDecoration(
              labelText: 'API Key',
              hintText: 'sk-...',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF1E88E5)),
                onPressed: _saveCustom,
                child: const Text('保存并启用'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _testing ? null : _testConnection,
              child: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('测试连接'),
            ),
          ]),
        ],
      );

  Future<void> _saveCustom() async {
    final url = _urlCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || model.isEmpty || key.isEmpty) {
      _toast('接口地址、模型名称、API Key 都不能为空');
      return;
    }
    SettingsService.customBaseUrl = url;
    SettingsService.customModel = model;
    SettingsService.customApiKey = key;
    SettingsService.mode = 'custom';
    _toast('已保存，AI 服务已切换为自定义模型');
  }

  Future<void> _testConnection() async {
    // 测试前先暂存当前表单内容
    final url = _urlCtrl.text.trim();
    final model = _modelCtrl.text.trim();
    final key = _keyCtrl.text.trim();
    if (url.isEmpty || model.isEmpty || key.isEmpty) {
      _toast('请先填写完整：接口地址、模型名称、API Key');
      return;
    }
    setState(() => _testing = true);
    final restore = (
      SettingsService.customBaseUrl,
      SettingsService.customModel,
      SettingsService.customApiKey,
      SettingsService.mode
    );
    SettingsService.customBaseUrl = url;
    SettingsService.customModel = model;
    SettingsService.customApiKey = key;
    SettingsService.mode = 'custom';
    try {
      await LlmService.chat('请回复：连接成功',
          temperature: 0, system: '你是连通性测试工具，只原样返回用户消息。');
      if (mounted) _toast('连接成功，模型响应正常');
    } catch (e) {
      if (mounted) _toast('连接失败：$e');
    } finally {
      // 恢复测试前已保存的配置（测试内容不一定保存）
      SettingsService.customBaseUrl = restore.$1;
      SettingsService.customModel = restore.$2;
      SettingsService.customApiKey = restore.$3;
      SettingsService.mode = restore.$4;
      if (mounted) setState(() => _testing = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }
}
